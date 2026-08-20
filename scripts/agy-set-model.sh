#!/usr/bin/env bash
#
# agy-set-model.sh — change agy's own persisted default model.
# Part of the "Antigravity for Claude Code" plugin.
#
# Why this exists: the plugin's `default_tier` / `default_model` / `tier_*` userConfig
# options (see agy-delegate.sh) only affect calls made THROUGH the delegation wrapper —
# they never touch agy's own default, which lives in
# ~/.gemini/antigravity-cli/settings.json's top-level "model" field and is what plain
# `agy` / `agy -p` use. Nothing in this plugin wrote to that field before this script, so
# a user changing tiers via /plugin config and then running `agy` directly would see no
# change at all — the two "model" concepts don't overlap.
#
# The other half of the bug this fixes: doctor.sh and plugin.json's tier_* defaults are
# hardcoded model names (e.g. "Gemini 3.5 Flash (High)") that go stale as agy ships new
# tiers. This script instead validates against a LIVE `agy models` call, so it always
# offers/accepts whatever the account's current plan actually exposes.
#
# Usage:
#   agy-set-model.sh --list                 List available models (slug + display name)
#   agy-set-model.sh --current               Print the currently configured default model
#   agy-set-model.sh <name-or-slug>          Validate against `agy models` and persist it
#
# <name-or-slug> may be an exact slug (gemini-3.1-pro-high) or display name
# ("Gemini 3.1 Pro (High)"); matching is case/whitespace/punctuation-insensitive, same as
# doctor.sh's tier check, so "gemini 3.1 pro high" also matches.
#
# Exit codes: 0 ok | 1 usage | 13 agy missing | 14 model not found in `agy models`
#             | 2 could not read/write settings.json
#
set -euo pipefail

SETTINGS="${AGY_SETTINGS_FILE:-$HOME/.gemini/antigravity-cli/settings.json}"

die() { echo "agy-set-model: $*" >&2; exit 1; }

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

# Same normalization doctor.sh uses: lowercase, alnum-only, so a slug and a display name
# for the same model compare equal regardless of which format agy's own list uses today.
norm_model() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'; }

[ "$#" -ge 1 ] || usage 1
case "$1" in -h|--help) usage 0 ;; esac

command -v agy >/dev/null 2>&1 || { echo "agy-set-model: 'agy' not found on PATH — install the Antigravity CLI first" >&2; exit 13; }

if [ "$1" = "--current" ]; then
  [ -f "$SETTINGS" ] || die "no settings file yet (${SETTINGS}) — agy has no persisted default; run \`agy\` once interactively first"
  CUR="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("model", ""))
' "$SETTINGS")"
  [ -n "$CUR" ] && echo "$CUR" || echo "(no default model set — agy falls back to its own built-in default)"
  exit 0
fi

MODELS="$(agy models 2>/dev/null)"
[ -n "$MODELS" ] || die "\`agy models\` returned nothing — check auth/network (run \`agy-doctor\`)"

if [ "$1" = "--list" ]; then
  printf '%s\n' "$MODELS"
  exit 0
fi

WANT="$1"
WANT_N="$(norm_model "$WANT")"
[ -n "$WANT_N" ] || die "empty model name"

# `agy models` emits either "<slug>\t<display name>" (current CLI) or one bare name per
# line (older builds) — resolve to the exact line's full text either way, matching in
# either direction so a partial slug like "3.1-pro" also hits.
MATCH=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  N="$(norm_model "$line")"
  case "$WANT_N" in *"$N"*) MATCH="$line"; break ;; esac
  case "$N" in *"$WANT_N"*) MATCH="$line"; break ;; esac
done <<EOF
$MODELS
EOF

if [ -z "$MATCH" ]; then
  echo "agy-set-model: '$WANT' is not in \`agy models\` — it may not exist, or your plan doesn't expose it." >&2
  echo "Available models:" >&2
  printf '%s\n' "$MODELS" | sed 's/^/  /' >&2
  exit 14
fi

# Prefer the display name (second tab-separated field) when present — that's the form
# agy's own settings.json already stored before this script existed, and it's what a
# human reads back with --current. Fall back to the whole line for older single-column
# `agy models` output.
RESOLVED="$(printf '%s' "$MATCH" | cut -f2)"
[ -n "$RESOLVED" ] || RESOLVED="$MATCH"

mkdir -p "$(dirname "$SETTINGS")"
# No `|| die` here on purpose: die() always exits 1, which would swallow the distinct
# exit-2 (invalid existing JSON) the inline script raises. `set -e` propagates whatever
# code python3 exits with instead.
python3 -c '
import json, os, sys

path, model = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError as e:
    print("agy-set-model: %s is not valid JSON (%s) — refusing to overwrite it" % (path, e), file=sys.stderr)
    sys.exit(2)

data["model"] = model

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
' "$SETTINGS" "$RESOLVED"

echo "agy-set-model: default model set to '$RESOLVED' (${SETTINGS/#$HOME/~})"
echo "This changes agy's OWN default (plain \`agy\` / \`agy -p\` runs). It does not affect"
echo "agy-delegate.sh calls made through this plugin — those follow --tier/--model or the"
echo "plugin's default_tier/default_model/tier_* userConfig instead. Run \`agy-doctor\` to"
echo "check both are pointing at what you expect."
