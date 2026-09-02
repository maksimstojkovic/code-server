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

USER 1000
