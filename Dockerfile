# syntax=docker/dockerfile:1

# --- builder stage: build a wheelhouse, keep build tools out of the final image ---
FROM python:3.14-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip wheel --no-cache-dir --wheel-dir /build/wheels -r requirements.txt


# --- runtime stage: small, no compilers, non-root ---
FROM python:3.14-slim AS runtime

# libpq5 is the runtime client lib psycopg2 needs; libpq-dev/build-essential
# from the builder stage are NOT copied into this image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /usr/sbin/nologin --create-home app

WORKDIR /app

COPY --from=builder /build/wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && \
    rm -rf /wheels

COPY --chown=app:app . .

USER app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/healthz', timeout=2).status==200 else 1)"

# 2 workers is plenty for a learning project; tune via WEB_CONCURRENCY in
# a real deployment. Binding to 0.0.0.0 is expected here — the container
# network, not the host, is the trust boundary (see terraform/ecs.tf and
# terraform/alb.tf for what's actually exposed to the internet).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "wsgi:app"]
