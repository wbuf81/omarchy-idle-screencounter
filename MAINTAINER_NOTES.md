# Maintainer Notes

This file is the durable handoff for future feature work and releases. Keep it
focused on details that are easy to lose between development sessions; user-facing
changes still belong in `CHANGELOG.md`.

## Current state

- Current manifest version: **1.0.1**.
- Development branch: `main`.
- The repository was clean and matched `origin/main` when these notes were
  written on September 1, 2026.
- The README records **Omarchy 4.0.2** as the tested platform.
- No local Git tag for 1.0.1 was present when these notes were written. Confirm
  the remote GitHub release/tag state before publishing or announcing it.

## v1.0.1 lifecycle fix

Commit `20068f2` prevents the countdown from appearing over Omarchy's
screensaver or lock surface.

The important design rule is that Omarchy's first-party services are the
authority for system lifecycle state. The plugin's `IdleMonitor` only measures
its own local idle interval and may be created halfway through an existing idle
cycle after a plugin reload.

`Service.qml` therefore observes:

- `omarchy.idle.screensaverStartedThisCycle`
- `omarchy.idle.screensaverWindowCount`
- `omarchy.lock.locked`
- `omarchy.lock.lockRequested`

When the screensaver or lock is active, both the real countdown and preview are
suppressed, the timer is stopped, and remaining time is cleared. Preserve this
contract when changing idle timing, reload behavior, preview rendering, or
popup visibility. The `status` IPC result exposes `screensaverActive` and
`sessionLocked` for diagnosis.

## Verification status

Automated validation after documenting this handoff:

- `./scripts/static-check.sh` passes for manifest version 1.0.1.
- Pure timing and configuration coverage remains in `tests/logic.test.js`.
- `./scripts/release-check.sh`, including Omarchy's native plugin validator,
  passed on September 1, 2026. It requires a real Omarchy installation and
  should be rerun before a future release.

The repository does not contain evidence that every manual v1.0.1 scenario was
completed. Before tagging the release, record or repeat these focused checks:

- Let the real idle warning appear, then confirm the screensaver immediately
  removes it.
- Reload or re-enable the plugin while the screensaver is already active and
  confirm no popup appears.
- Confirm preview is suppressed while the screensaver is active and while the
  session is locking or locked.
- Confirm activity, Stay Awake, and idle inhibitors still cancel or disarm the
  countdown normally.
- Run the broader manual release checklist in `README.md`.

## Future version checklist

1. Add user-facing changes to `CHANGELOG.md`.
2. Update `manifest.json` and the expected version in
   `scripts/static-check.sh` together.
3. Run `./scripts/static-check.sh` during development.
4. Run `./scripts/release-check.sh` and the README's manual checks on the target
   Omarchy version.
5. Update the tested-version badge in `README.md` when appropriate.
6. Commit the release, create the matching Git tag, and verify the remote
   release state.
7. Update this file if a new architectural constraint or unfinished item would
   otherwise be easy to forget.
