#!/usr/bin/env bash
set -euo pipefail

TARGET="/opt/ros/humble/lib/python3.10/site-packages/rqt_graph/ros_graph.py"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root. Try: sudo $0" >&2
  exit 1
fi

if [[ ! -f "$TARGET" ]]; then
  echo "Target file not found: $TARGET" >&2
  exit 1
fi

timestamp=$(date +%Y%m%d%H%M%S)
backup="${TARGET}.bak.${timestamp}"
cp -a "$TARGET" "$backup"
echo "Backup created at $backup"

# 1) handle.write(self._current_dotcode) -> handle.write(self._current_dotcode.encode('utf-8'))
sed -i -E "s/handle\.write\([[:space:]]*self\._current_dotcode[[:space:]]*\)/handle.write(self._current_dotcode.encode('utf-8'))/g" "$TARGET"

# 2) self._update_graph_view(dotcode) -> self._update_graph_view(dotcode.decode('utf-8'))
sed -i -E "s/self\._update_graph_view\([[:space:]]*dotcode[[:space:]]*\)/self._update_graph_view(dotcode.decode('utf-8'))/g" "$TARGET"

if grep -q "handle.write(self._current_dotcode.encode('utf-8'))" "$TARGET" \
   && grep -q "self._update_graph_view(dotcode.decode('utf-8'))" "$TARGET"; then
  echo "rqt_graph patched successfully."
else
  echo "Error: Expected changes not detected. Restoring backup." >&2
  cp -a "$backup" "$TARGET"
  exit 1
fi

exit 0


