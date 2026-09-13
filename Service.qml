import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

Item {
  id: root

  // Injected by omarchy-shell when it loads a service plugin.
  property var shell: null
  readonly property string pluginId: "io.github.wbuf81.idle-screencounter"
  readonly property var config: entryForPlugin()
  readonly property bool configured: config && String(config.id || "") === pluginId
  readonly property bool enabled: configured && setting("enabled", true) === true
  readonly property int requestedWarningSeconds: Logic.seconds(setting("warningSeconds", 120), 120)
  // Omarchy's idle service is authoritative for these two deadlines. The
  // settings panel writes them too, but reading the central config means a
  // manual shell.json edit is respected immediately.
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle
    : (shell && shell.idleConfig ? shell.idleConfig : ({}))
  readonly property int screensaverSeconds: Logic.seconds(idleConfig.screensaver, Logic.seconds(setting("screensaverSeconds", 600), 600))
  readonly property int lockSeconds: Logic.seconds(idleConfig.lock, Logic.seconds(setting("lockSeconds", 1200), 1200))
  readonly property var timeline: Logic.timeline(requestedWarningSeconds, screensaverSeconds, lockSeconds)
  readonly property int nextDeadlineSeconds: timeline.deadline
  readonly property bool nextEventIsLock: timeline.nextEvent === "lock"
  // Never invent a later deadline than Omarchy's real one. If a hand-edited
  // warning is too late, show the counter for the final available second.
  readonly property int warningSeconds: timeline.effectiveWarning
  readonly property var omarchyIdle: shell && typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var omarchyLock: shell && typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property bool idleArmed: !omarchyIdle || omarchyIdle.idleEnabled === true
  // The shell's lifecycle state is authoritative. A plugin reload can create
  // this service's IdleMonitor partway through an existing idle cycle, so its
  // local elapsed time must never keep a popup above the real screensaver or
  // lock surface.
  readonly property bool screensaverActive: !!omarchyIdle && (
    omarchyIdle.screensaverStartedThisCycle === true
    || Number(omarchyIdle.screensaverWindowCount || 0) > 0
  )
  readonly property bool sessionLocked: !!omarchyLock && (
    omarchyLock.locked === true || omarchyLock.lockRequested === true
  )
  readonly property string placement: Logic.normalizedPlacement(setting("placement", "center"))
  readonly property string flipStyle: Logic.normalizedFlipStyle(setting("flipStyle", "random"))
  // The board that plays for the current appearance. Chosen once per show so
  // a countdown never changes character halfway through.
  property string activeStyle: "solari"
  property string lastStyle: ""
  property string previewStyle: ""
  readonly property string activeStyleLabel: Logic.flipStyleLabel(activeStyle)
  // Arrivals board: running coding agents under the countdown.
  readonly property bool agentsBoardEnabled: setting("agentsBoard", true) !== false
  readonly property string agentsExtra: Logic.normalizedAgentsExtra(setting("agentsExtra", ""))
  property var agentRows: []
  property var previousCpu: ({})
  readonly property bool hasAgents: agentsBoardEnabled && agentRows.length > 0
  // Hovering the card keeps the popup up after the pointer ended idle.
  property bool held: false
  property int heldSeconds: 0
  // Countdown is a notification-like surface, so prefer the theme's semantic
  // countdown color over assuming its generic accent is always appropriate.
  readonly property color countdownAccent: Color.notifications.countdown
  readonly property bool warningVisible: enabled && idleMonitor.isIdle && remainingSeconds > 0
    && !screensaverActive && !sessionLocked
  readonly property bool popupVisible: !screensaverActive && !sessionLocked
    && (warningVisible || previewVisible || held)
  readonly property string effectivePlacement: previewVisible ? previewPlacement : placement
  readonly property int displaySeconds: previewVisible ? previewSeconds
    : (held && remainingSeconds === 0 ? heldSeconds : remainingSeconds)
  readonly property string targetScreenName: {
    var focusedName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    if (focusedName !== "") return focusedName
    return Quickshell.screens.length > 0 ? String(Quickshell.screens[0].name || "") : ""
  }

  property int remainingSeconds: 0
  property bool previewVisible: false
  property int previewSeconds: 10
  property string previewPlacement: "center"
  property double countdownStartedAt: 0

  function setting(key, fallback) {
    var value = config ? config[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // This plugin is enabled through its bar-widget entry. Read that same entry
  // so the service and its settings panel always agree without a second config.
  function entryForPlugin() {
    // Newer shells hand third-party services a scoped API that exposes the
    // bar config directly and no longer carries the whole shell config.
    var barConfig = shell && shell.barConfig ? shell.barConfig
      : (shell && shell.shellConfig && shell.shellConfig.bar ? shell.shellConfig.bar : ({}))
    var layout = barConfig && barConfig.layout ? barConfig.layout : ({})
    var sections = ["left", "center", "right"]
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      var entries = layout[sections[sectionIndex]] || []
      for (var index = 0; index < entries.length; index++) {
        if (entries[index] && String(entries[index].id) === pluginId) return entries[index]
      }
    }
    return ({})
  }

  function format(secondsLeft) {
    return Logic.format(secondsLeft)
  }

  function updateCountdown() {
    if (!idleMonitor.isIdle || screensaverActive || sessionLocked) {
      remainingSeconds = 0
      countdownTimer.stop()
      return
    }
    elapsedSeconds = Math.max(0, Math.floor((Date.now() - countdownStartedAt) / 1000))
    remainingSeconds = Math.max(0, nextDeadlineSeconds - warningSeconds - elapsedSeconds)
    if (remainingSeconds === 0) countdownTimer.stop()
  }

  property int elapsedSeconds: 0

  function beginCountdown() {
    if (!enabled || !idleArmed || screensaverActive || sessionLocked) {
      endCountdown("system-state")
      return
    }
    elapsedSeconds = 0
    countdownStartedAt = Date.now()
    updateCountdown()
    if (remainingSeconds > 0) countdownTimer.start()
    console.log("idle-screen-counter countdown-start warning=" + warningSeconds + " deadline=" + nextDeadlineSeconds + " event=" + (nextEventIsLock ? "lock" : "screensaver") + " remaining=" + remainingSeconds)
  }

  function endCountdown(reason) {
    var wasCounting = countdownTimer.running || remainingSeconds > 0
    countdownTimer.stop()
    elapsedSeconds = 0
    countdownStartedAt = 0
    remainingSeconds = 0
    if (wasCounting) console.log("idle-screen-counter countdown-cancelled " + String(reason || "activity"))
  }

  function chooseStyle(explicit) {
    var chosen
    if (explicit) chosen = Logic.normalizedFlipStyle(explicit)
    else if (previewVisible && flipStyle === "random") chosen = Logic.nextFlipStyle(lastStyle)
    else chosen = Logic.flipStyleForShow(flipStyle, lastStyle, Math.random())
    if (chosen === "random") chosen = Logic.nextFlipStyle(lastStyle)
    lastStyle = chosen
    activeStyle = chosen
  }

  // `style` is optional: the settings panel passes the board it wants to
  // show; a bare preview under "random" tours the boards in order.
  function preview(position, style) {
    previewPlacement = Logic.normalizedPlacement(position || placement)
    previewStyle = style ? String(style) : ""
    previewSeconds = 10
    previewVisible = true
    chooseStyle(previewStyle)
    previewTimer.restart()
    console.log("idle-screen-counter preview " + previewPlacement + " style=" + activeStyle)
  }

  // Every board pick bumps the generation so the popup rebuilds its tiles
  // instead of animating from whatever value the previous board showed.
  property int boardGeneration: 0
  onActiveStyleChanged: boardGeneration += 1

  // Real countdowns pick their board here; previews pick theirs in preview().
  onPopupVisibleChanged: {
    if (popupVisible && !previewVisible) chooseStyle("")
    if (!popupVisible) { agentRows = []; previousCpu = ({}); held = false }
  }
  // A preview that ends while the real warning is up hands over to a fresh
  // board for the live countdown.
  onPreviewVisibleChanged: if (!previewVisible && popupVisible) { chooseStyle(""); boardGeneration += 1 }

  onHeldChanged: {
    if (held) { heldSeconds = displaySeconds; return }
    if (!previewVisible && !idleMonitor.isIdle) endCountdown("released")
  }

  // ------------------------------------------------------------ agents
  readonly property string scanScript: Qt.resolvedUrl("scripts/agents-scan.sh").toString().replace(/^file:\/\//, "")

  Process {
    id: agentScan
    command: ["bash", root.scanScript]
    environment: ({
      AGENTS_EXTRA: root.agentsExtra,
      AGENTS_TITLES: root.candidateTitles()
    })
    stdout: StdioCollector {
      onStreamFinished: root.applyScan(text)
    }
  }

  Timer {
    id: agentScanTimer
    interval: 5000
    repeat: true
    running: root.popupVisible && root.agentsBoardEnabled
    triggeredOnStart: true
    onTriggered: if (!agentScan.running) agentScan.running = true
  }

  // Terminal titles, one "any<TAB>title" per line. The scan attributes a title
  // to a Claude Code session when its text appears in that transcript.
  function candidateTitles() {
    var lines = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tops.length; i++) {
      var title = String(tops[i].title || "")
      if (title !== "") lines.push("any\t" + title)
    }
    return lines.join("\n")
  }

  function applyScan(text) {
    var records
    try { records = JSON.parse(String(text || "[]")) } catch (e) { console.warn("idle-screen-counter agents-scan parse failed"); records = [] }
    if (!Array.isArray(records)) records = []
    // A title claimed by more than one record identifies neither.
    var titleCount = ({})
    for (var t = 0; t < records.length; t++) {
      var wt = String(records[t].windowTitle || "")
      if (wt !== "") titleCount[wt] = (titleCount[wt] || 0) + 1
    }
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var now = Date.now()
    var rows = []
    var nextCpu = ({})
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      if (titleCount[String(r.windowTitle || "")] > 1) r.windowTitle = ""
      var key = String(r.agent) + ":" + String(r.pid)
      nextCpu[key] = Number(r.cpuTicks || 0)
      rows.push(Logic.agentRow(r, root.toplevelFor(r, tops), now, previousCpu[key]))
    }
    previousCpu = nextCpu
    agentRows = Logic.sortedAgentRows(rows)
  }

  // A toplevel belongs to a record when its client pid is the agent or one of
  // its ancestors (claude → shell → terminal). Single-process terminals share
  // one pid across windows; then only an attributed title disambiguates.
  function toplevelFor(record, tops) {
    var pids = [Number(record.pid)]
    var ancestors = Array.isArray(record.ancestors) ? record.ancestors : []
    for (var a = 0; a < ancestors.length; a++) pids.push(Number(ancestors[a]))
    var candidates = []
    for (var i = 0; i < tops.length; i++) {
      var ipc = tops[i].lastIpcObject || {}
      if (pids.indexOf(Number(ipc.pid || -1)) !== -1) candidates.push(tops[i])
    }
    if (candidates.length === 1) return { title: String(candidates[0].title || ""), address: String(candidates[0].address || "") }
    var wanted = String(record.windowTitle || "")
    for (var c = 0; c < candidates.length; c++) {
      if (wanted !== "" && String(candidates[c].title || "") === wanted)
        return { title: wanted, address: String(candidates[c].address || "") }
    }
    return { title: wanted, address: "" }
  }

  // Omarchy 4.0.3 ships Hyprland's Lua dispatch surface, so the dispatcher
  // is a Lua expression rather than the classic "focuswindow address:..".
  function focusAgent(address) {
    var safe = String(address || "").replace(/[^0-9a-fx]/gi, "")
    if (safe === "") return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + safe + '" })')
    held = false
    console.log("idle-screen-counter focus " + safe)
  }

  // Preview with nothing running shows two labelled sample rows so the board
  // is discoverable. Never mistaken for live data: the label says so.
  readonly property var sampleRows: {
    if (!previewVisible || agentRows.length > 0) return []
    var nowS = Math.floor(Date.now() / 1000)
    var rows = Logic.sortedAgentRows([
      Logic.agentRow({ pid: 0, agent: "sample", label: "Claude Code", strategy: "claude", cwd: "/home/you/Projects/your-app", started: nowS - 620, lastActivity: nowS - 12, branch: "main", tools: ["Read", "Edit"], sessionStatus: "busy", cpuTicks: 0, windowTitle: "" }, null, Date.now()),
      Logic.agentRow({ pid: 1, agent: "sample", label: "Codex", strategy: "codex", cwd: "/home/you/Projects/ledger", started: nowS - 3000, lastActivity: nowS - 400, branch: "", tools: ["shell"], sessionStatus: "idle", cpuTicks: 0, windowTitle: "" }, null, Date.now())
    ])
    for (var i = 0; i < rows.length; i++) rows[i].agentLabel += " · sample"
    return rows
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.enabled && root.idleArmed
    timeout: root.warningSeconds
    respectInhibitors: true
    onIsIdleChanged: isIdle ? root.beginCountdown() : root.endCountdown("activity")
  }

  onEnabledChanged: if (!enabled) endCountdown("disabled")
  onIdleArmedChanged: if (!idleArmed) endCountdown("stay-awake")
  onScreensaverActiveChanged: if (screensaverActive) { held = false; endCountdown("screensaver-started") }
  onSessionLockedChanged: if (sessionLocked) { held = false; endCountdown("session-locked") }

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.elapsedSeconds += 1
      root.updateCountdown()
    }
  }

  Timer {
    id: previewTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.previewSeconds = Math.max(0, root.previewSeconds - 1)
      if (root.previewSeconds === 0) {
        stop()
        root.previewVisible = false
      }
    }
  }

  IpcHandler {
    target: "idle-screen-counter"

    function preview(position: string): string {
      root.preview(position, "")
      return "ok"
    }

    function previewStyle(style: string): string {
      root.preview(root.placement, style)
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        configured: root.configured,
        idleArmed: root.idleArmed,
        idle: idleMonitor.isIdle,
        screensaverActive: root.screensaverActive,
        sessionLocked: root.sessionLocked,
        warning: root.requestedWarningSeconds,
        effectiveWarning: root.warningSeconds,
        screensaver: root.screensaverSeconds,
        lock: root.lockSeconds,
        nextEvent: root.nextEventIsLock ? "lock" : "screensaver",
        remaining: root.remainingSeconds,
        visible: root.popupVisible,
        flipStyle: root.flipStyle,
        activeStyle: root.activeStyle,
        agentsBoard: root.agentsBoardEnabled,
        agents: root.agentRows.length,
        held: root.held,
        placement: root.effectivePlacement
      })
    }
  }

  // One passive surface per monitor; only the last-focused monitor displays
  // the card. If Hyprland has no focus yet, the primary screen is used.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData
      screen: modelData
      readonly property bool targetScreen: root.targetScreenName === ""
        || String(popupWindow.screen ? popupWindow.screen.name : "") === root.targetScreenName
      visible: root.popupVisible && targetScreen
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "idle-screen-counter"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Click-through everywhere except the card, and only while the board
      // has rows to hold open. Otherwise the surface stays fully passive.
      mask: root.hasAgents || root.held ? cardRegion : emptyRegion
      Region { id: emptyRegion }
      Region { id: cardRegion; item: card }
      Item {
        id: card
        width: Math.min(Style.space(500), Math.max(1, parent.width - Style.space(32)))
        height: content.implicitHeight + Style.space(34)
        anchors.centerIn: parent
        readonly property real safeHorizontalOffset: Math.min(parent.width * 0.30, Math.max(0, (parent.width - width) / 2 - Style.space(24)))
        readonly property real safeVerticalOffset: Math.min(parent.height * 0.29, Math.max(0, (parent.height - height) / 2 - Style.space(24)))
        anchors.horizontalCenterOffset: root.effectivePlacement.indexOf("right") !== -1 ? safeHorizontalOffset
          : root.effectivePlacement.indexOf("left") !== -1 ? -safeHorizontalOffset : 0
        anchors.verticalCenterOffset: root.effectivePlacement.indexOf("top") !== -1 ? -safeVerticalOffset
          : root.effectivePlacement.indexOf("bottom") !== -1 ? safeVerticalOffset : 0

        HoverHandler {
          enabled: root.hasAgents || root.held
          onHoveredChanged: {
            if (hovered) { root.held = true; heldSafety.restart() }
            else root.held = false
          }
        }
        Timer { id: heldSafety; interval: 45000; onTriggered: root.held = false }

        // Flat station-board palette derived from the popup theme tokens.
        readonly property color alert: Color.urgent
        readonly property color ink: Color.popups.text
        readonly property color dim: Util.alpha(ink, 0.55)
        readonly property color line: Util.alpha(ink, 0.16)
        readonly property color well: Qt.darker(Color.popups.background, 1.35)

        BorderSurface {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Util.alpha(Color.popups.background, 0.97)
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.normalBorderWidth))
        }

        component Caption: Text {
          textFormat: Text.PlainText
          color: card.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.6
          font.capitalization: Font.AllUppercase
          elide: Text.ElideRight
        }

        component Rule: Rectangle {
          width: parent.width
          height: 1
          color: card.line
        }

        Column {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(20)
          anchors.rightMargin: Style.space(20)
          spacing: Style.space(10)

          // Station row: what this is, and what is coming.
          Item {
            width: parent.width
            height: Math.max(headLeft.implicitHeight, headRight.implicitHeight)

            Row {
              id: headLeft
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(7)
              Rectangle {
                width: Style.space(5); height: width
                anchors.verticalCenter: parent.verticalCenter
                color: root.countdownAccent
                SequentialAnimation on opacity {
                  running: root.popupVisible
                  loops: Animation.Infinite
                  PropertyAction { value: 1 }
                  PauseAnimation { duration: 550 }
                  PropertyAction { value: 0 }
                  PauseAnimation { duration: 550 }
                }
              }
              Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: "Idle warning"
                color: card.ink
                font.bold: true
              }
            }

            Row {
              id: headRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Caption {
                text: root.held ? "Held" : (root.previewVisible ? "Preview" : "Live")
                color: root.held ? card.alert : root.countdownAccent
              }
              Caption { text: "·" }
              Caption { text: root.activeStyleLabel }
            }
          }

          Rule {}

          Caption {
            width: parent.width
            topPadding: Style.space(4)
            horizontalAlignment: Text.AlignHCenter
            text: root.held ? "Countdown paused while you look"
              : root.previewVisible ? "Your screensaver would start in"
              : (root.nextEventIsLock ? "Your session locks in" : "Your screensaver starts in")
          }

          // A fresh board per appearance: tiles settle silently on the first
          // value and the chosen style never carries over between shows.
          Item {
            width: parent.width
            height: Style.space(80) + Style.space(8)

            Loader {
              id: boardLoader
              anchors.centerIn: parent
              active: popupWindow.visible
              Connections {
                target: root
                function onBoardGenerationChanged() {
                  if (!boardLoader.active) return
                  boardLoader.active = false
                  boardLoader.active = Qt.binding(function() { return popupWindow.visible })
                }
              }
              sourceComponent: FlipBoard {
                style: root.activeStyle
                value: root.format(root.displaySeconds)
                tileWidth: Style.space(62)
                tileHeight: Style.space(80)
                gap: Style.space(7)
                foreground: card.ink
                accent: root.countdownAccent
                dim: card.dim
                line: card.line
                well: card.well
                fontFamily: Style.font.family
                animated: popupWindow.visible
              }
            }
          }

          ArrivalsBoard {
            visible: rows.length > 0
            width: parent.width
            rows: root.hasAgents ? root.agentRows : root.sampleRows
            style: root.activeStyle
            held: root.held
            foreground: card.ink
            accent: root.countdownAccent
            alert: card.alert
            dim: card.dim
            line: card.line
            well: card.well
            fontFamily: Style.font.family
            captionSize: Style.font.caption
            bodySize: Style.font.bodySmall
            animated: popupWindow.visible
            onFocusRequested: function(address) { root.focusAgent(address) }
          }

          Rule {}

          Item {
            width: parent.width
            height: footLeft.implicitHeight

            Caption {
              id: footLeft
              anchors.left: parent.left
              anchors.right: cursor.left
              anchors.rightMargin: Style.space(12)
              text: root.held ? "Move off the board to dismiss · click a row to focus its terminal"
                : root.previewVisible ? "Preview only · nothing will start" : "Move mouse or press any key to stay active"
            }
            Rectangle {
              id: cursor
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(4, Style.space(6))
              height: footLeft.implicitHeight
              color: root.countdownAccent
              SequentialAnimation on opacity {
                running: root.popupVisible
                loops: Animation.Infinite
                PropertyAction { value: 1 }
                PauseAnimation { duration: 550 }
                PropertyAction { value: 0 }
                PauseAnimation { duration: 550 }
              }
            }
          }
        }
      }
    }
  }

  Component.onCompleted: console.log("idle-screen-counter ready warning=" + warningSeconds + " screensaver=" + screensaverSeconds + " placement=" + placement + " flipStyle=" + flipStyle)
}
