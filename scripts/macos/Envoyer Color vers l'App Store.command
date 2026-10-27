#!/bin/bash
# Construit Color pour le Mac, l iPhone et l iPad et l envoie a App Store Connect.
#
# Ce fichier ne fait que trouver Python et passer la main a
# construction-mac/envoyer-app-store.py. Tout ce qu'il installe va dans le dossier
# « mobiles », a cote des dossiers de construction ; rien de ce qui est a toi
# n'est supprime.
cd "$(dirname "$0")" || exit 1
ICI="$(pwd)"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"
PROGRAMME="$ICI/construction-mac/envoyer-app-store.py"
PYTHON=""
for candidat in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null)" /usr/bin/python3; do
  if [ -n "$candidat" ] && [ -x "$candidat" ] && "$candidat" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    PYTHON="$candidat"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "Python 3 est introuvable sur ce Mac."
  exit 1
fi
if [ ! -f "$PROGRAMME" ]; then
  echo "Fichier introuvable : $PROGRAMME"
  exit 1
fi
# caffeinate empeche seulement la mise en veille pendant le travail.
/usr/bin/caffeinate -i "$PYTHON" "$PROGRAMME" "$ICI" "$@"
STATUT=$?
echo
read -r -p "Appuie sur Entree pour fermer cette fenetre." _
exit $STATUT
