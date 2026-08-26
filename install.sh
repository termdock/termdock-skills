#!/usr/bin/env bash
#
# Install Termdock agent skills into the agent skill directories on this machine.
#
# Only writes to agent directories that already exist: finding no ~/.codex means
# you do not use Codex, not that it needs setting up.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_DIR/skills"

PLATFORMS=(claude codex gemini)
WANT_PLATFORM=""
WANT_SKILL=""
DRY_RUN=0
FORCE=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --skill <name>       Install one skill instead of all
  --platform <name>    Install for one agent (claude|codex|gemini)
  --dry-run            Print what would happen, change nothing
  --force              Overwrite skills you have edited locally
  -h, --help           This text

Installs into ~/.claude/skills, ~/.codex/skills, ~/.gemini/skills, skipping any
that do not exist.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skill) WANT_SKILL="${2:-}"; [ -n "$WANT_SKILL" ] || { echo "--skill needs a name" >&2; exit 64; }; shift 2 ;;
    --platform) WANT_PLATFORM="${2:-}"; [ -n "$WANT_PLATFORM" ] || { echo "--platform needs a name" >&2; exit 64; }; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done

[ -d "$SKILLS_DIR" ] || { echo "No skills/ directory next to this script" >&2; exit 1; }

if [ -n "$WANT_PLATFORM" ]; then
  case " ${PLATFORMS[*]} " in
    *" $WANT_PLATFORM "*) PLATFORMS=("$WANT_PLATFORM") ;;
    *) echo "Unknown platform: $WANT_PLATFORM (expected claude, codex or gemini)" >&2; exit 64 ;;
  esac
fi

# Front matter value for a key, empty when the key is absent.
read_front_matter() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside {
      split($0, parts, ":")
      gsub(/^[ \t]+|[ \t]+$/, "", parts[1])
      if (parts[1] == key) {
        value = substr($0, index($0, ":") + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", value)
        print value
        exit
      }
    }
  ' "$1"
}

# Same directory contents? Compares files, not timestamps.
same_contents() {
  diff -r -q "$1" "$2" >/dev/null 2>&1
}

installed=0
skipped=0
changed=0

for skill_path in "$SKILLS_DIR"/*/; do
  skill_id="$(basename "$skill_path")"
  [ -n "$WANT_SKILL" ] && [ "$skill_id" != "$WANT_SKILL" ] && continue
  [ -f "$skill_path/SKILL.md" ] || { echo "skip $skill_id: no SKILL.md"; continue; }

  version="$(read_front_matter "$skill_path/SKILL.md" version)"
  min_app="$(read_front_matter "$skill_path/SKILL.md" minAppVersion)"
  label="$skill_id${version:+ v$version}"

  for platform in "${PLATFORMS[@]}"; do
    target_root="$HOME/.$platform/skills"
    if [ ! -d "$HOME/.$platform" ]; then
      continue
    fi
    target="$target_root/$skill_id"

    if [ -d "$target" ] && same_contents "$skill_path" "$target"; then
      echo "up to date  $label -> ~/.$platform/skills/"
      skipped=$((skipped + 1))
      continue
    fi

    if [ -d "$target" ] && [ "$FORCE" -eq 0 ]; then
      installed_version="$(read_front_matter "$target/SKILL.md" version 2>/dev/null || true)"
      if [ -n "$version" ] && [ -n "$installed_version" ] && [ "$installed_version" = "$version" ]; then
        echo "edited locally, left alone  $label -> ~/.$platform/skills/  (--force to overwrite)"
        skipped=$((skipped + 1))
        continue
      fi
    fi

    action="install"
    [ -d "$target" ] && action="update"

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would $action  $label -> ~/.$platform/skills/${min_app:+  (needs Termdock >= $min_app)}"
      continue
    fi

    mkdir -p "$target_root"
    rm -rf "$target"
    cp -R "$skill_path" "$target"
    find "$target" -name '*.sh' -exec chmod 755 {} +
    echo "$action  $label -> ~/.$platform/skills/${min_app:+  (needs Termdock >= $min_app)}"
    [ "$action" = "install" ] && installed=$((installed + 1)) || changed=$((changed + 1))
  done
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Dry run, nothing was written."
  exit 0
fi

echo
echo "installed $installed, updated $changed, skipped $skipped"
if [ $((installed + changed)) -gt 0 ]; then
  echo "Restart your agent session to pick the skills up."
fi
