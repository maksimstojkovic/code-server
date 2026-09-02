#!/usr/bin/env bash
# OSC 52 clipboard fix for code-server's web client.
#
# Root cause: VS Code's xterm ClipboardAddon provider maps terminal clipboard
# writes to IClipboardService.writeText(text, 'clipboard'). In the web
# clipboard service (BrowserClipboardService.writeText) any write that passes
# a selection type is stored in-memory only ("With type: only in-memory is
# supported") and never reaches navigator.clipboard. Desktop VS Code uses a
# different clipboard service, which is why OSC 52 copy works there but not in
# code-server. Passing the write untyped makes it go to the real browser
# clipboard.
#
# This script rewrites the minified provider mapping inside
# workbench.web.main.internal.js:
#   g.writeText(L,x==="p"?"selection":"clipboard")
#     -> g.writeText(L,x==="p"?"selection":void 0)
# (the readText mapping is left untouched)
#
# Exits non-zero if the pattern is missing or the patch does not apply, so a
# code-server update that changes the minification fails the Docker build
# loudly instead of silently shipping without the fix.
set -euo pipefail

BUNDLE="${1:?usage: osc52-web.sh <path-to-workbench.web.main.internal.js>}"
[ -f "$BUNDLE" ] || { echo "osc52-web: file not found: $BUNDLE" >&2; exit 1; }

VAR='[A-Za-z_$][A-Za-z0-9_$]*'
PATTERN="writeText\\(${VAR},(${VAR}===\"p\"|\"p\"===${VAR})\\?\"selection\":\"clipboard\"\\)"
PATCHED_PATTERN="writeText\\(${VAR},(${VAR}===\"p\"|\"p\"===${VAR})\\?\"selection\":void 0\\)"

BEFORE=$(grep -oE "$PATTERN" "$BUNDLE" | wc -l || true)
if [ "$BEFORE" -ne 1 ]; then
    echo "osc52-web: expected exactly 1 writeText provider mapping, found ${BEFORE}." >&2
    echo "osc52-web: upstream minification changed - update the pattern in this script." >&2
    echo "osc52-web: locate the ClipboardAddon createInstance call in the bundle and" >&2
    echo "osc52-web: compare with src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts (upstream VS Code)." >&2
    exit 1
fi

sed -E -i "s/(writeText\\(${VAR},(${VAR}===\"p\"|\"p\"===${VAR})\\?\"selection\":)\"clipboard\"/\\1void 0/" "$BUNDLE"

AFTER=$(grep -oE "$PATTERN" "$BUNDLE" | wc -l || true)
DONE=$(grep -oE "$PATCHED_PATTERN" "$BUNDLE" | wc -l || true)
if [ "$AFTER" -ne 0 ] || [ "$DONE" -ne 1 ]; then
    echo "osc52-web: patch did not apply cleanly (remaining=${AFTER}, patched=${DONE})" >&2
    exit 1
fi

echo "osc52-web: patched ${BUNDLE}"
echo "osc52-web: OSC 52 terminal clipboard writes now reach the browser clipboard"
