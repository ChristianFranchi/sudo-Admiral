#!/bin/bash
# sa-gh-sync — propaga l'auth di GitHub CLI (`gh`) dal controller a tutta la flotta,
# via PIPE del token su SSH (Tailscale). Companion di fleet-lock: stessa flotta, stesso
# stile fan-out, ma per `gh` invece che per il lucchetto sudo. NON richiede root/sudo:
# è pura auth utente di `gh`.
#
# Il token NON transita mai su schermo, file o riga di comando: viaggia SOLO in pipe
# (controller→device) e viene consegnato a `gh auth login --with-token`, che lo legge da
# stdin e lo ripone nel keyring/hosts.yml del device. Stesso principio con cui si passa
# una password dal Keychain a un tool senza stamparla.
#
# Inventario device: ~/.config/fleet-lock/hosts  (lo stesso di fleet-lock — un alias SSH
# per riga). Gli host Windows (windows-hosts) sono ESCLUSI: il metodo `bash -lc` è
# specifico per la flotta macOS/Homebrew.
#
# Uso:
#   sa-gh-sync [-u <account>] [host ...]   # sync: propaga l'account (default: quello ATTIVO
#                                          #   sul controller) a tutti gli host (o solo quelli indicati)
#   sa-gh-sync status [host ...]           # solo verifica (read-only): chi è loggato su ogni device
#
# Metodica: the_Architect ▸ "(3) interNET ⇢ CLOUD ⇢ UI global ▸ … ▸ gh — sync auth remoto".
set -euo pipefail

HOSTS_FILE="${FLEET_HOSTS:-$HOME/.config/fleet-lock/hosts}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"
GH_HOST="github.com"

die(){                                    # se lanciato dal menu (stderr non-tty) notifica anche su macOS
  echo "sa-gh-sync: $*" >&2
  if [ ! -t 2 ] && command -v osascript >/dev/null 2>&1; then
    local m; m="$(printf '%s' "$*" | tr '"\\' "' ")"     # niente virgolette/backslash nell'AppleScript
    osascript -e "display notification \"$m\" with title \"sudo-Admiral · gh\"" >/dev/null 2>&1 || true
  fi
  exit 1
}
command -v gh >/dev/null 2>&1 || die "gh non installato sul controller"

# alias host "puliti" (anti-injection): lettere/cifre/._- e MAI un trattino iniziale (che ssh
# leggerebbe come opzione). Difesa a due strati: qui il filtro, e '--' prima dell'host nelle ssh.
hosts_all(){ [ -f "$HOSTS_FILE" ] && grep -vE '^\s*(#|$)' "$HOSTS_FILE" | grep -E '^[A-Za-z0-9._][A-Za-z0-9._-]*$' || true; }

# ── parse argomenti ──
mode="sync"; acct=""
[ "${1:-}" = "status" ] && { mode="status"; shift; }
case "${1:-}" in
  -u|--user) acct="${2:-}"; shift 2 2>/dev/null || die "manca <account> dopo $1" ;;
esac

# target: host espliciti (validati) oppure tutto l'inventario
targets=()
if [ "$#" -gt 0 ]; then
  for h in "$@"; do
    case "$h" in ''|-*|*[!A-Za-z0-9._-]*) die "host non valido: '$h'";; esac
    targets+=("$h")
  done
else
  while IFS= read -r h; do [ -n "$h" ] && targets+=("$h"); done < <(hosts_all)
fi
[ "${#targets[@]}" -gt 0 ] || die "nessun device in $HOSTS_FILE (aggiungi un alias SSH per riga)"

# ── account da propagare (solo in sync): default = quello ATTIVO sul controller ──
if [ "$mode" = sync ]; then
  if [ -z "$acct" ]; then
    acct="$(gh auth status --active -h "$GH_HOST" 2>/dev/null | sed -n 's/.*account \([A-Za-z0-9-]*\).*/\1/p' | head -1 || true)"
  fi
  case "$acct" in ''|*[!A-Za-z0-9-]*) die "account gh non valido o non determinabile: '${acct}'";; esac
  # il token per quell'account deve esistere sul controller (non lo stampiamo)
  gh auth token -h "$GH_HOST" -u "$acct" >/dev/null 2>&1 \
    || die "nessun token per l'account '$acct' sul controller (fai prima 'gh auth login')"
fi

# ── comandi remoti (bash -lc: `gh` di Homebrew è nel PATH solo in shell di login) ──
# sync: legge il token da stdin (pipe) → login → switch all'account giusto → verifica.
RCMD_SYNC="bash -lc '
  command -v gh >/dev/null 2>&1 || { echo NO-GH; exit 3; }
  gh auth login -h $GH_HOST --with-token >/dev/null 2>&1 || { echo LOGIN-FAIL; exit 4; }
  gh auth switch -h $GH_HOST -u $acct >/dev/null 2>&1 || true
  gh api user --jq .login 2>/dev/null || echo VERIFY-FAIL
'"
# status: read-only, nessun token.
RCMD_STATUS="bash -lc '
  command -v gh >/dev/null 2>&1 || { echo NO-GH; exit 3; }
  gh api user --jq .login 2>/dev/null || echo INVALID
'"

total=0; ok=0
if [ "$mode" = sync ]; then
  echo "gh sync (account: $acct) → flotta:"
else
  echo "gh status flotta:"
fi

for h in "${targets[@]}"; do
  total=$((total+1))
  printf '  %-12s: ' "$h"
  if [ "$mode" = sync ]; then
    if out="$(gh auth token -h "$GH_HOST" -u "$acct" | $SSH -- "$h" "$RCMD_SYNC" 2>/dev/null)"; then :; fi
  else
    if out="$($SSH -- "$h" "$RCMD_STATUS" 2>/dev/null)"; then :; fi
  fi
  case "$out" in
    NO-GH*)                 echo "gh non installato sul device" ;;
    LOGIN-FAIL*)            echo "login fallito (token/scope?)" ;;
    INVALID*)               echo "token assente/non valido" ;;
    VERIFY-FAIL*)           echo "loggato ma verifica API fallita" ;;
    '')                     echo "irraggiungibile (SSH)" ;;
    *)                      echo "OK — loggato come $out"; ok=$((ok+1)) ;;
  esac
done

summary="$ok/$total OK"
[ "$mode" = sync ] && summary="$summary · $acct"
echo "── $summary"

# se lanciato dal menu (stdout non è un terminale), notifica il riepilogo su macOS
if [ ! -t 1 ] && command -v osascript >/dev/null 2>&1; then
  title="sudo-Admiral · gh $mode"
  osascript -e "display notification \"$summary\" with title \"$title\"" >/dev/null 2>&1 || true
fi

# exit code utile in automazione: 0 solo se tutti OK
[ "$ok" -eq "$total" ]
