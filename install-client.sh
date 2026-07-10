#!/bin/bash
# install-client.sh — bootstrap di UN device (macOS). Va eseguito COME ROOT (sudo) UNA volta:
# è la "1 volta nella vita" in cui ti autentichi. Installa helper+watcher+sudoers+LaunchAgent.
#   uso:  sudo ./install-client.sh <username> <trust:0|1>
#         trust=1 -> "trusted controller": il controller potrà aprire questo device senza prompt.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

SRC="$(cd "$(dirname "$0")" && pwd)"
USERNAME="${1:?uso: sudo ./install-client.sh <username> <trust:0|1>}"
TRUST="${2:-0}"
[ "$(id -u)" -eq 0 ] || { echo "esegui con sudo"; exit 1; }
id -u "$USERNAME" >/dev/null 2>&1 || { echo "utente $USERNAME inesistente"; exit 1; }
UIDU="$(id -u "$USERNAME")"

echo "== helper + watcher =="
mkdir -p /usr/local/sbin /usr/local/bin          # su Mac senza Homebrew queste non esistono
install -m 0755 -o root -g wheel "$SRC/fleet-lock-apply.sh" /usr/local/sbin/fleet-lock-apply
install -m 0755 -o root -g wheel "$SRC/fleet-lock-agent.sh" /usr/local/bin/fleet-lock-agent
mkdir -p /var/db/fleet-lock; chown root:wheel /var/db/fleet-lock; chmod 0755 /var/db/fleet-lock

echo "== sudoers (validato) =="
tmp="$(mktemp /etc/sudoers.d/.flk.XXXXXX)"
# base: togli i commenti (inclusa la riga trusted commentata); sostituisci l'utente
sed "s/__USER__/$USERNAME/g" "$SRC/sudoers.fleet-lock-helper.template" | grep -vE '^\s*#' > "$tmp"
if [ "$TRUST" = 1 ]; then
  echo "$USERNAME ALL=(root) NOPASSWD: FLK_OPEN" >> "$tmp"   # override: apertura senza prompt (trusted controller)
fi
chown root:wheel "$tmp"; chmod 0440 "$tmp"
if /usr/sbin/visudo -cf "$tmp" >/dev/null 2>&1; then
  mv -f "$tmp" /etc/sudoers.d/fleet-lock-helper
else
  rm -f "$tmp"; echo "SUDOERS INVALIDO — abortito, nessuna modifica"; exit 1
fi

echo "== timeout default 10 min =="
/usr/local/sbin/fleet-lock-apply set-timeout 10 "$USERNAME" >/dev/null

echo "== LaunchAgent (watcher) per $USERNAME =="
LA_DIR="/Users/$USERNAME/Library/LaunchAgents"; mkdir -p "$LA_DIR"; chown "$USERNAME:staff" "$LA_DIR"
PLIST="$LA_DIR/io.github.christianfranchi.sudo-admiral.agent.plist"
install -m 0644 -o "$USERNAME" -g staff "$SRC/io.github.christianfranchi.sudo-admiral.agent.plist" "$PLIST"
launchctl bootout   "gui/$UIDU/io.github.christianfranchi.sudo-admiral.agent" 2>/dev/null || true
launchctl bootstrap "gui/$UIDU" "$PLIST" 2>/dev/null \
  || echo "NB: carica il watcher come $USERNAME:  launchctl bootstrap gui/$UIDU $PLIST"

echo "OK: fleet-lock client installato per $USERNAME (trust=$TRUST)."
echo "   status:  sudo -n /usr/local/sbin/fleet-lock-apply status"
