#!/bin/bash
# Claude Code hook: after Claude writes or edits a Swift file in this project, format it with the
# rules in .swift-format. Any other file, including one reached through "..", is left alone.
root="${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
root=$(cd "$root" && pwd -P) || exit 0
file=$(jq -r '.tool_input.file_path // empty')
[ -f "$file" ] || exit 0
file="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"
case "$file" in
"$root"/*.swift) xcrun swift format --in-place "$file" ;;
esac
exit 0
