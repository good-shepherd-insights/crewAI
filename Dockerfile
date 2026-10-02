# syntax=docker/dockerfile:1

# ---- base ------------------------------------------------------------------
FROM python:3.13-slim@sha256:bb2988715db2cf7ace7b53f38f3cffbef7c7046a656bee66245eb0ed386e2e81 AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN apt-get update && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

# ---- builder ----------------------------------------------------------------
FROM base AS builder
COPY --from=ghcr.io/astral-sh/uv:0.11.15@sha256:e590846f4776907b254ac0f44b5b380347af5d90d668138ca7938d1b0c2f98d3 /uv /usr/local/bin/uv
WORKDIR /src
# uv sync --frozen resolves strictly from uv.lock and builds the workspace
# packages from this tree, so the installed set matches what CI would resolve.
COPY pyproject.toml uv.lock README.md ./
COPY lib/crewai-core/ lib/crewai-core/
COPY lib/crewai-files/ lib/crewai-files/
COPY lib/cli/ lib/cli/
COPY lib/devtools/ lib/devtools/
COPY lib/crewai-tools/ lib/crewai-tools/
COPY lib/crewai/ lib/crewai/
# Note: do not narrow this with --package. The `crewai` console script imports
# crewai_cli, so a crewai+crewai-tools-only sync produces a broken entrypoint.
# --no-editable is mandatory: the default sync installs the workspace packages as
# .pth files pointing at /src, which does not exist in the runtime stage, so the
# copied venv fails with ModuleNotFoundError on first import.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

# ---- runtime ----------------------------------------------------------------
FROM base AS runtime
RUN useradd --create-home --uid 10001 crewai
COPY --from=builder --chown=crewai:crewai /opt/venv /opt/venv
USER crewai
WORKDIR /home/crewai
LABEL org.opencontainers.image.title="crewai" \
      org.opencontainers.image.source="https://github.com/good-shepherd-insights/crewAI" \
      org.opencontainers.image.version="1.15.23" \
      org.opencontainers.image.licenses="MIT"
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["crewai", "--help"]
ENTRYPOINT ["crewai"]
CMD ["--help"]