#!/bin/sh
# Seeds a default model into opencode's config when OPENCODE_MODEL is set, so
# a fresh install needs no manual /models setup. Never overrides a model the
# user has already set in their config.
set -eu

[ -n "${OPENCODE_MODEL:-}" ] || exit 0

CONFIG_DIR="${HOME}/.config/opencode"
CONFIG="${CONFIG_DIR}/opencode.json"

mkdir -p "${CONFIG_DIR}"
[ -f "${CONFIG}" ] || printf '{}\n' > "${CONFIG}"

python3 - "$CONFIG" "${OPENCODE_MODEL}" <<'EOF'
import json, os, sys, tempfile

path, model = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"opencode-config: cannot parse {path} ({e}); leaving untouched")
    raise SystemExit(0)

if "model" in cfg:
    print(f"opencode-config: model already set ({cfg['model']}); not overriding")
    raise SystemExit(0)

cfg["model"] = model
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
print(f"opencode-config: set default model {model}")
EOF
