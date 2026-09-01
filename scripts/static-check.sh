#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.wbuf81.idle-screencounter" and
  .version == "1.0.1" and
  .license == "MIT" and
  (.kinds | index("service")) != null and
  (.kinds | index("bar-widget")) != null and
  .barWidget.defaults.warningSeconds < .barWidget.defaults.screensaverSeconds and
  .barWidget.defaults.screensaverSeconds < .barWidget.defaults.lockSeconds
' manifest.json >/dev/null

for entrypoint in Service.qml BarWidget.qml Panel.qml PlacementPicker.qml Logic.js README.md LICENSE \
  assets/demo/idle-screen-counter-demo-clean.gif \
  assets/demo/idle-screen-counter-demo-clean.mp4 \
  assets/screenshots/countdown-popup.webp \
  assets/screenshots/settings-panel.webp \
  assets/screenshots/placement-bottom-right.webp \
  assets/social/idle-screen-counter-share-card.png; do
  test -s "$entrypoint"
done

test "$(stat -c %s assets/social/idle-screen-counter-share-card.png)" -lt 1048576

# The popup must defer to Omarchy's actual lifecycle, not only its own
# IdleMonitor. This prevents a late plugin reload from overlaying a running
# screensaver or lock screen.
rg -q 'screensaverStartedThisCycle' Service.qml
rg -q 'screensaverWindowCount' Service.qml
rg -q 'onScreensaverActiveChanged' Service.qml
rg -q 'onSessionLockedChanged' Service.qml
if find assets/demo -maxdepth 1 -type f -name 'screenrecording-*' | grep -q .; then
  echo "Static check failed: raw screen recording found in release assets" >&2
  exit 1
fi

bash -n scripts/dev-sync.sh scripts/release-check.sh scripts/static-check.sh
node tests/logic.test.js

if rg -n '(^|[^[:alpha:]])(TODO|FIXME|HACK)([^[:alpha:]]|$)' --glob '*.qml' --glob '*.js' --glob '*.sh' --glob '!scripts/static-check.sh'; then
  echo "Static check failed: unresolved marker" >&2
  exit 1
fi

echo "static checks passed"
