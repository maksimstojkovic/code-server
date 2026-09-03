# syntax=docker/dockerfile:1

# Default only silences the InvalidDefaultArgInFrom lint; CI always passes
# the real pin from versions.env (single source of truth).
ARG CODE_SERVER_VERSION=4.135.0
FROM ghcr.io/coder/code-server:${CODE_SERVER_VERSION}

ARG OPENCODE_VERSION

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        vim \
        python3 \
        python3-pip \
        python3-venv \
        tzdata \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Install the pinned opencode release
RUN HOME=/usr/local/share/opencode-install \
    curl -fsSL https://opencode.ai/install | HOME=/usr/local/share/opencode-install bash -s -- --version "${OPENCODE_VERSION}" \
    && cp /usr/local/share/opencode-install/.opencode/bin/opencode /usr/local/bin/opencode \
    && chmod +x /usr/local/bin/opencode \
    && opencode --version | grep -q "${OPENCODE_VERSION}"

# OSC 52 clipboard fix: makes terminal clipboard writes (opencode drag-select
# copy, tmux, etc.) reach the real browser clipboard in code-server's web
# client. See patches/osc52-web.sh. The build fails if the upstream bundle no
# longer matches the pattern, so updates cannot silently regress.
COPY patches/osc52-web.sh /tmp/osc52-web.sh
RUN BUNDLE="$(find /usr/lib/code-server -type f -name 'workbench.web.main.internal.js')" \
    && [ "$(echo "$BUNDLE" | wc -l)" -eq 1 ] \
    && bash /tmp/osc52-web.sh "$BUNDLE" \
    && rm /tmp/osc52-web.sh

# Startup hooks directory (runs after fixuid, before code-server). The base
# image's default ENTRYPOINTD location is under $HOME, which is shadowed by
# the mounted volume, so it is moved to /usr/local/share/entrypoint.d.
# Kept as an extension point; empty by default.
RUN mkdir -p /usr/local/share/entrypoint.d
ENV ENTRYPOINTD=/usr/local/share/entrypoint.d

# Wrapper entrypoint: enables PUID/PGID/DEFAULT_WORKSPACE as plain environment
# variables (the stock entrypoint hard-codes "." as the workspace and relies
# on docker "user:" for the runtime UID).
COPY scripts/entrypoint-wrapper.sh /usr/local/bin/entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/entrypoint-wrapper.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-wrapper.sh"]

USER 1000
