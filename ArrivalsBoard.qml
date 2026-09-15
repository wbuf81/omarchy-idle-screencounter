import QtQuick

// The Arrivals board: one departure-board row per running coding agent.
// Pure QtQuick. Rows come in already sorted; every theme value is a property.
Item {
  id: board

  property var rows: []
  property string style: "solari"
  property bool held: false
  property int maxRows: 5
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color alert: "#f776c6"
  property color dim: "#565f89"
  property color line: "#2f3349"
  property color well: "#1a1b26"
  property string fontFamily: "monospace"
  property real captionSize: 10
  property real bodySize: 11
  property bool animated: true

  signal focusRequested(string address)

  // Detail line for the row under the pointer while held; the host shows it
  // in the footer so the card never changes height.
  property string hoveredDetail: ""
  onHeldChanged: if (!held) hoveredDetail = ""

  readonly property int shown: rows.length > maxRows ? maxRows - 1 : rows.length
  readonly property int hidden: rows.length - shown
  readonly property int working: countStatus("working")
  readonly property int needing: countStatus("needs-you")
  readonly property real rowHeight: Math.round(bodySize * 2.9)
  readonly property real cell: Math.round(bodySize * 1.8)
  readonly property real tileW: Math.round(cell * 0.55)
  readonly property real agentWidth: Math.round(width * 0.17)
  readonly property real projectWidth: Math.round(width * 0.19)
  readonly property real nowWidth: tileW * 11 + 10
  readonly property real elapsedWidth: tileW * 5 + 4

  // "Bash › Bash › Bash › Write" reads as "Bash ×3 › Write".
  function collapseTools(tools) {
    var out = []
    for (var i = 0; i < tools.length; i++) {
      var name = String(tools[i])
      if (out.length && out[out.length - 1].name === name) out[out.length - 1].count += 1
      else out.push({ name: name, count: 1 })
    }
    return out.map(function(t) { return t.count > 1 ? t.name + " ×" + t.count : t.name }).join(" › ")
  }

  function countStatus(status) {
    var n = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].status === status) n++
    return n
  }

  implicitWidth: 460
  implicitHeight: rows.length === 0 ? 0 : column.implicitHeight

  component Caption: Text {
    textFormat: Text.PlainText
    color: board.dim
    font.family: board.fontFamily
    font.pixelSize: board.captionSize
    font.letterSpacing: 1.4
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
  }

  component Chip: Rectangle {
    id: chip
    property string status: "idle"
    readonly property bool isWorking: status === "working"
    readonly property bool isNeeds: status === "needs-you"
    implicitWidth: chipRow.implicitWidth + 12
    implicitHeight: chipText.implicitHeight + 4
    color: isWorking ? board.accent : "transparent"
    border.color: isWorking ? board.accent : (isNeeds ? board.alert : board.line)
    border.width: 1
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 4
      Rectangle {
        visible: chip.isWorking || chip.isNeeds
        width: 4
        height: Math.round(chipText.implicitHeight * 0.65)
        anchors.verticalCenter: parent.verticalCenter
        color: chip.isWorking ? board.well : board.alert
        SequentialAnimation on opacity {
          running: board.visible && (chip.isWorking || chip.isNeeds)
          loops: Animation.Infinite
          PropertyAction { value: 1 }
          PauseAnimation { duration: chip.isNeeds ? 350 : 500 }
          PropertyAction { value: 0 }
          PauseAnimation { duration: chip.isNeeds ? 350 : 500 }
        }
      }
      Caption {
        id: chipText
        text: chip.isWorking ? "Working" : (chip.isNeeds ? "Needs you" : "Idle")
        color: chip.isWorking ? board.well : (chip.isNeeds ? board.alert : board.dim)
        font.letterSpacing: 1.0
        font.pixelSize: Math.max(7, board.captionSize - 1)
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: 4
    visible: board.rows.length > 0

    Item {
      width: parent.width
      height: headLeft.implicitHeight
      Row {
        id: headLeft
        spacing: 6
        Rectangle { width: 5; height: 5; anchors.verticalCenter: parent.verticalCenter; color: board.accent }
        Caption { text: "Arrivals"; color: board.foreground; font.bold: true }
      }
      Caption {
        anchors.right: parent.right
        text: board.rows.length + (board.rows.length === 1 ? " agent" : " agents") + " · " + board.working + " working"
          + (board.needing > 0 ? " · " + board.needing + " waiting" : "")
      }
    }

    Item {
      width: parent.width
      height: colHead.implicitHeight + 3
      Row {
        id: colHead
        width: parent.width
        spacing: 6
        Caption { width: board.agentWidth; text: "Agent" }
        Caption { width: board.projectWidth; text: "Project" }
        Caption { width: board.nowWidth; text: "Now" }
        Caption { width: board.elapsedWidth; text: "Elapsed" }
        Caption { text: "Status" }
      }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: board.line }
    }

    Repeater {
      model: board.shown
      delegate: Item {
        id: rowItem
        required property int index
        readonly property var row: board.rows[index]
        readonly property bool hovered: hover.hovered && board.held
        readonly property string detailText: (row.tools.length ? "Last: " + board.collapseTools(row.tools) : "No tool calls seen")
          + (row.title !== "" ? "  ·  “" + row.title + "”" : "")
          + (String(row.address || "") !== "" ? "  ·  click to focus" : "")
        width: column.width
        height: board.rowHeight

        onHoveredChanged: {
          if (hovered) board.hoveredDetail = detailText
          else if (board.hoveredDetail === detailText) board.hoveredDetail = ""
        }

        Rectangle { anchors.fill: parent; color: board.accent; opacity: rowItem.hovered ? 0.08 : 0 }

        HoverHandler { id: hover }
        TapHandler {
          enabled: board.held && String(rowItem.row.address || "") !== ""
          onTapped: board.focusRequested(String(rowItem.row.address))
        }

        Row {
          id: cells
          width: parent.width
          height: board.rowHeight
          spacing: 6
          Text {
            width: board.agentWidth
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: rowItem.row.agentLabel
            color: board.foreground
            font.family: board.fontFamily
            font.pixelSize: board.bodySize
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: board.projectWidth
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: rowItem.row.project + (rowItem.row.branch !== "" ? " · " + rowItem.row.branch : "")
            color: board.dim
            font.family: board.fontFamily
            font.pixelSize: board.bodySize
            elide: Text.ElideRight
          }
          Item {
            width: board.nowWidth
            height: board.cell
            anchors.verticalCenter: parent.verticalCenter
            FlipBoard {
              value: String(rowItem.row.now).padEnd(11, " ").slice(0, 11)
              style: board.style
              glyphSet: "alnum"
              tileWidth: board.tileW
              tileHeight: board.cell
              gap: 1
              colonWidth: board.tileW
              foreground: board.foreground
              accent: board.accent
              dim: board.dim
              line: board.line
              well: board.well
              fontFamily: board.fontFamily
              animated: board.animated
            }
          }
          Item {
            width: board.elapsedWidth
            height: board.cell
            anchors.verticalCenter: parent.verticalCenter
            FlipBoard {
              value: String(rowItem.row.elapsed).padStart(5, " ").slice(-5)
              style: board.style
              glyphSet: "alnum"
              tileWidth: board.tileW
              tileHeight: board.cell
              gap: 1
              colonWidth: Math.round(board.tileW * 0.5)
              foreground: board.foreground
              accent: board.accent
              dim: board.dim
              line: board.line
              well: board.well
              fontFamily: board.fontFamily
              animated: board.animated
            }
          }
          Chip { anchors.verticalCenter: parent.verticalCenter; status: rowItem.row.status }
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: board.line }
      }
    }

    Caption {
      visible: board.hidden > 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "+" + board.hidden + " more"
    }
  }
}
