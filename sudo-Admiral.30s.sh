#!/bin/bash
# sudo-Admiral — SwiftBar menu-bar app: lucchetto sudo passwordless su tutta la flotta
# (motore: fleet-lock). Refresh 30s. Multilingua: it/en/es/fr/de/zh.
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
FL="$HOME/.local/bin/fleet-lock"
APPLY="/usr/local/sbin/fleet-lock-apply"
SETLANG="$HOME/.local/bin/sa-setlang"
GHSYNC="$HOME/.local/bin/sa-gh-sync"

lang="$(cat "$HOME/.config/sudo-admiral/lang" 2>/dev/null || echo it)"
case "$lang" in it|en|es|fr|de|zh) :;; *) lang=it;; esac

# ── traduzioni ──
case "$lang" in
 en) t_open="Unlock fleet"; t_close="Lock fleet"; t_timeout="Idle timeout"; t_min="min"; t_prefs="Preferences"; t_lang="Language"; t_about="About sudo-Admiral"; t_quit="Quit sudo-Admiral"; t_author="Author"; t_engine="Engine"; t_desc="passwordless sudo lock across the whole fleet"; w_open="unlocked"; w_closed="locked"; w_manage="manageable (SSH)"; w_unreach="unreachable"; t_gh="GitHub (gh)"; t_gh_sync="Sync auth → fleet"; t_gh_status="Check gh status";;
 es) t_open="Desbloquear flota"; t_close="Bloquear flota"; t_timeout="Tiempo de inactividad"; t_min="min"; t_prefs="Preferencias"; t_lang="Idioma"; t_about="Acerca de sudo-Admiral"; t_quit="Salir de sudo-Admiral"; t_author="Autor"; t_engine="Motor"; t_desc="bloqueo sudo sin contraseña en toda la flota"; w_open="desbloqueado"; w_closed="bloqueado"; w_manage="gestionable (SSH)"; w_unreach="inaccesible"; t_gh="GitHub (gh)"; t_gh_sync="Sincronizar auth → flota"; t_gh_status="Comprobar estado gh";;
 fr) t_open="Déverrouiller la flotte"; t_close="Verrouiller la flotte"; t_timeout="Délai d'inactivité"; t_min="min"; t_prefs="Préférences"; t_lang="Langue"; t_about="À propos de sudo-Admiral"; t_quit="Quitter sudo-Admiral"; t_author="Auteur"; t_engine="Moteur"; t_desc="verrou sudo sans mot de passe sur toute la flotte"; w_open="déverrouillé"; w_closed="verrouillé"; w_manage="gérable (SSH)"; w_unreach="injoignable"; t_gh="GitHub (gh)"; t_gh_sync="Synchroniser l'auth → flotte"; t_gh_status="Vérifier l'état gh";;
 de) t_open="Flotte entsperren"; t_close="Flotte sperren"; t_timeout="Leerlauf-Timeout"; t_min="Min."; t_prefs="Einstellungen"; t_lang="Sprache"; t_about="Über sudo-Admiral"; t_quit="sudo-Admiral beenden"; t_author="Autor"; t_engine="Engine"; t_desc="passwortloses sudo-Schloss für die gesamte Flotte"; w_open="entsperrt"; w_closed="gesperrt"; w_manage="verwaltbar (SSH)"; w_unreach="nicht erreichbar"; t_gh="GitHub (gh)"; t_gh_sync="Auth → Flotte synchronisieren"; t_gh_status="gh-Status prüfen";;
 zh) t_open="解锁全部设备"; t_close="锁定全部设备"; t_timeout="空闲超时"; t_min="分钟"; t_prefs="偏好设置"; t_lang="语言"; t_about="关于 sudo-Admiral"; t_quit="退出 sudo-Admiral"; t_author="作者"; t_engine="引擎"; t_desc="对整个设备群的免密 sudo 锁"; w_open="已解锁"; w_closed="已锁定"; w_manage="可管理 (SSH)"; w_unreach="无法访问"; t_gh="GitHub (gh)"; t_gh_sync="同步认证 → 全部设备"; t_gh_status="检查 gh 状态";;
 *)  t_open="Apri flotta"; t_close="Chiudi flotta"; t_timeout="Timeout inattività"; t_min="min"; t_prefs="Preferenze"; t_lang="Lingua"; t_about="Info su sudo-Admiral"; t_quit="Esci da sudo-Admiral"; t_author="Autore"; t_engine="Motore"; t_desc="lucchetto sudo senza password su tutta la flotta"; w_open="aperto"; w_closed="chiuso"; w_manage="gestibile (SSH)"; w_unreach="irraggiungibile"; t_gh="GitHub (gh)"; t_gh_sync="Sincronizza auth → flotta"; t_gh_status="Verifica stato gh";;
