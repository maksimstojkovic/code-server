#!/bin/sh
# Seeds opencode defaults on first run (never overrides user-set values):
#  - a default model from OPENCODE_MODEL
#  - zero-data-retention on the OpenRouter provider (OPENCODE_ZDR, default on)
#  - 9Router (self-hosted OpenAI-compatible gateway) when N9ROUTER_BASE_URL set
#  - Tavily MCP server when TAVILY_API_KEY is set
#  - Outline MCP server when OUTLINE_API_KEY is set
#  - Actual Budget MCP server when ACTUAL_MCP_TOKEN is set
#  - a local LLM provider (OpenAI-compatible, e.g. Ollama/LM Studio) when
#    LOCAL_LLM_BASE_URL and LOCAL_LLM_MODEL are set
set -eu

N9_BASE="${N9ROUTER_BASE_URL:-}"
N9_MODEL="${N9ROUTER_MODEL:-}"
N9_PROVIDER="${N9ROUTER_PROVIDER:-9router}"
LOCAL_BASE="${LOCAL_LLM_BASE_URL:-}"
LOCAL_MODEL="${LOCAL_LLM_MODEL:-}"
LOCAL_NAME="${LOCAL_LLM_NAME:-}"
LOCAL_PROVIDER="${LOCAL_LLM_PROVIDER:-local}"

# Default model resolution: a 9Router model takes precedence when 9Router is
# enabled and N9ROUTER_MODEL is set (so it becomes the web server's default);
# otherwise OPENCODE_MODEL is used. Applied on every start. The model is shown
# as "<N9ROUTER_PROVIDER>/<N9ROUTER_MODEL>" so a custom provider name is used
# and the model ID may itself contain slashes.
DEFAULT_MODEL="${OPENCODE_MODEL:-}"
if [ -n "${N9_BASE}" ] && [ -n "${N9_MODEL}" ]; then
    DEFAULT_MODEL="${N9_PROVIDER}/${N9_MODEL}"
fi
case "${OPENCODE_ZDR:-}" in
    false|0|no|FALSE|No|False) ZDR=0 ;;
    *) ZDR=1 ;;
esac
TAVILY_KEY="${TAVILY_API_KEY:-}"
TAVILY_URL="${TAVILY_MCP_URL:-https://mcp.tavily.com/mcp}"
OUTLINE_KEY="${OUTLINE_API_KEY:-}"
OUTLINE_URL="${OUTLINE_MCP_URL:-https://outline.example.com/mcp}"
ACTUAL_KEY="${ACTUAL_MCP_TOKEN:-}"
ACTUAL_URL="${ACTUAL_MCP_URL:-http://actual-mcp-server:3600/http}"

if [ -z "${DEFAULT_MODEL}" ] && [ "${ZDR}" != "1" ] && [ -z "${TAVILY_KEY}" ] && [ -z "${N9_BASE}" ] && [ -z "${OUTLINE_KEY}" ] && [ -z "${ACTUAL_KEY}" ] && [ -z "${LOCAL_BASE}" ]; then
    exit 0
fi

CONFIG_DIR="${HOME}/.config/opencode"
CONFIG="${CONFIG_DIR}/opencode.json"

mkdir -p "${CONFIG_DIR}"
[ -f "${CONFIG}" ] || printf '{}\n' > "${CONFIG}"

python3 - "$CONFIG" "${DEFAULT_MODEL}" "${ZDR}" "${TAVILY_KEY}" "${TAVILY_URL}" "${N9_BASE}" "${N9_MODEL}" "${N9_PROVIDER}" "${OUTLINE_KEY}" "${OUTLINE_URL}" "${ACTUAL_KEY}" "${ACTUAL_URL}" "${LOCAL_BASE}" "${LOCAL_MODEL}" "${LOCAL_NAME}" "${LOCAL_PROVIDER}" <<'EOF'
import json, os, sys, tempfile, time, urllib.request

path, model, zdr, tavily_key, tavily_url, n9_base, n9_model, n9_provider, outline_key, outline_url, actual_key, actual_url, local_base, local_model, local_name, local_provider = sys.argv[1:17]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"opencode-config: cannot parse {path} ({e}); leaving untouched")
    raise SystemExit(0)

MD_CACHE = os.path.join(os.environ.get("HOME", "/home/coder"), ".cache", "opencode-modelsdev.json")
def _load_modelsdev():
    try:
        if os.path.exists(MD_CACHE) and time.time() - os.path.getmtime(MD_CACHE) < 86400:
            with open(MD_CACHE) as f:
                return json.load(f)
    except Exception:
        pass
    try:
        req = urllib.request.Request("https://models.dev/api.json", headers={"User-Agent": "opencode-container"})
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.load(r)
        os.makedirs(os.path.dirname(MD_CACHE), exist_ok=True)
        with open(MD_CACHE, "w") as f:
            json.dump(data, f)
        return data
    except Exception as e:
        print(f"opencode-config: could not fetch models.dev ({e}); using env/default metadata")
        return None

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

