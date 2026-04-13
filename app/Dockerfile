# Multi-stage build for the Money Honey FastAPI backend.
# Stage 1 installs dependencies into a clean virtualenv.
# Stage 2 copies only the venv and app code into a minimal runtime image.

FROM python:3.14-slim-bookworm AS builder

WORKDIR /build

# Install build tools needed by faiss-cpu and other wheels
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


FROM python:3.14-slim-bookworm AS runtime

# Pull any Debian package fixes released since the base image tag was
# cut. Belt-and-suspenders against CVE drift between tag refreshes
# (e.g. CVE-2026-28390 in libssl3 was patched after the 3.12-slim-bookworm
# pin we're on). Cleans apt lists to keep the image small.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Non-root user per CLAUDE.md Dockerfile rules
RUN useradd --create-home --uid 10001 honey

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=honey:honey . /app

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER honey

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
