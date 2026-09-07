resource "aws_ecr_repository" "app" {
  name = var.project_name
  # MUTABLE (not IMMUTABLE) so the CD pipeline's two-phase apply works:
  # it applies just this repo first, pushes the image, then applies the
  # rest of the stack. See .github/workflows/cd.yml and README.md.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    # Basic scanning on every push — a second, AWS-native layer of
    # container scanning on top of the Trivy scan that already runs in
    # ci.yml before the image is even pushed here.
    scan_on_push = true
  }

  tags = { Name = var.project_name }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 15 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 15
        }
        action = { type = "expire" }
      }
    ]
  })
}
