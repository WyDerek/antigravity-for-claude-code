---
description: Change agy's own default model, validated against the live `agy models` list.
argument-hint: "[model-name-or-slug | --list | --current]"
---

Change agy's persisted default model (used by plain `agy` / `agy -p` runs — separate
from this plugin's `default_tier`/`default_model`/`tier_*` options, which only affect
delegation calls made through `agy-delegate.sh`).

- No arguments, or `--list`: run `agy-set-model --list` and show the user the live list
  of models `agy models` currently reports (do not use a hardcoded list — availability is
  plan-dependent and changes over time). Ask which one they want if they haven't said.
- `--current`: run `agy-set-model --current` and report the presently configured default.
- Otherwise: run `agy-set-model "$ARGUMENTS"`. It validates the name against a live
  `agy models` call and only writes `~/.gemini/antigravity-cli/settings.json` on a match.

Report the exit code plainly:
- `0`: confirm the new default and repeat the note the script prints about this being
  agy's own default, not the plugin's delegation tiers.
- `14`: the name isn't in `agy models` — show the available list the script printed and
  ask the user to pick one from it.
- `13`: agy isn't on PATH — point at `/antigravity:setup`.
- anything else: show the script's stderr verbatim.
