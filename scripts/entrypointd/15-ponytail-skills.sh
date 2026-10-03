#!/bin/sh
# Makes the bundled ponytail skills visible to opencode. The skills are baked
# into the image at /usr/local/share/opencode/skills (outside the /home/coder
# volume, which would otherwise shadow them); symlink each one into the global
# skills dir on start. Never overrides a skill the user has installed/edited
# themselves.
set -eu

SKILLS_SRC="${PONYTAIL_SKILLS_SRC:-/usr/local/share/opencode/skills}"
SKILLS_DIR="${HOME}/.config/opencode/skills"

[ -d "${SKILLS_SRC}" ] || exit 0

mkdir -p "${SKILLS_DIR}"
for skill in "${SKILLS_SRC}"/*; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    if [ ! -e "${SKILLS_DIR}/${name}" ]; then
        ln -s "$skill" "${SKILLS_DIR}/${name}"
        echo "ponytail: linked skill ${name}"
    fi
done