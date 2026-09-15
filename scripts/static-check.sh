#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.wbuf81.idle-screencounter" and
  .version == "2.1.0" and
  .license == "MIT" and
  (.kinds | index("service")) != null and
  (.kinds | index("bar-widget")) != null and
  .barWidget.defaults.warningSeconds < .barWidget.defaults.screensaverSeconds and
  .barWidget.defaults.screensaverSeconds < .barWidget.defaults.lockSeconds
' manifest.json >/dev/null

for entrypoint in Service.qml BarWidget.qml Panel.qml PlacementPicker.qml Logic.js README.md LICENSE \
  FlipBoard.qml FlipSolari.qml FlipBits.qml FlipDrum.qml FlipSweep.qml FlipStep.qml \
  ArrivalsBoard.qml scripts/agents-scan.sh tests/agents-scan.test.sh \
  assets/demo/idle-screen-counter-demo-clean.gif \
  assets/demo/idle-screen-counter-demo-clean.mp4 \
  assets/demo/idle-screen-counter-demo-arrivals.gif \
  assets/demo/idle-screen-counter-demo-arrivals.mp4 \
  assets/screenshots/countdown-popup.webp \
  assets/screenshots/settings-panel.webp \
  assets/screenshots/placement-bottom-right.webp \
  assets/screenshots/arrivals-board.webp \
  preview.png \
  assets/social/idle-screen-counter-share-card.png; do
  test -s "$entrypoint"
done

test "$(stat -c %s preview.png)" -lt 1048576
test "$(stat -c %s assets/social/idle-screen-counter-share-card.png)" -lt 1048576

# The popup must defer to Omarchy's actual lifecycle, not only its own
# IdleMonitor. This prevents a late plugin reload from overlaying a running
# screensaver or lock screen.
grep -Fq 'screensaverStartedThisCycle' Service.qml
grep -Fq 'screensaverWindowCount' Service.qml
grep -Fq 'onScreensaverActiveChanged' Service.qml
grep -Fq 'onSessionLockedChanged' Service.qml
# Every board the picker offers must exist on disk, and the popup must pick
# one per appearance through the shared pure logic.
for style in solari bits drum sweep step; do
  test -s "Flip$(tr '[:lower:]' '[:upper:]' <<< "${style:0:1}")${style:1}.qml"
done
grep -Fq 'flipStyleForShow' Service.qml
# The Arrivals board only ever learns about agents through the scan script.
grep -Fq 'agents-scan.sh' Service.qml
if find assets/demo -maxdepth 1 -type f -name 'screenrecording-*' | grep -q .; then
  echo "Static check failed: raw screen recording found in release assets" >&2
  exit 1
fi

bash -n scripts/dev-sync.sh scripts/release-check.sh scripts/static-check.sh scripts/agents-scan.sh tests/agents-scan.test.sh
node tests/logic.test.js
bash tests/agents-scan.test.sh

if grep -RInE '(^|[^[:alpha:]])(TODO|FIXME|HACK)([^[:alpha:]]|$)' \
  --include='*.qml' --include='*.js' --include='*.sh' --exclude='static-check.sh' .; then
  echo "Static check failed: unresolved marker" >&2
  exit 1
fi

echo "static checks passed"
