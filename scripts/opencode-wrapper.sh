#!/usr/bin/env bash
# opencode wrapper for the code-server image.
#
# When the container's opencode web server is enabled (OPENCODE_WEB=true),
# the terminal `opencode` command attaches to that server, so the TUI and the
# web interface share the same sessions and state. Otherwise it behaves
# exactly like the real opencode binary.
set -eu

REAL="${OPENCODE_REAL_BIN:-/usr/local/lib/opencode/opencode}"

web_enabled() {
    case "${OPENCODE_WEB:-}" in
        true|TRUE|True|1|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

if ! web_enabled; then
    exec "$REAL" "$@"
fi

URL="${OPENCODE_SERVER_URL:-http://127.0.0.1:${OPENCODE_WEB_PORT:-4096}}"

# The web server starts at container boot, before code-server, so it is
# normally already up; wait briefly in case of a race.
for _ in $(seq 1 5); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 "${URL}/doc" 2>/dev/null || true)
    [ -n "${code}" ] && [ "${code}" != "000" ] && break
    sleep 1
done

# Server unreachable: fall back to a standalone server like the real binary.
if [ -z "${code:-}" ] || [ "${code:-000}" = "000" ]; then
    echo "opencode: web server not reachable at ${URL}; starting a standalone server" >&2
    exec "$REAL" "$@"
fi

first="${1:-}"
if [ -z "${first}" ]; then
    exec "$REAL" attach "${URL}" "$@"
fi

case "${first}" in
    serve|web|attach|acp|mcp|models|completion|--version|-v|--help|-h)
        exec "$REAL" "$@" ;;
    run)
        shift
        exec "$REAL" run --attach "${URL}" "$@" ;;
    -*)
        exec "$REAL" attach "${URL}" "$@" ;;
    *)
        exec "$REAL" attach "${URL}" --dir "${first}" "${@:2}" ;;
esac