import QtQuick
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

Panel {
  id: root
  moduleName: "io.github.wbuf81.idle-screencounter"
  ipcTarget: moduleName
  manageIpc: false

  property var hostWidget: null
  property var anchorItem: null
  property bool choosingPlacement: false

  readonly property bool enabled: setting("enabled", true) === true
  readonly property int warningSeconds: intSetting("warningSeconds", 120)
  // The central Omarchy idle config is authoritative. Using the live service
  // here prevents a later placement/snap edit from restoring stale duplicates
  // kept in the bar entry after somebody edits shell.json directly.
  readonly property int screensaverSeconds: counter ? Number(counter.screensaverSeconds) : intSetting("screensaverSeconds", 600)
  readonly property int lockSeconds: counter ? Number(counter.lockSeconds) : intSetting("lockSeconds", 1200)
  readonly property int snapSeconds: intSetting("snapSeconds", 30)
  readonly property string placement: String(setting("placement", "center"))
  readonly property string flipStyle: Logic.normalizedFlipStyle(setting("flipStyle", "random"))
  readonly property var counter: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var timeline: Logic.timeline(warningSeconds, screensaverSeconds, lockSeconds)

  // Station palette derived from the bar foreground, in omastorm's spirit:
  // one ink, one dim, one hairline, the theme accent.
  readonly property color ink: root.barForeground
  readonly property color dim: Util.alpha(ink, 0.55)
  readonly property color line: Util.alpha(ink, 0.14)
  readonly property color well: Util.alpha(ink, 0.035)
  readonly property color boardWell: Qt.darker(Color.popups.background, 1.35)

  // The hero board: a live miniature of the popup. Under "random" it tours
  // the boards; hovering a picker tile shows that board instead.
  property string hoverStyle: ""
  property string tourStyle: "solari"
  readonly property string heroStyle: hoverStyle !== "" && hoverStyle !== "random" ? hoverStyle
    : (flipStyle === "random" ? tourStyle : flipStyle)
  property int heroSeconds: 0
  // The host injects `settings` after construction; skip work until then.
  property bool ready: false

  function intSetting(key, fallback) {
    var value = Number(setting(key, fallback))
    return isFinite(value) ? Math.floor(value) : fallback
  }

  function time(value) {
    var safe = Math.max(0, Math.round(value))
    var minutes = Math.floor(safe / 60)
    var seconds = safe % 60
    return (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
  }

  function placementLabel(value) {
    return String(value || "center").replace("-", " ").toUpperCase()
  }

  function snappedTime(value) {
    var step = Math.max(1, root.snapSeconds)
    return Math.round(Number(value) / step) * step
  }

  function save(key, value) {
    var next = Logic.editedSettings(settings, {
      warningSeconds: root.warningSeconds,
      screensaverSeconds: root.screensaverSeconds,
      lockSeconds: root.lockSeconds
    }, key, value, moduleName)

    settings = next
    if (hostWidget) hostWidget.updateSettings(next)
  }

  function choosePlacement(value) {
    save("placement", value)
    if (counter && typeof counter.preview === "function") counter.preview(value, root.heroStyle)
  }

  function chooseStyle(value) {
    save("flipStyle", value)
    if (counter && typeof counter.preview === "function") counter.preview(root.placement, value === "random" ? "" : value)
  }

  function previewPopup() {
    if (counter && typeof counter.preview === "function") counter.preview(root.placement, root.flipStyle === "random" ? "" : root.flipStyle)
  }

  function resetHero() {
    // Change handlers can fire while the panel is still constructing, before
    // the timeline binding has a value.
    var current = root.timeline
    heroSeconds = current ? Math.max(1, current.countdownSeconds) : 1
  }

  onWarningSecondsChanged: if (ready) resetHero()
  onScreensaverSecondsChanged: if (ready) resetHero()
  onLockSecondsChanged: if (ready) resetHero()
  onOpenedChanged: if (opened) { resetHero(); tourStyle = Logic.nextFlipStyle(tourStyle) }
  Component.onCompleted: { ready = true; resetHero() }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.heroSeconds <= 1 ? root.resetHero() : root.heroSeconds -= 1
  }

  Timer {
    interval: 6000
    running: root.opened && root.flipStyle === "random" && root.hoverStyle === ""
    repeat: true
    onTriggered: root.tourStyle = Logic.nextFlipStyle(root.tourStyle)
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.4
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
  }

  component Rule: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: root.line
  }

  Component {
    id: enableSwitch
    ToggleSwitch {
      checked: root.enabled
      foreground: root.barForeground
      accent: Color.accent
      onToggled: root.save("enabled", !root.enabled)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(480))
    contentHeight: fittedContentHeight(root.choosingPlacement ? placementPage.implicitHeight : settingsPage.implicitHeight)

    Column {
      id: settingsPage
      visible: !root.choosingPlacement
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      // ------------------------------------------------------ station row
      Item {
        width: parent.width
        height: Math.max(stationLeft.implicitHeight, stationToggle.implicitHeight)

        Row {
          id: stationLeft
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Rectangle {
            width: Style.space(6); height: width
            anchors.verticalCenter: parent.verticalCenter
            color: root.enabled ? Color.accent : root.dim
            SequentialAnimation on opacity {
              running: root.opened && root.enabled
              loops: Animation.Infinite
              PropertyAction { value: 1 }
              PauseAnimation { duration: 550 }
              PropertyAction { value: 0 }
              PauseAnimation { duration: 550 }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "IDLE SCREEN COUNTER"
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.8
          }
        }

        Loader {
          id: stationToggle
          sourceComponent: enableSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }

        Caption {
          anchors.left: stationLeft.right
          anchors.leftMargin: Style.space(12)
          anchors.right: stationToggle.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideMiddle
          text: root.enabled ? "Armed" : "Paused"
          color: root.enabled ? Color.accent : root.dim
        }
      }

      Rule {}

      // ------------------------------------------------------ hero board
      CursorSurface {
        id: hero
        width: parent.width
        implicitHeight: heroContent.implicitHeight + Style.space(28)
        bordered: true
        foreground: root.barForeground

        HoverHandler {}
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.previewPopup()
        }

        Column {
          id: heroContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(16)
          anchors.rightMargin: Style.space(16)
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: heroHead.implicitHeight
            Row {
              id: heroHead
              anchors.left: parent.left
              spacing: Style.space(7)
              Rectangle { width: Style.space(5); height: width; anchors.verticalCenter: parent.verticalCenter; color: Color.notifications.countdown }
              Caption { text: root.enabled ? "Idle warning" : "Idle warning · off"; color: root.ink; font.bold: true }
            }
            Row {
              anchors.right: parent.right
              spacing: Style.space(6)
              Caption { text: (Logic.FLIP_STYLES.indexOf(root.heroStyle) + 1).toString().padStart(2, "0"); color: Color.accent }
              Caption { text: Logic.flipStyleLabel(root.heroStyle) }
              Caption { visible: root.flipStyle === "random" && root.hoverStyle === ""; text: "· touring" }
            }
          }

          Item {
            width: parent.width
            height: Style.space(56)
            FlipBoard {
              anchors.centerIn: parent
              style: root.heroStyle
              value: root.time(root.heroSeconds)
              tileWidth: Style.space(44)
              tileHeight: Style.space(56)
              gap: Style.space(5)
              foreground: Color.popups.text
              accent: Color.notifications.countdown
              dim: Util.alpha(Color.popups.text, 0.5)
              line: Util.alpha(Color.popups.text, 0.16)
              well: root.boardWell
              fontFamily: Style.font.family
              animated: root.opened
            }
          }

          Item {
            width: parent.width
            height: heroFoot.implicitHeight
            Caption {
              id: heroFoot
              anchors.left: parent.left
              anchors.right: heroSpan.left
              anchors.rightMargin: Style.space(12)
              text: "Click to preview"
            }
            Caption {
              id: heroSpan
              anchors.right: parent.right
              text: "Warn " + root.time(root.warningSeconds) + " → " + (root.timeline.nextEvent === "lock" ? "lock " : "saver ") + root.time(root.timeline.deadline) + " → " + (root.timeline.nextEvent === "lock" ? "saver " + root.time(root.screensaverSeconds) : "lock " + root.time(root.lockSeconds))
            }
          }
        }
      }

      // ------------------------------------------------------ flip style
      Item {
        width: parent.width
        height: styleHeader.implicitHeight
        PanelSectionHeader { id: styleHeader; anchors.left: parent.left; text: "FLIP STYLE"; foreground: root.barForeground }
        Caption {
          anchors.right: parent.right
          anchors.baseline: styleHeader.baseline
          text: root.flipStyle === "random" ? "A different board each time" : Logic.flipStyleLabel(root.flipStyle) + " every time"
        }
      }

      Row {
        id: pickerRow
        width: parent.width
        spacing: Style.space(6)
        readonly property var choices: Logic.FLIP_STYLES.concat(["random"])
        readonly property real tileWidth: (width - spacing * (choices.length - 1)) / choices.length

        Repeater {
          model: pickerRow.choices

          CursorSurface {
            id: pick
            required property string modelData
            required property int index
            readonly property bool selected: root.flipStyle === modelData
            readonly property bool isRandom: modelData === "random"
            width: pickerRow.tileWidth
            implicitHeight: Style.space(74)
            bordered: true
            current: selected
            foreground: root.barForeground
            accent: Color.accent

            HoverHandler {
              onHoveredChanged: root.hoverStyle = hovered ? pick.modelData : (root.hoverStyle === pick.modelData ? "" : root.hoverStyle)
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.chooseStyle(pick.modelData)
            }

            Caption {
              visible: !pick.isRandom
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: Style.space(5)
              text: (pick.index + 1).toString().padStart(2, "0")
              color: pick.selected ? Color.accent : root.dim
              font.letterSpacing: 0.6
              font.pixelSize: Style.font.caption - 1
            }

            Item {
              width: Style.space(24)
              height: Style.space(32)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              FlipBoard {
                visible: !pick.isRandom
                anchors.fill: parent
                style: pick.isRandom ? "solari" : pick.modelData
                value: String((pick.index + 1) % 10)
                tileWidth: parent.width
                tileHeight: parent.height
                foreground: Color.popups.text
                accent: Color.notifications.countdown
                dim: Util.alpha(Color.popups.text, 0.5)
                line: Util.alpha(Color.popups.text, 0.2)
                well: root.boardWell
                fontFamily: Style.font.family
                animated: false
              }
              Text {
                visible: pick.isRandom
                anchors.centerIn: parent
                text: "󰒟"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }
            }

            Caption {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(6)
              horizontalAlignment: Text.AlignHCenter
              text: pick.modelData
              color: pick.selected ? Color.accent : root.dim
              font.letterSpacing: 0.8
              font.pixelSize: Style.font.caption - 1
            }
          }
        }
      }

      Rule {}

      // ------------------------------------------------------ timeline
      Item {
        width: parent.width
        height: Math.max(timelineHeader.implicitHeight, snapGroup.implicitHeight)
        PanelSectionHeader { id: timelineHeader; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "IDLE TIMELINE"; foreground: root.barForeground }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Caption { anchors.verticalCenter: parent.verticalCenter; text: "Snap" }
          ButtonGroup {
            id: snapGroup
            anchors.verticalCenter: parent.verticalCenter
            options: [
              { value: "15", label: "15s" },
              { value: "30", label: "30s" },
              { value: "60", label: "1m" }
            ]
            value: String(root.snapSeconds)
            foreground: root.barForeground
            accent: Color.accent
            fontSize: Style.font.caption
            onChanged: function(value) { root.save("snapSeconds", Number(value)) }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)

        Repeater {
          model: [
            { key: "warningSeconds", label: "Warn", description: "Board appears after", value: root.warningSeconds, minimum: 15, maximum: 900, presets: [{value:"30",label:"30s"},{value:"60",label:"1m"},{value:"120",label:"2m"},{value:"300",label:"5m"}] },
            { key: "screensaverSeconds", label: "Screensaver", description: "Countdown hits zero at", value: root.screensaverSeconds, minimum: 30, maximum: 1800, presets: [{value:"60",label:"1m"},{value:"180",label:"3m"},{value:"300",label:"5m"},{value:"600",label:"10m"}] },
            { key: "lockSeconds", label: "Lock", description: "Password required at", value: root.lockSeconds, minimum: 45, maximum: 3600, presets: [{value:"300",label:"5m"},{value:"600",label:"10m"},{value:"1200",label:"20m"},{value:"1800",label:"30m"}] }
          ]

          delegate: Column {
            id: timingRow
            required property var modelData
            required property int index
            property real draftValue: modelData.value
            width: parent.width
            spacing: Style.space(4)

            Rule { visible: timingRow.index > 0; opacity: 0.7 }

            Item {
              width: parent.width
              height: Math.max(rowLabels.implicitHeight, rowPresets.implicitHeight, rowValue.implicitHeight)

              Row {
                id: rowLabels
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Caption { text: timingRow.modelData.label; color: root.ink; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Caption { text: timingRow.modelData.description; font.capitalization: Font.MixedCase; font.letterSpacing: 0.2; anchors.verticalCenter: parent.verticalCenter }
              }

              ButtonGroup {
                id: rowPresets
                anchors.right: rowValue.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                options: timingRow.modelData.presets
                value: String(timingRow.modelData.value)
                foreground: root.barForeground
                accent: Color.accent
                fontSize: Style.font.caption
                onChanged: function(value) { root.save(timingRow.modelData.key, Number(value)) }
              }

              Text {
                id: rowValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.time(timingRow.draftValue)
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                width: implicitWidth
              }
            }

            PanelSlider {
              id: timingSlider
              bar: root.bar
              width: parent.width
              minimum: timingRow.modelData.minimum
              maximum: timingRow.modelData.maximum
              step: root.snapSeconds
              integer: true
              value: timingRow.modelData.value
              onMoved: function(value) {
                var snapped = root.snappedTime(value)
                timingSlider.liveValue = snapped
                timingRow.draftValue = snapped
              }
              onReleased: function(value) {
                var snapped = root.snappedTime(value)
                timingRow.draftValue = snapped
                root.save(timingRow.modelData.key, snapped)
              }
            }
          }
        }
      }

      Rule {}

      // ------------------------------------------------------ footer row
      Item {
        width: parent.width
        height: Math.max(footNote.implicitHeight, footButtons.implicitHeight)

        Caption {
          id: footNote
          anchors.left: parent.left
          anchors.right: footButtons.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "Never blocks clicks or keys"
        }

        Row {
          id: footButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Button {
            text: root.placementLabel(root.placement) + "  󰅂"
            iconText: "󰍹"
            bordered: true
            foreground: root.barForeground
            accent: Color.accent
            fontSize: Style.font.caption
            onClicked: root.choosingPlacement = true
          }
          Button {
            text: "PREVIEW"
            iconText: "󰐊"
            bordered: true
            selected: true
            foreground: root.barForeground
            accent: Color.accent
            fontSize: Style.font.caption
            onClicked: root.previewPopup()
          }
        }
      }
    }

    // -------------------------------------------------------- placement page
    Column {
      id: placementPage
      visible: root.choosingPlacement
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      Item {
        width: parent.width
        height: Math.max(backButton.implicitHeight, pickerHeading.implicitHeight)

        Button {
          id: backButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰁍"
          text: "BACK"
          bordered: true
          foreground: root.barForeground
          accent: Color.accent
          fontSize: Style.font.caption
          onClicked: root.choosingPlacement = false
        }

        Column {
          id: pickerHeading
          anchors.left: backButton.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "LANDING SPOT"
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.8
          }
          Caption { width: parent.width; text: "Click anywhere in the mini desktop"; font.capitalization: Font.MixedCase; font.letterSpacing: 0.2 }
        }
      }

      Rule {}

      PlacementPicker {
        width: parent.width
        selected: root.placement
        foreground: root.barForeground
        accent: Color.accent
        onPicked: function(value) { root.choosePlacement(value) }
      }

      Caption {
        width: parent.width
        text: "The real board previews on your desktop as you choose"
        font.capitalization: Font.MixedCase
        font.letterSpacing: 0.2
        horizontalAlignment: Text.AlignHCenter
      }

      Button {
        width: parent.width
        text: "DONE · " + root.placementLabel(root.placement)
        iconText: "󰄬"
        bordered: true
        selected: true
        foreground: root.barForeground
        accent: Color.accent
        fontSize: Style.font.caption
        onClicked: root.choosingPlacement = false
      }
    }
  }
}
