#!/bin/bash
# install-controller.sh — installs the sudo-Admiral controller CLI + SwiftBar menu-bar app
# on your main machine (the "server"). User-level, no sudo required.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/fleet-lock"
install -m 0755 "$SRC/fleet-lock.sh"  "$HOME/.local/bin/fleet-lock"
install -m 0755 "$SRC/sa-setlang.sh"  "$HOME/.local/bin/sa-setlang"

# empty inventories on first install
[ -f "$HOME/.config/fleet-lock/hosts" ]         || printf '# one SSH alias per line (e.g. host1)\n' > "$HOME/.config/fleet-lock/hosts"
[ -f "$HOME/.config/fleet-lock/windows-hosts" ] || printf '# windows hosts: alias|jump  (e.g. winbox|host1)\n' > "$HOME/.config/fleet-lock/windows-hosts"

# SwiftBar plugin (if SwiftBar is installed)
if [ -d "/Applications/SwiftBar.app" ]; then
  PDIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.config/swiftbar-plugins")"
  mkdir -p "$PDIR"
  install -m 0755 "$SRC/sudo-Admiral.30s.sh" "$PDIR/sudo-Admiral.30s.sh"
  echo "menu-bar app installed in: $PDIR"
  open -g "swiftbar://refreshallplugins" 2>/dev/null || true
else
  echo "SwiftBar not found — install it (brew install --cask swiftbar) then re-run to get the menu-bar app."
fi

echo "OK: controller ready. Add your devices to ~/.config/fleet-lock/hosts"
echo "    Ensure ~/.local/bin is on your PATH."
