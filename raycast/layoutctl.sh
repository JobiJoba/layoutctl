#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Layoutctl
# @raycast.mode compact
# @raycast.packageName Layout Control
# @raycast.icon 🤖
# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "save", "value": "save"}, {"title": "restore", "value": "restore"}] }
# @raycast.argument2 { "type": "text", "placeholder": "Profile name", "optional": true }

set -euo pipefail

action="$1"
profile="${2-}"

case "$action" in
  save|restore)
    if [[ -z "${profile}" ]]; then
      echo "Profile name is required for $action." >&2
      exit 1
    fi
    exec /usr/local/bin/layoutctl "$action" "$profile"
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 1
    ;;
esac