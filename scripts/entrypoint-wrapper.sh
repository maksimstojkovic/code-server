#!/bin/sh
# Entrypoint wrapper for the code-server image.
#
# Makes PUID/PGID configurable as plain environment variables
# (LinuxServer-style) instead of requiring a docker "user:" override:
#
# 1. When started as root (the default), remap the built-in "coder" user to
#    $PUID/$PGID, apply a one-time ownership fix to the mounted home if the
#    runtime UID/GID changed, then drop privileges and hand off to the stock
#    coder entrypoint (which runs fixuid, the ENTRYPOINTD hooks, DOCKER_USER
#    handling and launches code-server).
# 2. When started as a non-root user, just hand off unchanged.
#
# The default workspace is /home/coder/workspace (configurable via
# DEFAULT_WORKSPACE); it is created if missing.
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
BIND_ADDR="${BIND_ADDR:-0.0.0.0:8080}"
DEFAULT_WORKSPACE="${DEFAULT_WORKSPACE:-/home/coder/workspace}"
AUTH="${AUTH:-password}"

case "${AUTH}" in
    password|none) ;;
    *)
        echo "entrypoint-wrapper: invalid AUTH '${AUTH}' (supported: password, none)" >&2
        exit 1
        ;;
esac

# Docker derives HOME from the container user in /etc/passwd; when started as
# root it stays /root, so pin the coder user's real home before any exec.
export HOME=/home/coder
export USER=coder
export LOGNAME=coder

if [ "$(id -u)" = "0" ]; then
    if [ "${PUID}" = "0" ]; then
        echo "entrypoint-wrapper: PUID=0 (root) is not supported" >&2
        exit 1
    fi

    # Remap the coder user/group (-o allows non-unique ids, e.g. reusing the
    # host "users" group gid).
    if [ "$(id -u coder)" != "${PUID}" ]; then
        usermod -o -u "${PUID}" coder
    fi
    if [ "$(id -g coder)" != "${PGID}" ]; then
        groupmod -o -g "${PGID}" coder
    fi

    # One-time ownership fix after a PUID/PGID change; no-op otherwise.
    if [ "$(stat -c %u /home/coder)" != "${PUID}" ] || [ "$(stat -c %g /home/coder)" != "${PGID}" ]; then
        echo "entrypoint-wrapper: /home/coder ownership (${PUID}:${PGID} expected) - applying chown -R"
        chown -R "$(id -u coder):$(id -g coder)" /home/coder
    fi

    mkdir -p "${DEFAULT_WORKSPACE}"
    chown "$(id -u coder):$(id -g coder)" "${DEFAULT_WORKSPACE}" 2>/dev/null || true

    exec setpriv --reuid="$(id -u coder)" --regid="$(id -g coder)" --init-groups \
        /usr/bin/entrypoint.sh --auth "${AUTH}" --bind-addr "${BIND_ADDR}" "${DEFAULT_WORKSPACE}"
fi

exec /usr/bin/entrypoint.sh --auth "${AUTH}" --bind-addr "${BIND_ADDR}" "${DEFAULT_WORKSPACE}"
