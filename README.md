# DevSecOps Notes App

A small, real Flask + PostgreSQL notes app, used as a vehicle to build and
run a full DevSecOps pipeline: secrets scanning, SAST, dependency
scanning, container scanning, IaC scanning, and DAST — deployed to real
AWS infrastructure via Terraform and GitHub Actions.

The app itself is deliberately simple (register, log in, create/edit/
delete notes). The point of this project is everything *around* it.

## Contents

- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Repo layout](#repo-layout)
- [Local development](#local-development)
- [The security pipeline (`ci.yml`)](#the-security-pipeline-ciyml)
  - [Running each tool locally](#running-each-tool-locally)
- [Deploying to AWS](#deploying-to-aws)
  - [One-time setup](#one-time-setup)
  - [How a deploy actually happens](#how-a-deploy-actually-happens)
- [DAST (`dast.yml`)](#dast-dastyml)
- [Adding SonarQube later](#adding-sonarqube-later)
- [Known simplifications](#known-simplifications--what-a-production-version-would-add)
- [Suggested learning path](#suggested-learning-path)

## Architecture

```
                           ┌────────────────────────────────────-------
  GitHub Actions           │              AWS (us-east-1)             │
  ─────────────            │                                          │
  ci.yml (every PR)        │   Internet                               │
    lint+test              │      │                                   │
    secrets scan           │      ▼                                   │
    SAST (semgrep)         │   ALB :80  (public subnets)              │
    dependency scan        │      │                                   │
    build+scan image       │      ▼                                   │
    IaC scan (checkov)     │   ECS Fargate task (public subnets,      │
                           │     no NAT Gateway — see below)          │
  cd.yml (main, after CI)  │      │           │                       │
    terraform apply        │      ▼           ▼                       │
    build, scan, push      │   RDS Postgres  Secrets Manager          │
    → ECR                  │   (private      (FLASK_SECRET_KEY,       │
    ECS deploy             │    subnets,      RDS master password)    │
                           │    no NAT)                               │
  dast.yml (post-deploy)   │                                          │
    OWASP ZAP baseline →   │
                            ──────────────────────────────────────────┘
    scans the live ALB URL
```

## Tech stack

- **App**: Python, Flask, SQLAlchemy, Flask-Login, Flask-WTF, Jinja2 templates, vanilla CSS
- **Database**: PostgreSQL
- **Container**: Docker (multi-stage, non-root)
- **CI/CD**: GitHub Actions
- **IaC**: Terraform, AWS (VPC, ALB, ECS Fargate, RDS, ECR, Secrets Manager, IAM, VPC Flow Logs)
- **Security tooling**: gitleaks (secrets), Semgrep (SAST), pip-audit + Dependabot (dependencies), Trivy (container), Checkov (IaC), OWASP ZAP (DAST)

## Repo layout

```
app/                  Flask application (factory pattern)
  routes/              auth.py, notes.py
  templates/           Jinja2 templates
  static/              CSS
tests/                 pytest suite (13 tests, 96% coverage of app/)
terraform/             Main infra: VPC, ALB, ECS, RDS, ECR, IAM, Secrets Manager
  bootstrap/           One-time module: GitHub OIDC provider + deploy IAM role
.github/
  workflows/ci.yml      Lint, test, secrets/SAST/dependency/container/IaC scans
  workflows/cd.yml       Deploy to AWS (Terraform + ECS)
  workflows/dast.yml     OWASP ZAP baseline scan against the live deployment
  dependabot.yml         Weekly PRs for pip, Docker, GitHub Actions, Terraform deps
.checkov.yaml           Documented IaC-scan baseline (what's skipped, and why)
sonar-project.properties  Ready for when you add SonarQube (see below)
Dockerfile, docker-compose.yml
```

## Local development

Requires Docker. Copy the env file and start everything:

```bash
cp .env.example .env
# generate a real secret: python -c "import secrets; print(secrets.token_hex(32))"
# paste it in as FLASK_SECRET_KEY in .env

docker compose up --build
```

This starts Postgres, runs `flask init-db` to create tables, and starts
the app at http://localhost:5000.

To run it without Docker:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
docker compose up -d db          # just the database
flask --app wsgi init-db
flask --app wsgi run
```

Run the tests:

```bash
pytest          # 13 tests, prints a coverage summary
ruff check .     # lint
```

## The security pipeline (`ci.yml`)

Every push/PR to `main` runs six jobs, mostly in parallel:

| Job | Tool | Catches |
|---|---|---|
| `lint-and-test` | ruff, pytest | Bugs, basic security lint rules (`S` rules — flake8-bandit equivalent) |
| `secrets-scan` | gitleaks | Committed API keys, tokens, private keys — scans full git history |
| `sast-semgrep` | Semgrep | Real vuln patterns in app code: SQLi, SSRF, unsafe deserialization, etc. |
| `dependency-scan` | pip-audit | Known CVEs in `requirements.txt` |
| `build-and-scan-image` | Trivy | Vulnerable OS packages in the built Docker image (not just Python deps) |
| `iac-scan` | Checkov | Terraform misconfigurations (open security groups, missing encryption, etc.) |

Every job that produces SARIF output uploads it to the repo's **Security**
tab (Settings → Security → Code scanning), so findings show up alongside
your code, not just in a build log.

### Running each tool locally

```bash
# Secrets — no license needed for this one-off local run:
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest \
  detect --source /repo --verbose

# SAST:
pip install semgrep
semgrep scan --config=p/ci --config=p/security-audit --config=p/python --config=p/flask

# Dependencies:
pip install pip-audit
pip-audit -r requirements.txt

# Container (after `docker build -t devsecops-notes-app .`):
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image devsecops-notes-app

# IaC:
pip install checkov
checkov -d terraform --config-file .checkov.yaml
```

`.checkov.yaml` is worth reading — it's a real example of how a team
triages IaC scan findings: 31 checks are explicitly skipped, each with a
one-line reason (cost, "not applicable to a single-account learning
project", "here's the variable that turns it on"). Re-run checkov
*without* `--config-file` to see the full, un-triaged list.

## Deploying to AWS

### One-time setup

You only do this once, locally, with your own AWS credentials (not in
CI — CI doesn't have any credentials yet at this point).

**1. Remote Terraform state** (required — see the comment in `cd.yml` for why):

```bash
aws s3api create-bucket --bucket YOUR-UNIQUE-NAME-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket YOUR-UNIQUE-NAME-tfstate \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket YOUR-UNIQUE-NAME-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST

cp terraform/backend.tf.example terraform/backend.tf
# edit the bucket name in it, then:
cd terraform && terraform init -migrate-state && cd ..
git add terraform/backend.tf && git commit -m "Add remote state backend"
```

**2. GitHub OIDC role** (lets GitHub Actions authenticate to AWS with no
stored access keys):

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="github_org=YOUR_GITHUB_USERNAME" -var="github_repo=YOUR_REPO_NAME"
terraform output github_actions_role_arn
```

Copy that ARN into the repo's GitHub secrets as `AWS_ROLE_ARN`
(Settings → Secrets and variables → Actions → New repository secret).

**3. (Optional but recommended) Require approval before deploys:**
Settings → Environments → New environment → name it `production` → add
yourself as a required reviewer. `cd.yml` already references this
environment, so it'll start gating automatically once it exists.

**4. Push to `main`.** `ci.yml` runs, and once it passes, `cd.yml` picks
up and deploys.

### How a deploy actually happens

`cd.yml` does a **two-phase apply** to solve a bootstrapping problem: the
ECS service needs an image to exist in ECR before it can start, but
Terraform needs to create the ECR repo before an image can be pushed to
it.

1. `terraform apply -target=aws_ecr_repository.app` — just the ECR repo
2. Build the app image, scan it with Trivy again (defense in depth — same
   gate as `ci.yml`, run again against what's about to actually ship),
   push it to ECR tagged with the git commit SHA
3. `terraform apply -var="app_image_tag=<sha>"` — everything else,
   pointing the ECS task definition at the image just pushed
4. Force a fresh ECS deployment and wait for it to stabilize

Every deploy is tagged and traceable to an exact commit — no `:latest`
floating tag in production.

## DAST (`dast.yml`)

Runs an OWASP ZAP **baseline** scan (passive — crawls the app and
inspects responses, doesn't attempt exploitation) against whatever's
currently deployed: automatically after every successful deploy, weekly
on a schedule, or on demand via workflow_dispatch (with an optional
`target_url` override to scan somewhere other than the live deployment).

Once you're comfortable reading its findings, a natural next step is
ZAP's **full/active scan** (`zaproxy/action-full-scan`), which actually
attempts common attacks — only run that against environments you're
prepared to have knocked over or filled with test data.

## Adding SonarQube later

You said Semgrep for now, SonarQube later — here's the two-step path
when you're ready:

1. Get a `SONAR_TOKEN`: easiest is [SonarCloud](https://sonarcloud.io)
   (free for public repos) — create a project there, generate a token.
   Self-hosting SonarQube instead? You'll also need a `SONAR_HOST_URL`
   secret pointing at it.
2. Add `SONAR_TOKEN` (and `SONAR_HOST_URL` if self-hosted) as repo
   secrets, then uncomment the `sonarqube` job at the bottom of
   `.github/workflows/ci.yml`.

`sonar-project.properties` is already in the repo root, pointed at
`app/`, `wsgi.py`, `config.py`, and wired to read `tests`' coverage
output. Semgrep and SonarQube aren't redundant even though both do
SAST — Semgrep is fast and rule-transparent (you can read exactly which
pattern matched), SonarQube adds code-quality/maintainability metrics
and a persistent dashboard across scans. Running both is a completely
normal real-world setup.

## Known simplifications — what a production version would add

Being upfront about every corner cut, so it reads as "decisions", not
gaps you'd discover the hard way:

- **HTTP only, no HTTPS.** No domain name / ACM certificate in this
  project. `terraform/alb.tf` has the exact steps to add a 443 listener;
  flip `FORCE_HTTPS_COOKIES=true` in `terraform/ecs.tf` once you do.
- **No NAT Gateway.** ECS tasks sit in public subnets with public IPs
  instead (locked down to ALB-only ingress via security groups) to skip
  the ~$32/mo NAT Gateway cost. Production would use private subnets +
  NAT (or VPC endpoints for ECR/Secrets Manager/CloudWatch, which avoids
  the NAT cost too and is arguably the better answer either way).
- **Single AZ, single task, no autoscaling.** `desired_count = 1`,
  `db_multi_az = false`. Both are one variable away from real
  availability — see `terraform/variables.tf`.
- **Broad-ish IAM policy for the GitHub Actions deploy role**
  (`terraform/bootstrap/main.tf`) — Terraform needs to manage a lot of
  resource types end to end. The mitigating control is the OIDC trust
  policy: that role can only be assumed by workflow runs on this repo's
  `main` branch, nothing else. Splitting into a narrow read-only "plan"
  role (used on PRs) and a separately-approved "apply" role is the
  natural next step.
- **AWS-managed encryption keys, not customer-managed KMS CMKs**, on
  ECR/CloudWatch/Secrets Manager. Still encrypted at rest; a CMK mainly
  buys per-key audit trails and cross-account key policies.
- **No WAF in front of the ALB.** Real cost ($5+/mo minimum) for a
  personal project; add `aws_wafv2_web_acl` + associate it with the ALB
  when this stops being a learning exercise.

## Suggested learning path

1. Get it running locally with `docker compose up`, poke at the app.
2. Push a branch, open a PR, watch `ci.yml` run. Read the Security tab.
3. Deliberately break something and watch a scanner catch it — try each
   of these on a scratch branch, one at a time, and revert after:
   - Remove `.gitignore`'s `.env` line, commit a fake-looking API key → gitleaks
   - Change a note query to raw SQL string concatenation → Semgrep
   - Pin a known-vulnerable version of a dependency → pip-audit/Trivy
   - Open the RDS security group to `0.0.0.0/0` → Checkov
   - Remove the security headers in `app/__init__.py` → ZAP
4. Do the AWS setup above and get a real deploy working end to end.
5. Read `.checkov.yaml` and `terraform/bootstrap/main.tf` end to end —
   they're written as much to be read as to be run.
6. Add SonarQube, compare what it flags vs. Semgrep on the same code.
7. From there: WAF, HTTPS, a narrower IAM split, autoscaling — pick one
   from "Known simplifications" above and implement it yourself.