esac

loc="$(sudo -n "$APPLY" status 2>/dev/null || echo 'unknown')"
case "$loc" in
  open*)   sym="lock.open.fill"; sfc="#30d158"; state="open";;    # verde acceso (aperto)
  closed*) sym="lock.fill";      sfc="#ffcc00"; state="closed";;  # oro, come l'emoji (chiuso)
  *)       sym="lock.fill";      sfc="#ff453a"; state="unknown";; # rosso (stato ignoto)
esac
N="$(printf '%s' "$loc" | sed -n 's/.*timeout=\([0-9]*\).*/\1/p')"; N="${N:-?}"

# ── icona menu-bar ──
echo " | sfimage=$sym sfcolor=$sfc"
echo "---"
# LA FLOTTA = una riga cliccabile (apre/chiude tutta la flotta); device annidati
if [ "$state" = "open" ]; then
  echo "$t_close | sfimage=lock.fill sfcolor=#ffcc00 bash=\"$FL\" param1=close terminal=false refresh=true"
else
  echo "$t_open | sfimage=lock.open.fill sfcolor=#30d158 bash=\"$FL\" param1=open terminal=false refresh=true"
fi
"$FL" status 2>/dev/null | sed -n 's/^  \(.*\)/\1/p' | while IFS= read -r line; do
  dev="${line%%:*}"; rest="${line#*: }"
  case "$rest" in
    open*)               st="$w_open";    c="#16a34a";;
    closed*)             st="$w_closed";  c="#8e8e93";;
    gestibile*)          st="$w_manage";  c="#0a84ff";;
    *FALLITO*|*irragg*)  st="$w_unreach"; c="#ff453a";;
    *)                   st="$rest";      c="#8e8e93";;
  esac
  echo "-- $dev: $st | color=$c font=Menlo size=12"
done
echo "---"
# ── Preferences (assorbe il timeout + lingua) ──
echo "$t_prefs | sfimage=gearshape"
echo "--$t_timeout: ${N} $t_min | sfimage=timer"
for n in 1 5 10 15 30 60; do
  mk=""; [ "$n" = "$N" ] && mk="✓ "
  echo "----${mk}${n} $t_min | bash=\"$FL\" param1=set param2=$n terminal=false refresh=true"
done
echo "--$t_lang | sfimage=globe"
for row in "it|Italiano" "en|English" "es|Español" "fr|Français" "de|Deutsch" "zh|中文"; do
  code="${row%%|*}"; name="${row#*|}"; mk=""; [ "$code" = "$lang" ] && mk="✓ "
  echo "----${mk}${name} | bash=\"$SETLANG\" param1=$code terminal=false refresh=true"
done
# ── GitHub (gh) — sync auth alla flotta (solo se sa-gh-sync è installato) ──
if [ -x "$GHSYNC" ]; then
  echo "$t_gh | sfimage=chevron.left.forwardslash.chevron.right"
  echo "--$t_gh_sync | sfimage=arrow.triangle.2.circlepath bash=\"$GHSYNC\" terminal=false"
  echo "--$t_gh_status | sfimage=checkmark.seal bash=\"$GHSYNC\" param1=status terminal=true"
fi
echo "$t_about | sfimage=info.circle"
echo "--sudo-Admiral — $t_desc"
echo "--$t_author: Christian Franchi Viceré"
echo "--MIT License · github.com/ChristianFranchi/sudo-Admiral"
echo "--$t_engine: fleet-lock — FOSS (sudo · ioreg · launchd · SwiftBar)"
echo "$t_quit | sfimage=power bash=/usr/bin/killall param1=SwiftBar terminal=false"
