#!/bin/bash
# uninstall.sh — removes sudo-Admiral from THIS machine (controller/app + client).
set -u
AGENT_LABEL="io.github.christianfranchi.sudo-admiral.agent"

echo "== controller + menu-bar app (user) =="
rm -f "$HOME/.local/bin/fleet-lock" "$HOME/.local/bin/sa-setlang" "$HOME/.local/bin/sa-gh-sync"
PDIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.config/swiftbar-plugins")"
rm -f "$PDIR/sudo-Admiral.30s.sh"
rm -rf "$HOME/.config/sudo-admiral"

echo "== client agent (user) =="
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

echo "== client root parts (sudo) =="
sudo rm -f /usr/local/sbin/fleet-lock-apply /usr/local/bin/fleet-lock-agent \
           /etc/sudoers.d/fleet-lock-helper /etc/sudoers.d/fleet-nopasswd /etc/sudoers.d/fleet-timeout
sudo rm -rf /var/db/fleet-lock

echo "Done. (Inventory files in ~/.config/fleet-lock left in place; remove manually if desired.)"
echo "Note: /etc/pam.d/sudo_local (Touch ID) and SwiftBar were left untouched."
