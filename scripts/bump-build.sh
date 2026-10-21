#!/bin/zsh
# Erhöht die Build-Nummer in Config/Schreibmaschine.xcconfig um eins.
#
# Vor jedem Neubau nach Änderungen ausführen und das Ergebnis mitcommitten, damit
# sich installierte Builds unterscheiden lassen; App Store Connect verlangt
# ohnehin für jeden Upload eine höhere Nummer als für den vorigen.
set -euo pipefail
cd "${0:A:h}/.."

file=Config/Schreibmaschine.xcconfig
current=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9][0-9]*\)$/\1/p' "$file")
if [[ -z "$current" ]]; then
    echo "CURRENT_PROJECT_VERSION steht nicht in $file." >&2
    exit 1
fi

next=$((current + 1))
sed -i '' "s/^CURRENT_PROJECT_VERSION = ${current}\$/CURRENT_PROJECT_VERSION = ${next}/" "$file"
echo "Build-Nummer: $current → $next"