if n9_base:
    entry = cfg.setdefault("provider", {}).setdefault(n9_provider, {})
    entry.setdefault("npm", "@ai-sdk/openai-compatible")
    entry.setdefault("name", "9Router")
    entry.setdefault("options", {}).setdefault("baseURL", n9_base)
    entry.setdefault("options", {}).setdefault("apiKey", "{env:N9ROUTER_API_KEY}")
    changed.append(f"{n9_provider} provider")
    # Auto-sync the full model list from 9Router (GET /models) when enabled, so
    # every model is selectable; falls back to N9ROUTER_MODEL if the fetch fails.
    # For models with an "openrouter/" prefix, context window and pricing are
    # auto-derived from OpenRouter's actual catalog (models.dev, cached 24h).
    md = _load_modelsdev()
    def _or_meta(slug):
        if md is None:
            return None
        models = md.get("openrouter", {}).get("models", {})
        if slug in models:
            return models[slug]
        for key, m in models.items():
            if key.endswith("/" + slug):
                return m
        return None

    def model_entry(mid, prev):
        m = dict(prev)
        m["name"] = m.get("name") or mid
        # Only attach limit/cost when complete real data is available (OpenRouter
        # catalog for "openrouter/*" models). limit must carry both context and
        # output (opencode requires limit.output when limit is present); no
        # hardcoded figures are used. Models without known metadata get none.
        meta = _or_meta(mid[len("openrouter/"):]) if mid.startswith("openrouter/") else None
        l = meta.get("limit", {}) if meta else {}
        if l.get("context") and l.get("output"):
            m["limit"] = {"context": l["context"], "output": l["output"]}
        elif "limit" in m and not (m["limit"].get("context") and m["limit"].get("output")):
            del m["limit"]
        c = meta.get("cost", {}) if meta else {}
        if "input" in c and "output" in c:
            m["cost"] = {"input": c["input"], "output": c["output"]}
        return m
    if os.environ.get("N9ROUTER_AUTO_MODELS", "true").lower() in ("false", "0", "no"):
        synced = None
    else:
        key = os.environ.get("N9ROUTER_API_KEY", "")
        req = urllib.request.Request(
            n9_base.rstrip("/") + "/models",
            headers={"Authorization": f"Bearer {key}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                data = json.load(r)
            ids = [m.get("id") for m in data.get("data", []) if m.get("id")]
            prev = entry.get("models", {})
            synced = {i: model_entry(i, prev.get(i, {})) for i in ids} if ids else None
        except Exception as e:
            print(f"opencode-config: could not fetch 9router models ({e}); using N9ROUTER_MODEL only")
            synced = None
    if synced is not None:
        entry["models"] = synced
        changed.append(f"9router models ({len(synced)})")
    elif n9_model:
        models = entry.setdefault("models", {})
        # Repair existing entries too (e.g. incomplete limit from an earlier
        # seed) so the config stays valid even when the /models sync is off.
        for mid in list(models.keys()):
            repaired = model_entry(mid, models[mid])
            if repaired != models[mid]:
                models[mid] = repaired
                changed.append(f"9router model {mid}")
        if n9_model not in models:
            models[n9_model] = model_entry(n9_model, {})
            changed.append(f"9router model {n9_model}")

# Local LLM provider (OpenAI-compatible, e.g. Ollama / LM Studio / vLLM).
# Env is the source of truth when configured; each model ID shows up as an
# opencode option under the configured provider (LOCAL_LLM_PROVIDER).
if local_base and local_model:
    models = {}
    for mid in [m.strip() for m in local_model.split(",") if m.strip()]:
        models[mid] = {"name": local_name or mid}
    cfg.setdefault("provider", {})[local_provider] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": local_name or "Local LLM",
        "options": {
            "baseURL": local_base,
            "apiKey": "{env:LOCAL_LLM_API_KEY}",
        },
        "models": models,
    }
    changed.append(f"{local_provider} provider ({len(models)})")

if tavily_key and "tavily" not in cfg.setdefault("mcp", {}):
    cfg["mcp"]["tavily"] = {
        "type": "remote",
        "url": tavily_url,
        "enabled": True,
        "headers": {"Authorization": "Bearer {env:TAVILY_API_KEY}"},
    }
    changed.append("tavily mcp")

if outline_key and "outline" not in cfg.setdefault("mcp", {}):
    cfg["mcp"]["outline"] = {
        "type": "remote",
        "url": outline_url,
        "enabled": True,
        "headers": {"Authorization": "Bearer {env:OUTLINE_API_KEY}"},
    }
    changed.append("outline mcp")

if actual_key and "actual" not in cfg.setdefault("mcp", {}):
    cfg["mcp"]["actual"] = {
        "type": "remote",
        "url": actual_url,
        "enabled": True,
        "headers": {"Authorization": "Bearer {env:ACTUAL_MCP_TOKEN}"},
    }
    changed.append("actual mcp")

if not changed:
    raise SystemExit(0)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
print("opencode-config: " + ", ".join(changed))
EOF

