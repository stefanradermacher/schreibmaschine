#!/bin/zsh
# Builds Schreibmaschine.app with Xcode into ./build and installs it to /Applications.
# Usage: ./build.sh [--no-install] [--adhoc]
#   Signs with the team from Config/Local.xcconfig if it names one; Xcode creates the App ID and the
#   development profile in the developer account if needed. Without a team, or with --adhoc, it
#   signs ad hoc; the app works the same.
set -euo pipefail
cd "${0:A:h}"

install=true
team=false
grep -q '^DEVELOPMENT_TEAM *= *[A-Z0-9]' Config/Local.xcconfig 2>/dev/null && team=true
for argument in "$@"; do
    case "$argument" in
        --no-install) install=false ;;
        --adhoc) team=false ;;
        --team) ;;  # the default when Config/Local.xcconfig names a team
        *) echo "Unbekannte Option: $argument" >&2; exit 1 ;;
    esac
done

if $team; then
    signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration CODE_SIGN_STYLE=Automatic)
else
    # Without a developer account: ad-hoc signed, with the same sandbox as in the App Store.
    signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

mkdir -p .build
if ! xcodebuild -project Schreibmaschine.xcodeproj -scheme Schreibmaschine -configuration Release \
    -derivedDataPath .build/xcode \
    "${signing[@]}" \
    build > .build/xcodebuild.log 2>&1; then
    grep -E "error:" .build/xcodebuild.log >&2 || tail -20 .build/xcodebuild.log >&2
    echo "Build fehlgeschlagen, vollständiges Protokoll: $PWD/.build/xcodebuild.log" >&2
    exit 1
fi

app=build/Schreibmaschine.app
built=.build/xcode/Build/Products/Release/Schreibmaschine.app
rm -rf "$app"
mkdir -p build
ditto "$built" "$app"

# Build copies must not take over opening text files from the installed app.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$built" 2>/dev/null || true
"$lsregister" -u "$app" 2>/dev/null || true

# The build number comes from Config/Schreibmaschine.xcconfig, the same source Xcode reads.
build_number=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9][0-9]*\)$/\1/p' Config/Schreibmaschine.xcconfig)
echo "Gebaut: $PWD/$app (Build ${build_number:-?}, $($team && echo "signiert mit Team" || echo "ad hoc"))"

$install || exit 0

target=/Applications/Schreibmaschine.app
# A copy from the App Store stays untouched: it belongs to the App Store, which updates it,
# and replacing it would lose its receipt. The new build is then only in build/.
if [[ -e "$target/Contents/_MASReceipt/receipt" ]]; then
    echo "Nicht installiert: $target stammt aus dem App Store und bleibt, wie es ist."
    echo "Zum Ausprobieren: open -a \"$PWD/$app\""
    exit 0
fi
# The installed Schreibmaschine has to quit before it can be replaced; it is reopened afterwards.
# Other copies, e.g. one started from Xcode, are left alone.
is_running() { pgrep -qf "^$target/Contents/MacOS/Schreibmaschine"; }
was_running=false
if is_running; then
    was_running=true
    osascript -e "quit app \"$target\"" >/dev/null 2>&1 || true
    for _ in {1..50}; do is_running || break; sleep 0.1; done
    if is_running; then
        echo "Schreibmaschine lässt sich nicht beenden (vielleicht ist noch ein Dialog offen)." >&2
        echo "Bitte Schreibmaschine von Hand beenden und erneut bauen. Gebaut ist die neue Version schon: $PWD/$app" >&2
        exit 1
    fi
fi

rm -rf "$target"
ditto "$app" "$target"
# ditto keeps the bundle's old date; macOS caches app and document icons by that date and would
# go on showing icons from an earlier build.
touch "$target"
"$lsregister" -f "$target"
echo "Installiert: $target"

$was_running && open "$target"
exit 0
