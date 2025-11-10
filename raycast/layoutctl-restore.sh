#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Restore Layout Profile
# @raycast.mode filter
# @raycast.argument1 { "type": "text", "placeholder": "Type to filter layouts", "optional": true }
# @raycast.packageName Layout Control
# @raycast.icon 🤖

set -euo pipefail

restore_profile() {
  local profile="$1"
  if [[ -z "$profile" ]]; then
    exit 0
  fi
  exec /usr/local/bin/layoutctl restore "$profile"
}

if [[ -n "${RAYCAST_SELECTED_ITEM:-}" ]]; then
  chosen="${RAYCAST_SELECTED_ITEM%%$'\t'*}"
  restore_profile "$chosen"
fi

filter="${RAYCAST_ARGUMENT_1:-}"
profiles_json=$(/usr/local/bin/layoutctl list --json 2>/dev/null || echo "[]")

python3 - "$profiles_json" "$filter" <<'PY'
import json
import sys
from datetime import datetime, timezone

def human(ts):
    if not ts:
        return " "
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        dt = dt.astimezone()
        return dt.strftime("Last updated %Y-%m-%d %H:%M")
    except ValueError:
        return ts

try:
    profiles = json.loads(sys.argv[1])
except json.JSONDecodeError:
    profiles = []

query = (sys.argv[2] if len(sys.argv) > 2 else "").strip().lower()
if query:
    profiles = [
        profile for profile in profiles
        if query in profile.get("profile", "").lower()
        or query in (profile.get("updatedAt") or "").lower()
    ]

if not profiles:
    print("No profiles found\tSave a layout first.")
else:
    for profile in profiles:
        name = profile.get("profile", "")
        updated = human(profile.get("updatedAt"))
        print(f"{name}\t{updated}")
PY

