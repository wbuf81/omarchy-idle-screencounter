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
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
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
  // Countdown is a notification-like surface, so prefer the theme's semantic
  // countdown color over assuming its generic accent is always appropriate.
  readonly property color countdownAccent: Color.notifications.countdown
  readonly property bool warningVisible: enabled && idleMonitor.isIdle && remainingSeconds > 0
    && !screensaverActive && !sessionLocked
  readonly property bool popupVisible: !screensaverActive && !sessionLocked
    && (warningVisible || previewVisible)
  readonly property string effectivePlacement: previewVisible ? previewPlacement : placement
  readonly property int displaySeconds: previewVisible ? previewSeconds : remainingSeconds
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
    var shellConfig = shell && shell.shellConfig ? shell.shellConfig : ({})
    var layout = shellConfig.bar && shellConfig.bar.layout ? shellConfig.bar.layout : ({})
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

  function preview(position) {
    previewPlacement = Logic.normalizedPlacement(position || placement)
    previewSeconds = 10
    previewVisible = true
    previewTimer.restart()
    console.log("idle-screen-counter preview " + previewPlacement)
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
  onScreensaverActiveChanged: if (screensaverActive) endCountdown("screensaver-started")
  onSessionLockedChanged: if (sessionLocked) endCountdown("session-locked")

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
      root.preview(position)
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
      // The card is purely informational; all pointer input reaches the app below.
      mask: Region {}
      Item {
        id: card
        width: Math.min(Style.space(480), Math.max(1, parent.width - Style.space(32)))
        height: Style.space(216)
        anchors.centerIn: parent
        readonly property real safeHorizontalOffset: Math.min(parent.width * 0.30, Math.max(0, (parent.width - width) / 2 - Style.space(24)))
        readonly property real safeVerticalOffset: Math.min(parent.height * 0.29, Math.max(0, (parent.height - height) / 2 - Style.space(24)))
        anchors.horizontalCenterOffset: root.effectivePlacement.indexOf("right") !== -1 ? safeHorizontalOffset
          : root.effectivePlacement.indexOf("left") !== -1 ? -safeHorizontalOffset : 0
        anchors.verticalCenterOffset: root.effectivePlacement.indexOf("top") !== -1 ? -safeVerticalOffset
          : root.effectivePlacement.indexOf("bottom") !== -1 ? safeVerticalOffset : 0

        BorderSurface {
          anchors.fill: parent
          radius: Style.cornerRadius * 1.5
          color: Util.alpha(Color.popups.background, 0.96)
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.max(2, Style.space(3))
          radius: height / 2
          color: root.countdownAccent
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(22)
          spacing: Style.space(9)

          Row {
            width: parent.width
            spacing: Style.space(8)
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
              width: Style.space(7)
              height: width
              radius: width / 2
              color: root.countdownAccent
              anchors.verticalCenter: parent.verticalCenter
              SequentialAnimation on opacity {
                running: root.popupVisible
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.35; duration: 850 }
                NumberAnimation { from: 0.35; to: 1; duration: 850 }
              }
            }
            Text {
              text: root.previewVisible ? "COUNTDOWN PREVIEW" : "IDLE WARNING"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 2.0
            }
          }

          Text {
            width: parent.width
            text: root.previewVisible
              ? "YOUR SCREENSAVER WOULD START IN"
              : (root.nextEventIsLock ? "YOUR SESSION LOCKS IN" : "YOUR SCREENSAVER STARTS IN")
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            font.letterSpacing: 1.5
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            id: digits
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(7)
            property string value: root.format(root.displaySeconds)

            Repeater {
              model: 5
              delegate: Item {
                id: digitSlot
                required property int index
                property string character: digits.value.charAt(index)
                width: character === ":" ? Style.space(15) : Style.space(62)
                height: Style.space(78)

                Text {
                  visible: digitSlot.character === ":"
                  anchors.centerIn: parent
                  text: digitSlot.character
                  color: root.countdownAccent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }

                Item {
                  id: digitFace
                  visible: digitSlot.character !== ":"
                  anchors.fill: parent
                  property string currentCharacter: ""
                  property string previousCharacter: ""
                  property real topFlapScale: 1
                  property real bottomFlapScale: 0.02
                  property bool topFlapVisible: false
                  property bool bottomFlapVisible: false
                  property real hingeGlow: 0.38

                  function animateTo(nextCharacter) {
                    if (nextCharacter === ":" || nextCharacter === currentCharacter) return
                    previousCharacter = currentCharacter === "" ? nextCharacter : currentCharacter
                    currentCharacter = nextCharacter
                    flip.restart()
                  }

                  Component.onCompleted: currentCharacter = digitSlot.character
                  Connections {
                    target: digitSlot
                    function onCharacterChanged() { digitFace.animateTo(digitSlot.character) }
                  }

                  SequentialAnimation {
                    id: flip
                    ScriptAction { script: {
                      digitFace.topFlapScale = 1
                      digitFace.bottomFlapScale = 0.02
                      digitFace.hingeGlow = 1
                      digitFace.topFlapVisible = true
                      digitFace.bottomFlapVisible = false
                    } }
                    NumberAnimation {
                      target: digitFace
                      property: "topFlapScale"
                      from: 1
                      to: 0.02
                      duration: 210
                      easing.type: Easing.InCubic
                    }
                    ScriptAction { script: {
                      digitFace.topFlapVisible = false
                      digitFace.bottomFlapVisible = true
                    } }
                    NumberAnimation {
                      target: digitFace
                      property: "bottomFlapScale"
                      from: 0.02
                      to: 1.12
                      duration: 235
                      easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                      target: digitFace
                      property: "bottomFlapScale"
                      from: 1.12
                      to: 1
                      duration: 105
                      easing.type: Easing.OutBack
                    }
                    ParallelAnimation {
                      NumberAnimation {
                        target: digitFace
                        property: "hingeGlow"
                        to: 0.38
                        duration: 160
                      }
                      SequentialAnimation {
                        PauseAnimation { duration: 75 }
                        ScriptAction { script: digitFace.bottomFlapVisible = false }
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(5)
                    color: Util.alpha(Color.background, 0.72)
                    border.color: Util.alpha(root.countdownAccent, 0.42)
                    border.width: Math.max(1, Style.space(1))
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Math.max(1, Style.space(2))
                    height: parent.height / 2 - anchors.margins
                    radius: Style.space(4)
                    color: Style.normalFillFor(Color.popups.text, root.countdownAccent)
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Math.max(1, Style.space(2))
                    height: parent.height / 2 - anchors.margins
                    radius: Style.space(4)
                    color: Util.alpha(root.countdownAccent, 0.055)
                  }

                  // The settled character is painted as two clipped halves.
                  // When the value changes, an old upper flap folds away and a
                  // new lower flap swings down over these stationary faces.
                  Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height / 2
                    clip: true
                    Text {
                      width: digitFace.width
                      height: digitFace.height
                      text: digitFace.currentCharacter
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.displayLarge
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height / 2
                    clip: true
                    Text {
                      y: -digitFace.height / 2
                      width: digitFace.width
                      height: digitFace.height
                      text: digitFace.currentCharacter
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.displayLarge
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  Item {
                    id: upperFlap
                    z: 2
                    visible: digitFace.topFlapVisible
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height / 2
                    clip: true
                    transform: Scale {
                      origin.x: upperFlap.width / 2
                      origin.y: upperFlap.height
                      yScale: digitFace.topFlapScale
                    }
                    Rectangle {
                      anchors.fill: parent
                      color: Util.alpha(Color.background, 0.96)
                    }
                    Text {
                      width: digitFace.width
                      height: digitFace.height
                      text: digitFace.previousCharacter
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.displayLarge
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  Item {
                    id: lowerFlap
                    z: 2
                    visible: digitFace.bottomFlapVisible
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height / 2
                    clip: true
                    transform: Scale {
                      origin.x: lowerFlap.width / 2
                      origin.y: 0
                      yScale: digitFace.bottomFlapScale
                    }
                    Rectangle {
                      anchors.fill: parent
                      color: Util.alpha(Color.background, 0.96)
                    }
                    Text {
                      y: -digitFace.height / 2
                      width: digitFace.width
                      height: digitFace.height
                      text: digitFace.currentCharacter
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.displayLarge
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  Rectangle {
                    z: 3
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.max(1, Style.space(2))
                    color: Util.alpha(root.countdownAccent, digitFace.hingeGlow)
                  }

                  Rectangle {
                    z: 4
                    width: Math.max(2, Style.space(4))
                    height: width
                    radius: width / 2
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.countdownAccent
                  }

                  Rectangle {
                    z: 4
                    width: Math.max(2, Style.space(4))
                    height: width
                    radius: width / 2
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.countdownAccent
                  }
                }
              }
            }
          }

          BorderSurface {
            width: parent.width
            height: Style.space(28)
            radius: Style.cornerRadius
            color: Style.selectedFillFor(Color.popups.text, root.countdownAccent)
            borderSpec: Border.controlSpec("selected", Color.popups.text, root.countdownAccent)

            Text {
              anchors.centerIn: parent
              text: root.previewVisible ? "󰏫  PREVIEW ONLY · NOTHING WILL START" : "󰍽  MOVE MOUSE OR PRESS ANY KEY TO STAY ACTIVE"
              color: Style.selectedStateColor(Color.popups.text, root.countdownAccent)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
            }
          }
        }
      }
    }
  }

  Component.onCompleted: console.log("idle-screen-counter ready warning=" + warningSeconds + " screensaver=" + screensaverSeconds + " placement=" + placement)
}
