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
  readonly property var counter: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

  function intSetting(key, fallback) {
    var value = Number(setting(key, fallback))
    return isFinite(value) ? Math.floor(value) : fallback
  }

  function time(value) {
    var safe = Math.max(0, Math.round(value))
    var minutes = Math.floor(safe / 60)
    var seconds = safe % 60
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
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
    if (counter && typeof counter.preview === "function") counter.preview(value)
  }

  function previewPopup() {
    if (counter && typeof counter.preview === "function") counter.preview(root.placement)
  }

  Component {
    id: heroIcon
    Text {
      text: "󰒲"
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }
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
    contentWidth: fittedContentWidth(Style.space(470))
    contentHeight: fittedContentHeight(root.choosingPlacement ? placementPage.implicitHeight : settingsPage.implicitHeight)

    Column {
      id: settingsPage
      visible: !root.choosingPlacement
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)

      PanelHero {
        iconComponent: heroIcon
        title: "Idle screen counter"
        meta: root.enabled ? "Ready for your next coffee break" : "Countdown paused"
        detail: root.enabled ? "ON" : "OFF"
        foreground: root.barForeground
        trailingControl: enableSwitch
      }

      Text {
        width: parent.width
        text: "A gentle heads-up before Omarchy starts the screensaver and locks your session."
        color: Qt.darker(root.barForeground, 1.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator { foreground: root.barForeground }
      PanelSectionHeader { text: "IDLE TIMELINE"; foreground: root.barForeground }

      CursorSurface {
        width: parent.width
        implicitHeight: snapContent.implicitHeight + Style.space(20)
        bordered: true
        foreground: root.barForeground

        Column {
          id: snapContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(13)
          anchors.rightMargin: Style.space(13)
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(snapTitle.implicitHeight, snapGroup.implicitHeight)

            Column {
              id: snapTitle
              anchors.left: parent.left
              anchors.right: snapGroup.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "Slider snap"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                width: parent.width
                text: "Choose how precisely the handles move."
                color: Qt.darker(root.barForeground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            ButtonGroup {
              id: snapGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: [
                { value: "15", label: "15s" },
                { value: "30", label: "30s" },
                { value: "60", label: "1m" }
              ]
              value: String(root.snapSeconds)
              foreground: root.barForeground
              accent: Color.accent
              fontSize: Style.font.bodySmall
              onChanged: function(value) { root.save("snapSeconds", Number(value)) }
            }
          }
        }
      }

      Repeater {
        model: [
          { key: "warningSeconds", icon: "󰔟", label: "Show the countdown", description: "How long to wait before the split-flap warning appears.", value: root.warningSeconds, minimum: 15, maximum: 900, presets: [{value:"30",label:"30s"},{value:"60",label:"1m"},{value:"120",label:"2m"},{value:"300",label:"5m"}] },
          { key: "screensaverSeconds", icon: "󰒲", label: "Start the screensaver", description: "The countdown reaches zero at this idle time.", value: root.screensaverSeconds, minimum: 30, maximum: 1800, presets: [{value:"60",label:"1m"},{value:"180",label:"3m"},{value:"300",label:"5m"},{value:"600",label:"10m"}] },
          { key: "lockSeconds", icon: "󰌾", label: "Lock the session", description: "Require your password after this much idle time.", value: root.lockSeconds, minimum: 45, maximum: 3600, presets: [{value:"300",label:"5m"},{value:"600",label:"10m"},{value:"1200",label:"20m"},{value:"1800",label:"30m"}] }
        ]

        delegate: CursorSurface {
          id: timingCard
          required property var modelData
          property real draftValue: modelData.value
          width: parent.width
          implicitHeight: timingContent.implicitHeight + Style.space(22)
          bordered: true
          foreground: root.barForeground

          HoverHandler {}

          Column {
            id: timingContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(13)
            anchors.rightMargin: Style.space(13)
            spacing: Style.space(9)

            Item {
              width: parent.width
              implicitHeight: Math.max(timingIcon.implicitHeight, timingLabels.implicitHeight, timingValue.implicitHeight)

              Text {
                id: timingIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: timingCard.modelData.icon
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              Column {
                id: timingLabels
                anchors.left: timingIcon.right
                anchors.leftMargin: Style.space(11)
                anchors.right: timingValue.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: timingCard.modelData.label
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: timingCard.modelData.description
                  color: Qt.darker(root.barForeground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              BorderSurface {
                id: timingValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: timingValueText.implicitWidth + Style.space(12)
                implicitHeight: timingValueText.implicitHeight + Style.space(6)
                radius: Style.cornerRadius
                color: Style.selectedFillFor(root.barForeground, Color.accent)
                borderSpec: Border.controlSpec("selected", root.barForeground, Color.accent)

                Text {
                  id: timingValueText
                  anchors.centerIn: parent
                  text: root.time(timingCard.draftValue)
                  color: Style.selectedStateColor(root.barForeground, Color.accent)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }

            PanelSlider {
              id: timingSlider
              bar: root.bar
              width: parent.width
              minimum: timingCard.modelData.minimum
              maximum: timingCard.modelData.maximum
              step: root.snapSeconds
              integer: true
              value: timingCard.modelData.value
              onMoved: function(value) {
                var snapped = root.snappedTime(value)
                timingSlider.liveValue = snapped
                timingCard.draftValue = snapped
              }
              onReleased: function(value) {
                var snapped = root.snappedTime(value)
                timingCard.draftValue = snapped
                root.save(timingCard.modelData.key, snapped)
              }
            }

            ButtonGroup {
              anchors.horizontalCenter: parent.horizontalCenter
              options: timingCard.modelData.presets
              value: String(timingCard.modelData.value)
              foreground: root.barForeground
              accent: Color.accent
              fontSize: Style.font.bodySmall
              onChanged: function(value) { root.save(timingCard.modelData.key, Number(value)) }
            }
          }
        }
      }

      PanelSeparator { foreground: root.barForeground }
      PanelSectionHeader { text: "APPEARANCE"; foreground: root.barForeground }

      CursorSurface {
        id: placementRow
        width: parent.width
        implicitHeight: Style.space(68)
        bordered: true
        foreground: root.barForeground

        HoverHandler {}
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.choosingPlacement = true
        }

        Item {
          anchors.fill: parent
          anchors.margins: Style.space(12)

          Text {
            id: placementIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍹"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          Column {
            anchors.left: placementIcon.right
            anchors.leftMargin: Style.space(11)
            anchors.right: placementPreview.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Popup position"
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.placementLabel(root.placement) + " · Click to choose visually"
              color: Qt.darker(root.barForeground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          BorderSurface {
            id: placementPreview
            anchors.right: arrow.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            height: Style.space(32)
            color: Util.alpha(root.barForeground, 0.04)
            radius: Math.max(2, Style.cornerRadius / 2)
            borderSpec: Border.flat(Util.alpha(root.barForeground, 0.30), 1)

            Rectangle {
              width: Style.space(18)
              height: Style.space(8)
              radius: 2
              color: Color.accent
              x: root.placement.indexOf("left") !== -1 ? Style.space(4)
                : root.placement.indexOf("right") !== -1 ? parent.width - width - Style.space(4)
                : (parent.width - width) / 2
              y: root.placement.indexOf("top") !== -1 ? Style.space(4)
                : root.placement.indexOf("bottom") !== -1 ? parent.height - height - Style.space(4)
                : (parent.height - height) / 2
            }
          }

          Text {
            id: arrow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅂"
            color: Qt.darker(root.barForeground, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }
        }
      }

      Button {
        width: parent.width
        text: "Preview countdown"
        iconText: "󰐊"
        bordered: true
        foreground: root.barForeground
        accent: Color.accent
        onClicked: root.previewPopup()
      }
    }

    Column {
      id: placementPage
      visible: root.choosingPlacement
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)

      Item {
        width: parent.width
        implicitHeight: Math.max(backButton.implicitHeight, pickerHeading.implicitHeight)

        Button {
          id: backButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰁍"
          text: "Back"
          bordered: true
          foreground: root.barForeground
          accent: Color.accent
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
            text: "Choose a landing spot"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: "Click anywhere in the mini desktop."
            color: Qt.darker(root.barForeground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      PlacementPicker {
        width: parent.width
        selected: root.placement
        foreground: root.barForeground
        accent: Color.accent
        onPicked: function(value) { root.choosePlacement(value) }
      }

      Text {
        width: parent.width
        text: "The real popup previews on your desktop as you choose. It never blocks clicks or keyboard input."
        color: Qt.darker(root.barForeground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }

      Button {
        width: parent.width
        text: "Done · " + root.placementLabel(root.placement)
        iconText: "󰄬"
        bordered: true
        selected: true
        foreground: root.barForeground
        accent: Color.accent
        onClicked: root.choosingPlacement = false
      }
    }
  }
}
