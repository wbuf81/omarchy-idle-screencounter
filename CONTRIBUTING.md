# Contributing

Delightful ideas and careful fixes are welcome.

## Development loop

1. Install the plugin once with `./scripts/dev-sync.sh --enable`.
2. Edit the repository copy.
3. Run `./scripts/dev-sync.sh` to validate, sync, and rescan.
4. Use **Preview countdown** for fast visual iteration.
5. Run `./scripts/release-check.sh` before opening a pull request.

Omarchy rejects plugin symlinks intentionally, so the sync helper copies this
tree into the user plugin directory.

## Design principles

- Stay passive: the popup must never steal keyboard or pointer input.
- Follow Omarchy: use native theme, spacing, typography, border, and control tokens.
- Keep one timeline: warning < screensaver < lock.
- Respect Stay Awake and idle inhibitors.
- Prefer a playful interaction that remains obvious without documentation.

## Useful commands

```sh
./scripts/static-check.sh
./scripts/release-check.sh
omarchy-shell idle-screen-counter preview center
omarchy-shell idle-screen-counter status
quickshell log -p /usr/share/omarchy/shell -t 120 --no-color
```

Please include your Omarchy version, monitor arrangement, active theme, and
reproduction steps with UI or idle-behavior bugs.
