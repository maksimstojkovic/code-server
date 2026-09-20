#!/bin/sh
# Starts the opencode web server in the background when OPENCODE_WEB is
# enabled. Runs before code-server takes over as the main process, so the
# web server keeps serving alongside code-server in the same container.
set -eu

case "${OPENCODE_WEB:-}" in
    1|true|yes|TRUE|YES|True) ;;
    *) exit 0 ;;
esac

PORT="${OPENCODE_WEB_PORT:-4096}"
HOSTNAME="${OPENCODE_WEB_HOSTNAME:-0.0.0.0}"
WORKDIR="${DEFAULT_WORKSPACE:-/home/coder/workspace}"
LOG="${OPENCODE_WEB_LOG:-/home/coder/opencode-web.log}"

# The real binary path, bypassing the /usr/local/bin/opencode wrapper (which
# would otherwise wait/probe for this very server before starting it).
OPCODE_BIN="${OPCODE_REAL_BIN:-/usr/local/lib/opencode/opencode}"
if [ ! -x "${OPCODE_BIN}" ]; then
    OPCODE_BIN="$(command -v opencode)"
fi

echo "opencode-web: starting 'opencode serve' on ${HOSTNAME}:${PORT} (workdir ${WORKDIR})"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# Detach so it survives this hook and code-server becoming the main process.
setsid nohup "${OPCODE_BIN}" serve \
    --hostname "${HOSTNAME}" \
    --port "${PORT}" \
    --print-logs \
    >>"${LOG}" 2>&1 </dev/null &
echo "opencode-web: pid $! (logs: ${LOG})"
