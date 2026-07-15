# syntax=docker/dockerfile:1.7

ARG PYTHON_VERSION=3.12

# uv 0.11.28, pinned to its multi-platform OCI index digest.
FROM ghcr.io/astral-sh/uv:0.11.28@sha256:0f36cb9361a3346885ca3677e3767016687b5a170c1a6b88465ec14aefec90aa AS uv

FROM python:${PYTHON_VERSION}-slim-trixie AS builder

COPY --from=uv /uv /uvx /bin/
COPY apt-runtime.txt apt-build.txt /tmp/packages/

RUN set -eux; \
    runtime_packages="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages/apt-runtime.txt | tr '\n' ' ')"; \
    build_packages="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages/apt-build.txt | tr '\n' ' ')"; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        procps \
        ${runtime_packages} \
        ${build_packages}; \
    rm -rf /var/lib/apt/lists/* /tmp/packages

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /build
COPY pyproject.toml uv.lock .python-version ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project --no-editable

FROM python:${PYTHON_VERSION}-slim-trixie AS runtime

COPY apt-runtime.txt /tmp/packages/apt-runtime.txt

RUN set -eux; \
    runtime_packages="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages/apt-runtime.txt | tr '\n' ' ')"; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        procps \
        ${runtime_packages}; \
    rm -rf /var/lib/apt/lists/* /tmp/packages; \
    chmod 1777 /tmp

COPY --from=builder /opt/venv /opt/venv

ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

WORKDIR /work

CMD ["/bin/bash"]
