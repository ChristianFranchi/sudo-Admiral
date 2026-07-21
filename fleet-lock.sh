#!/bin/bash
# fleet-lock — CONTROLLER (gira sul controller = "server"). Apre/chiude il lucchetto e
# imposta N (minuti di inattività) su SE STESSO e su tutte le device della flotta,
# via SSH (Tailscale). Come Deskflow: un solo punto di comando.
#
# Inventario device: ~/.config/fleet-lock/hosts  (un alias SSH per riga, es. "host1").
# Su ogni host l'utente da abilitare = l'utente con cui ci si logga via SSH (id -un lì).
#
# Uso:  fleet-lock open | close | set <N> | status
set -euo pipefail

APPLY="/usr/local/sbin/fleet-lock-apply"
HOSTS_FILE="${FLEET_HOSTS:-$HOME/.config/fleet-lock/hosts}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8"

# solo alias host "puliti" (anti-injection): lettere/cifre/._- e MAI un trattino iniziale
# (ssh lo leggerebbe come opzione); '--' prima dell'host nelle ssh come seconda difesa.
hosts(){ [ -f "$HOSTS_FILE" ] && grep -vE '^\s*(#|$)' "$HOSTS_FILE" | grep -E '^[A-Za-z0-9._][A-Za-z0-9._-]*$' || true; }

# host Windows (Opzione A): "alias|jump" — raggiunti via hop SSH sul jump; solo gestione
# remota (SSH admin già elevato), nessun lucchetto/UAC da toggle.
WINHOSTS_FILE="${FLEET_WINHOSTS:-$HOME/.config/fleet-lock/windows-hosts}"
winhosts(){ [ -f "$WINHOSTS_FILE" ] && grep -vE '^\s*(#|$)' "$WINHOSTS_FILE" | grep -E '^[A-Za-z0-9._][A-Za-z0-9._-]*\|[A-Za-z0-9._][A-Za-z0-9._-]*$' || true; }

# solo open/set-timeout/extend hanno bisogno dell'argomento <user>; close/status no.
needs_user(){ case "$1" in open|set-timeout|extend) return 0;; *) return 1;; esac; }

run_local(){  # $1=verbo, resto=args ; open richiede auth (Touch ID se pam_tid attivo)
  local verb="$1"; shift
  local args=("$verb" "$@"); needs_user "$verb" && args+=("$(id -un)")
  if [ "$verb" = open ]; then
    sudo "$APPLY" "${args[@]}"                        # con pam_tid (sudo_local) → Touch ID, anche da menu-bar
  else
    sudo -n "$APPLY" "${args[@]}"                    # close/set/status: NOPASSWD, mai interattivo
  fi
}

run_remote(){ # $1=host $2=verbo, resto=args (N validato; verb letterale; host validato in hosts())
  local h="$1" verb="$2"; shift 2
  local rc="sudo -n $APPLY $verb $*"
  needs_user "$verb" && rc="$rc \"\$(id -un)\""     # id -un valutato SUL remoto
  $SSH -- "$h" "$rc" 2>/dev/null
}

fanout(){ # $1=verbo, resto=args
  local verb="$1"; shift
  printf '  local   : '; run_local "$verb" "$@" || echo "FALLITO"
  local h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    printf '  %-8s: ' "$h"
    if out="$(run_remote "$h" "$verb" "$@")"; then echo "$out"
    else echo "FALLITO/irraggiungibile${verb:+ ($verb)}"; fi
  done < <(hosts)
  # host Windows (via hop): solo gestione remota, nessun lucchetto
  local wh wj
  while IFS='|' read -r wh wj; do
    [ -n "$wh" ] || continue
    printf '  %-8s: ' "$wh"
    if [ "$verb" = status ]; then
      if who="$($SSH -- "$wj" "ssh -o BatchMode=yes -o ConnectTimeout=8 -- $wh whoami" 2>/dev/null)" && [ -n "$who" ]; then
        echo "gestibile (SSH elevato)"
      else echo "irraggiungibile (via $wj)"; fi
    else
      echo "gestione remota sempre attiva — nessun UAC toggle"
    fi
  done < <(winhosts)
}

case "${1:-}" in
  open)   echo "Apro il lucchetto (fleet):";  fanout open ;;
  close)  shift || true
          if [ "$#" -eq 0 ]; then echo "Chiudo il lucchetto (fleet):"; fanout close
          else
            echo "Chiudo il lucchetto su: $*"
            for h in "$@"; do
              case "$h" in
                ''|-*|*[!A-Za-z0-9._-]*) echo "  host non valido: '$h'"; continue;;
                local|localhost) printf '  local   : '; run_local close || echo "FALLITO";;
                *) printf '  %-8s: ' "$h"
                   if out="$(run_remote "$h" close)"; then echo "$out"
                   else echo "FALLITO/irraggiungibile"; fi;;
              esac
            done
          fi ;;
  set)    n="${2:-}"; case "$n" in ''|*[!0-9]*) echo "N non valido (solo cifre 1..360)"; exit 2;; esac
          { [ "$n" -ge 1 ] && [ "$n" -le 360 ]; } || { echo "N fuori range (1..360)"; exit 2; }
          echo "Imposto timeout inattività = $n min (fleet):"; fanout set-timeout "$n" ;;
  extend) x="${2:-}"; case "$x" in ''|*[!0-9]*) echo "X non valido (minuti 1..360)"; exit 2;; esac
          { [ "$x" -ge 1 ] && [ "$x" -le 360 ]; } || { echo "X fuori range (1..360)"; exit 2; }
          echo "Estendo l'apertura di +$x min (fleet):"; fanout extend "$x" ;;
  status) echo "Stato lucchetto (fleet):"; fanout status ;;
  *) echo "uso: fleet-lock {open|close [host...]|set <N>|extend <X>|status}"; exit 2 ;;
esac
