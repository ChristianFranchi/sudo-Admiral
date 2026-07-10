#!/bin/bash
# sa-setlang — salva la lingua scelta per sudo-Admiral (letta dal plugin SwiftBar)
d="$HOME/.config/sudo-admiral"; mkdir -p "$d"
case "${1:-}" in it|en|es|fr|de|zh) printf '%s\n' "$1" > "$d/lang";; esac
