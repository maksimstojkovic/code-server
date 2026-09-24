#!/bin/sh
# Seeds opencode defaults on first run (never overrides user-set values):
#  - a default model from OPENCODE_MODEL
#  - zero-data-retention on the OpenRouter provider (OPENCODE_ZDR, default on)
#  - 9Router (self-hosted OpenAI-compatible gateway) when N9ROUTER_BASE_URL set
#  - Tavily MCP server when TAVILY_API_KEY is set
set -eu

MODEL="${OPENCODE_MODEL:-}"
case "${OPENCODE_ZDR:-}" in
    false|0|no|FALSE|No|False) ZDR=0 ;;
    *) ZDR=1 ;;
esac
TAVILY_KEY="${TAVILY_API_KEY:-}"
TAVILY_URL="${TAVILY_MCP_URL:-https://mcp.tavily.com/mcp}"
N9_BASE="${N9ROUTER_BASE_URL:-}"
N9_MODEL="${N9ROUTER_MODEL:-}"

if [ -z "${MODEL}" ] && [ "${ZDR}" != "1" ] && [ -z "${TAVILY_KEY}" ] && [ -z "${N9_BASE}" ]; then
    exit 0
fi

CONFIG_DIR="${HOME}/.config/opencode"
CONFIG="${CONFIG_DIR}/opencode.json"

mkdir -p "${CONFIG_DIR}"
[ -f "${CONFIG}" ] || printf '{}\n' > "${CONFIG}"

python3 - "$CONFIG" "${MODEL}" "${ZDR}" "${TAVILY_KEY}" "${TAVILY_URL}" "${N9_BASE}" "${N9_MODEL}" <<'EOF'
import json, os, sys, tempfile

path, model, zdr, tavily_key, tavily_url, n9_base, n9_model = sys.argv[1:8]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"opencode-config: cannot parse {path} ({e}); leaving untouched")
    raise SystemExit(0)

changed = []

if model:
    # OPENCODE_MODEL is the source of truth for the default model, so it is
    # re-applied on every start (updates propagate on restart).
    if cfg.get("model") != model:
        cfg["model"] = model
        changed.append(f"model={model}")

if zdr == "1":
    body = cfg.setdefault("provider", {}).setdefault("openrouter", {}).setdefault("body", {})
    prov = body.setdefault("provider", {})
    if "zdr" not in prov:
        prov["zdr"] = True
        changed.append("openrouter ZDR")

if n9_base and "9router" not in cfg.setdefault("provider", {}):
    entry = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "9Router",
        "options": {
            "baseURL": n9_base,
            "apiKey": "{env:N9ROUTER_API_KEY}",
        },
    }
    if n9_model:
        entry["models"] = {n9_model: {"name": n9_model}}
    cfg["provider"]["9router"] = entry
    changed.append("9router provider")

if tavily_key and "tavily" not in cfg.setdefault("mcp", {}):
    cfg["mcp"]["tavily"] = {
        "type": "remote",
        "url": tavily_url,
        "enabled": True,
        "headers": {"Authorization": "Bearer {env:TAVILY_API_KEY}"},
    }
    changed.append("tavily mcp")

if not changed:
    raise SystemExit(0)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
print("opencode-config: " + ", ".join(changed))
EOF

