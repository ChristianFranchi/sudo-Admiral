#!/bin/bash
# fleet-lock-apply — helper ROOT: apre/chiude il lucchetto (NOPASSWD) e imposta il
# timeout di inattività. Installato root-owned in /usr/local/sbin, invocato SOLO via sudo
# con una regola sudoers ristretta (vedi ReadMe). NON eseguibile direttamente dall'utente.
#
# HARDENING (review 2026-07-10): PATH fisso (anti hijack), visudo assoluto, validazione N
# 1..120, target legato a $SUDO_USER (no grant ad altri utenti), scritture atomiche +
# validate con visudo PRIMA di installare (niente lock-out).
#
# Verbi: open <user> | close | set-timeout <N> <user> | status
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin        # CRITICAL: mai ereditare il PATH del chiamante

NOPASSWD_FILE="/etc/sudoers.d/fleet-nopasswd"
TIMEOUT_FILE="/etc/sudoers.d/fleet-timeout"
STATE_DIR="/var/db/fleet-lock"
N_FILE="$STATE_DIR/timeout_minutes"
OPENED_FILE="$STATE_DIR/opened_at"
VISUDO="/usr/sbin/visudo"

die(){ echo "fleet-lock-apply: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "deve girare come root (via sudo)"

valid_user(){ case "$1" in ''|*[!a-zA-Z0-9._-]*) return 1;; esac; id -u "$1" >/dev/null 2>&1; }

# open/set-timeout possono agire solo sull'utente CHIAMANTE (via sudo), mai su un altro.
require_caller(){
  local u="$1"
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    [ "$u" = "$SUDO_USER" ] || die "target ($u) != chiamante ($SUDO_USER): rifiutato"
  fi
}

ensure_state(){ mkdir -p "$STATE_DIR"; chown root:wheel "$STATE_DIR"; chmod 0755 "$STATE_DIR"; }

install_sudoers(){ # $1=path finale  $2=contenuto  — atomico + validato
  local tmp; tmp="$(mktemp "${1%/*}/.flk.XXXXXX")" || die "mktemp"
  printf '%s\n' "$2" > "$tmp"; chown root:wheel "$tmp"; chmod 0440 "$tmp"
  if "$VISUDO" -cf "$tmp" >/dev/null 2>&1; then mv -f "$tmp" "$1"
  else rm -f "$tmp"; die "validazione visudo fallita per $1 (NON installato)"; fi
}

case "${1:-}" in
  open)
    u="${2:-}"; valid_user "$u" || die "utente non valido"; require_caller "$u"
    install_sudoers "$NOPASSWD_FILE" "# fleet-lock: lucchetto APERTO
$u ALL=(ALL) NOPASSWD: ALL"
    ensure_state; date +%s > "$OPENED_FILE"; chmod 0644 "$OPENED_FILE"
    echo "open"
    ;;
  close)
    rm -f "$NOPASSWD_FILE" "$OPENED_FILE"
    echo "closed"
    ;;
  set-timeout)
    n="${2:-}"; u="${3:-}"
    case "$n" in ''|*[!0-9]*) die "N non valido (solo cifre)";; esac
    [ "$n" -ge 1 ] && [ "$n" -le 120 ] || die "N fuori range (1..120)"
    valid_user "$u" || die "utente non valido"; require_caller "$u"
    install_sudoers "$TIMEOUT_FILE" "# fleet-lock: timeout cache sudo (min)
Defaults:$u timestamp_timeout=$n"
    ensure_state; printf '%s\n' "$n" > "$N_FILE"; chmod 0644 "$N_FILE"
    echo "timeout=$n"
    ;;
  status)
    if [ -f "$NOPASSWD_FILE" ]; then st=open; else st=closed; fi
    echo "$st timeout=$(cat "$N_FILE" 2>/dev/null || echo '?') opened_at=$(cat "$OPENED_FILE" 2>/dev/null || echo '-')"
    ;;
  *) die "usage: fleet-lock-apply {open <user>|close|set-timeout <N> <user>|status}";;
esac
