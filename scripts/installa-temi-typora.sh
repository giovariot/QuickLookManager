#!/bin/bash
# Installa nella cartella dei temi di Typora i temi di QuickLook Manager, preceduti da scripts/typora/compat.css
# (tabelle e citazioni). I file si chiamano qlm-*.css: non toccano i temi di Typora.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Application Support/abnerworks.Typora/themes"
[ -d "$DEST" ] || { echo "Cartella dei temi di Typora non trovata: $DEST" >&2; exit 1; }
for f in typora github claude-chat claude-code; do
  cat "$ROOT/scripts/typora/compat.css" "$ROOT/Modules/Text/Resources/Web/themes/$f.css" > "$DEST/qlm-$f.css"
done
echo "Installati in $DEST: qlm-typora, qlm-github, qlm-claude-chat, qlm-claude-code"
