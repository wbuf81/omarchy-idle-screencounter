import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string selected: "center"
  property string hoveredPosition: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  readonly property string previewPosition: hoveredPosition !== "" ? hoveredPosition : selected
  signal picked(string value)

  implicitHeight: screen.height + caption.implicitHeight + Style.space(10)

  BorderSurface {
    id: screen
    width: parent.width
    height: Math.round(width * 0.58)
    color: Util.alpha(root.foreground, 0.035)
    radius: Style.cornerRadius
    borderSpec: Border.flat(Util.alpha(root.foreground, 0.34), Math.max(1, Style.space(2)))
    clip: true

    Rectangle { anchors.fill: parent; color: Util.alpha(Color.popups.background, 0.90) }
    Rectangle {
      width: parent.width * 0.58
      height: width
      radius: width / 2
      x: parent.width * 0.56
      y: -height * 0.38
      color: Util.alpha(root.accent, 0.08)
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Style.space(17)
      color: Util.alpha(root.foreground, 0.10)

      Row {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Repeater {
          model: 3
          Rectangle { width: Style.space(4); height: width; radius: width / 2; color: Util.alpha(root.foreground, 0.45) }
        }
      }
      Text {
        anchors.centerIn: parent
        text: "OMARCHY"
        color: Util.alpha(root.foreground, 0.48)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 1.2
      }
    }

    BorderSurface {
      x: parent.width * 0.08
      y: parent.height * 0.25
      width: parent.width * 0.37
      height: parent.height * 0.46
      color: Util.alpha(root.foreground, 0.035)
      radius: Math.max(2, Style.cornerRadius / 2)
      borderSpec: Border.flat(Util.alpha(root.foreground, 0.12), 1)
      Column {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(5)
        Rectangle { width: parent.width * 0.52; height: Style.space(5); radius: 2; color: Util.alpha(root.foreground, 0.18) }
        Rectangle { width: parent.width; height: Style.space(4); radius: 2; color: Util.alpha(root.foreground, 0.09) }
        Rectangle { width: parent.width * 0.82; height: Style.space(4); radius: 2; color: Util.alpha(root.foreground, 0.09) }
      }
    }
    BorderSurface {
      x: parent.width * 0.50
      y: parent.height * 0.34
      width: parent.width * 0.38
      height: parent.height * 0.42
      color: Util.alpha(root.foreground, 0.025)
      radius: Math.max(2, Style.cornerRadius / 2)
      borderSpec: Border.flat(Util.alpha(root.foreground, 0.10), 1)
    }

    Repeater {
      model: [
        { value: "top-left", x: 0.09, y: 0.19 },
        { value: "top", x: 0.50, y: 0.19 },
        { value: "top-right", x: 0.91, y: 0.19 },
        { value: "center", x: 0.50, y: 0.50 },
        { value: "bottom-left", x: 0.09, y: 0.82 },
        { value: "bottom", x: 0.50, y: 0.82 },
        { value: "bottom-right", x: 0.91, y: 0.82 }
      ]

      delegate: Item {
        required property var modelData
        width: Style.space(58)
        height: Style.space(45)
        x: modelData.x * screen.width - width / 2
        y: modelData.y * screen.height - height / 2

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(24)
          height: width
          radius: Style.cornerRadius > 0 ? width / 2 : 0
          color: modelData.value === root.selected
            ? Style.selectedFillFor(root.foreground, root.accent)
            : (zoneMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : Util.alpha(root.foreground, 0.025))
          border.color: modelData.value === root.selected ? root.accent : Util.alpha(root.foreground, zoneMouse.containsMouse ? 0.48 : 0.18)
          border.width: Math.max(1, Style.space(1))

          Text {
            anchors.centerIn: parent
            text: modelData.value === root.selected ? "󰄬" : ""
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: zoneMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.hoveredPosition = String(modelData.value)
          onExited: if (root.hoveredPosition === String(modelData.value)) root.hoveredPosition = ""
          onClicked: root.picked(String(modelData.value))
        }
      }
    }

    BorderSurface {
      id: popupPreview
      width: Style.space(92)
      height: Style.space(42)
      radius: Math.max(2, Style.cornerRadius / 2)
      color: Util.alpha(Color.popups.background, 0.98)
      borderSpec: Border.flat(root.accent, Math.max(1, Style.space(1)))
      x: root.previewPosition.indexOf("left") !== -1 ? Style.space(42)
        : root.previewPosition.indexOf("right") !== -1 ? screen.width - width - Style.space(42)
        : (screen.width - width) / 2
      y: root.previewPosition.indexOf("top") !== -1 ? Style.space(44)
        : root.previewPosition.indexOf("bottom") !== -1 ? screen.height - height - Style.space(24)
        : (screen.height - height) / 2

      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(1)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "00:42"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 1.2
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "SCREEN IDLE"
          color: Util.alpha(Color.popups.text, 0.62)
          font.family: Style.font.family
          font.pixelSize: Math.max(7, Style.font.bodySmall * 0.65)
          font.bold: true
          font.letterSpacing: 0.8
        }
      }
    }
  }

  Text {
    id: caption
    anchors.top: screen.bottom
    anchors.topMargin: Style.space(10)
    width: parent.width
    text: String(root.previewPosition).replace("-", " ").toUpperCase()
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.4
    horizontalAlignment: Text.AlignHCenter
  }
}
