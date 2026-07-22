#!/bin/bash
# fleet-lock-agent — "salvaschermo del lucchetto": LaunchAgent utente su ogni device.
# Richiude il lucchetto quando si raggiunge la DEADLINE assoluta (close_at) fissata all'apertura
# (ora + N) ed estesa additivamente da 'extend' (close_at += X). Modello top-down, monotòno:
# il countdown scende sempre e "Estendi" lo somma davvero (niente idle-reset, niente "gambero").
# Vale identico per device interattive e headless/remote (SSH). Retry finché non chiude; esito su
# syslog. close_at mancante → back-compat da opened_at + N; N mancante → default 10 (fail-safe: chiude).
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

APPLY="/usr/local/sbin/fleet-lock-apply"
STATE_DIR="/var/db/fleet-lock"
N_FILE="$STATE_DIR/timeout_minutes"
OPENED_FILE="$STATE_DIR/opened_at"
CLOSE_AT_FILE="$STATE_DIR/close_at"
NOPASSWD_FILE="/etc/sudoers.d/fleet-nopasswd"
POLL=15
DEFAULT_N=10
ME="$(id -un)"

now(){ date +%s; }

while :; do
  t="$(now)"
  if [ -f "$NOPASSWD_FILE" ]; then
    ca="$(cat "$CLOSE_AT_FILE" 2>/dev/null || echo '')"
    case "$ca" in ''|*[!0-9]*)
      # back-compat/fail-safe: nessuna deadline scritta → derivala da opened_at + N
      n="$(cat "$N_FILE" 2>/dev/null || echo "$DEFAULT_N")"; case "$n" in ''|*[!0-9]*) n="$DEFAULT_N";; esac; [ "$n" -ge 1 ] || n="$DEFAULT_N"
      opened="$(cat "$OPENED_FILE" 2>/dev/null || echo "$t")"; case "$opened" in ''|*[!0-9]*) opened="$t";; esac
      ca=$(( opened + n*60 ));;
    esac
    if [ "$t" -ge "$ca" ]; then
      if sudo -n "$APPLY" close >/dev/null 2>&1 && [ ! -f "$NOPASSWD_FILE" ]; then
        logger -t fleet-lock "auto-close: deadline raggiunta, lucchetto richiuso"
      else
        logger -t fleet-lock "auto-close FALLITO (riprovo): $APPLY close non riuscito o lock ancora presente"
      fi   # nessun latch: se fallisce, il prossimo poll riprova (no fail-open)
    fi
  fi
  sleep "$POLL"
done
