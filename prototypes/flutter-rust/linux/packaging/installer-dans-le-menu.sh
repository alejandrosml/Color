#!/bin/sh
# Ajoute Color au menu des applications de ce compte, sans droits
# d'administrateur. Le programme reste dans le dossier de ce script.
#
#   ./installer-dans-le-menu.sh            ajoute l'entrée et ses icônes
#   ./installer-dans-le-menu.sh --retirer  retire ce que ce script a ajouté
#
# Les dessins, la galerie et la copie de récupération ne sont jamais touchés.
# Après avoir déplacé le dossier, relancer ce script : l'entrée du menu
# contient son chemin.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
id=com.example.edupaint_flutter_study
entry="$data/applications/$id.desktop"
sizes="16 32 48 64 128 256 512"
case "${1:-}" in
  --retirer)
    rm -f "$entry"
    for size in $sizes; do
      rm -f "$data/icons/hicolor/${size}x${size}/apps/$id.png"
    done
    echo "Color est retiré du menu. Tes dessins et le dossier du programme ne sont pas touchés."
    exit 0 ;;
  "") ;;
  *) echo "Option inconnue : $1" >&2; exit 2 ;;
esac
if [ ! -x "$here/color" ] || [ ! -f "$here/share/$id.desktop" ]; then
  echo "Ce script doit rester dans le dossier de Color, à côté du programme « color »." >&2
  exit 1
fi
# Le chemin est écrit entre guillemets dans l'entrée : ces caractères y
# auraient un autre sens.
case "$here" in
  *'"'*|*'`'*|*'$'*|*'\'*|*'%'*|*'
'*)
    echo "Le chemin de ce dossier contient un caractère que le menu n'accepte pas (\" \` \$ \\ %)." >&2
    echo "Renomme ou déplace le dossier, puis relance ce script." >&2
    exit 1 ;;
esac
mkdir -p "$data/applications"
for size in $sizes; do
  mkdir -p "$data/icons/hicolor/${size}x${size}/apps"
  cp "$here/share/icons/color-$size.png" "$data/icons/hicolor/${size}x${size}/apps/$id.png"
done
# Tout sauf la ligne Exec vient du modèle ; elle nomme le programme d'ici.
{
  grep -v '^Exec=' "$here/share/$id.desktop"
  printf 'Exec="%s/color"\n' "$here"
} >"$entry.nouveau"
mv "$entry.nouveau" "$entry"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data/applications" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f "$data/icons/hicolor" >/dev/null 2>&1 || true
fi
echo "Color est dans le menu des applications de ce compte."
echo "Pour le retirer : $here/installer-dans-le-menu.sh --retirer"
