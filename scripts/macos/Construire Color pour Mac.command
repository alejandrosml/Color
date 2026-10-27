#!/bin/bash
# Construit Color pour ce Mac. Un double-clic suffit.
#
# Ce fichier ne fait que trouver Python et passer la main a
# construction-mac/construire-color.py, qui verifie l'outillage, lance la
# recette du projet (tests, compilation par Xcode, signature locale) et depose
# Color.app a cote de ce fichier. Rien n'est supprime ; aucun fichier existant
# n'est remplace en dehors des dossiers de travail de la construction.
cd "$(dirname "$0")" || exit 1
ICI="$(pwd)"
# Homebrew d'abord (Rust et Python du projet), puis rustup, puis le systeme.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.cargo/bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"
PROGRAMME="$ICI/construction-mac/construire-color.py"
PYTHON=""
for candidat in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null)" /usr/bin/python3; do
  if [ -n "$candidat" ] && [ -x "$candidat" ] && "$candidat" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    PYTHON="$candidat"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "Python 3 est introuvable sur ce Mac : la construction ne peut pas commencer."
  echo "Il est fourni avec les outils en ligne de commande d'Xcode."
  exit 1
fi
if [ ! -f "$PROGRAMME" ]; then
  echo "Fichier introuvable : $PROGRAMME"
  exit 1
fi
# caffeinate empeche seulement la mise en veille pendant la construction.
if [ -x /usr/bin/caffeinate ]; then
  exec /usr/bin/caffeinate -i "$PYTHON" "$PROGRAMME" "$ICI"
fi
exec "$PYTHON" "$PROGRAMME" "$ICI"
