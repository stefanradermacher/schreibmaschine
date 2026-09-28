#!/bin/zsh
# Erhöht die Build-Nummer in Config/Schreibmaschine.xcconfig um eins.
#
# Vor jedem Upload in den App Store einmal ausführen und das Ergebnis
# mitcommitten: App Store Connect verlangt für jeden Upload eine höhere Nummer
# als für den vorigen. Lokale Builds brauchen das nicht.
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
