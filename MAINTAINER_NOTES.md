# Maintainer Notes

This file is the durable handoff for future feature work and releases. Keep it
focused on details that are easy to lose between development sessions; user-facing
changes still belong in `CHANGELOG.md`.

## Current state

- Current manifest version: **2.0.0** (five flip boards, station-style popup and panel).
- Development branch: `main`.
- The repository was clean and matched `origin/main` when these notes were
  written on September 1, 2026.
- The README records **Omarchy 4.0.3** as the tested platform.
- The public `v1.0.1` Git tag points to commit `20068f2`; the later maintainer
  documentation commit does not change the packaged plugin runtime.
- The root `preview.png` is the marketplace preview and contains a visible
  version label. Refresh it when the displayed version changes.

## v2.0.0 flip boards

The popup and panel were redrawn in the flat, monospace, hairline language of
omastorm.com on September 11, 2026. Constraints worth keeping:

- `FlipBoard.qml` and the five `Flip*.qml` tiles import only `QtQuick`. Colors
  and the font come in as properties so the popup, the panel's miniature, the
  picker tiles, and any standalone harness can all drive them. Keep it that
  way; it is what lets `qs -p` render them outside the shell.
- The board for one appearance is chosen once, in `Service.chooseStyle`, via
  the pure `Logic.flipStyleForShow`. Random mode never repeats the previous
  board; previews under random walk `Logic.nextFlipStyle` so a click tour shows
  each board once. `FlipBoard` tiles are loaded with `setSource` and an initial
  `character` so a fresh tile never animates in from its default.
- The popup rebuilds its `FlipBoard` through a `Loader` gated on window
  visibility, so tiles never carry stale digits between shows.
- `Style.cornerRadius` is honored as-is (0 on stock themes). Do not multiply it.
- Screenshots, the demo GIF and MP4, `preview.png`, and the share card were
  regenerated for 2.0.0 on September 11, 2026. Popup captures are the real
  rendered card composited onto the Tokyo Night wallpaper so no workspace
  content leaks; the demo cycles all five boards, four seconds each.
- Do not run `omarchy restart shell` within a couple of seconds of
  `scripts/dev-sync.sh`. On September 11, 2026 a restart landed while the
  hot-reload from dev-sync was still creating objects, and Quickshell
  segfaulted during engine teardown (core dump, `SIGSEGV` under
  `QQmlComponent::createObject` → `QQmlObjectCreator::finalize`). The crash
  handler relaunched the shell and nothing was lost, but let the reload settle
  first.

## Omarchy 4.0.3 plugin API

Third-party plugins no longer receive the shell object itself. `Service.qml`
gets a `PluginShellApi` (see `/usr/share/omarchy/shell/services/`) and bar
widgets get a bar-entry facade. What that means for this plugin:

- `shell.shellConfig` is gone. The bar entry is read from `shell.barConfig`
  (a live copy of `shell.json`'s `bar` section). `Service.entryForPlugin`
  tries that first and falls back to `shellConfig.bar` for older shells.
- `shell.idleConfig` is only populated for clones of `omarchy.idle`, so the
  real screensaver and lock deadlines cannot be read. The service falls back to
  the `screensaverSeconds` and `lockSeconds` stored on the bar entry. They can
  drift from Omarchy's actual idle timeline if the user edits it elsewhere.
- `mutateShellConfig` exists on the scoped API but returns `false` unless the
  plugin is a full bar replacement, so `BarWidget.updateSettings` treats
  anything other than `false` as success and otherwise calls
  `updateEntryInline`. The panel therefore can no longer push screensaver and
  lock deadlines into Omarchy's `idle` config on 4.0.3.
- `firstPartyServiceFor("omarchy.idle")` and `"omarchy.lock"` return `null`
  for bar-widget plugins, so the v1.0.1 lifecycle suppression below is inert on
  4.0.3. The countdown still ends on activity through `IdleMonitor`, but the
  guard against overlaying an already-running screensaver depends on the shell
  granting that proxy again.
- `keepLoaded: true` means a plugin hot-reload keeps the old `Service.qml`
  alive. After editing the service, run `omarchy restart shell`; `dev-sync.sh`
  alone only refreshes the widget and panel.

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

- `./scripts/static-check.sh` passes for manifest version 2.0.0.
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
6. Refresh `preview.png` if its visible version label is changing.
7. Commit the release, create the matching Git tag, and verify the remote
   release state.
8. Update this file if a new architectural constraint or unfinished item would
   otherwise be easy to forget.
