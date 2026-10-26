#!/bin/bash
# Claude Code hook: after Claude writes or edits a Swift file in this project, format it with the
# rules in .swift-format. Any other file is left alone.
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
"$root"/*.swift) [ -f "$file" ] && xcrun swift format --in-place "$file" ;;
esac
exit 0
