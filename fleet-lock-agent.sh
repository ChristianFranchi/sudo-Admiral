#!/bin/bash
# fleet-lock-agent — "salvaschermo del lucchetto": LaunchAgent utente su ogni device.
# Richiude il lucchetto quando la device è INUTILIZZATA da >= N minuti.
#
# Modello anti-headless (review 2026-07-10): la finestra parte da opened_at (quando il
# lucchetto è stato aperto) e viene ESTESA dall'attività HID locale. Quindi:
#   - device interattiva → chiude dopo N min dall'ultima attività reale (idle-based);
#   - device headless/remota → nessuna attività HID → chiude N min dopo l'APERTURA (time-box).
# Così l'apertura da remoto (SSH) sopravvive N minuti e non viene azzerata a 15s.
# Retry finché non chiude davvero; esito su syslog (logger). N mancante → default 10 (fail-safe: chiude).
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

APPLY="/usr/local/sbin/fleet-lock-apply"
STATE_DIR="/var/db/fleet-lock"
N_FILE="$STATE_DIR/timeout_minutes"
OPENED_FILE="$STATE_DIR/opened_at"
NOPASSWD_FILE="/etc/sudoers.d/fleet-nopasswd"
POLL=15
DEFAULT_N=10
ME="$(id -un)"

idle_seconds(){ ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
now(){ date +%s; }

last_active="$(now)"
while :; do
  n="$(cat "$N_FILE" 2>/dev/null || echo "$DEFAULT_N")"
  case "$n" in ''|*[!0-9]*) n="$DEFAULT_N";; esac; [ "$n" -ge 1 ] || n="$DEFAULT_N"
  t="$(now)"
  if [ -f "$NOPASSWD_FILE" ]; then
    idle="$(idle_seconds || echo 0)"; : "${idle:=0}"
    [ "$idle" -lt "$POLL" ] && last_active="$t"           # attività recente → estende la finestra
    opened="$(cat "$OPENED_FILE" 2>/dev/null || echo "$t")"; case "$opened" in ''|*[!0-9]*) opened="$t";; esac
    ref="$last_active"; [ "$opened" -gt "$ref" ] && ref="$opened"   # finestra = max(ultima attività, apertura)
    if [ "$((t - ref))" -ge "$((n*60))" ]; then
      if sudo -n "$APPLY" close >/dev/null 2>&1 && [ ! -f "$NOPASSWD_FILE" ]; then
        logger -t fleet-lock "auto-close: lucchetto richiuso dopo ${n}min di inattività"
      else
        logger -t fleet-lock "auto-close FALLITO (riprovo): $APPLY close non riuscito o lock ancora presente"
      fi   # nessun latch: se fallisce, il prossimo poll riprova (no fail-open)
    fi
  else
    last_active="$t"                                       # lucchetto chiuso → riparte la grazia alla prossima apertura
  fi
  sleep "$POLL"
done
