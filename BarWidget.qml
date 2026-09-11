import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

BarWidget {
  id: root
  moduleName: "io.github.wbuf81.idle-screencounter"
  readonly property var counter: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool counterEnabled: setting("enabled", true) === true
  readonly property string displayText: counter && counter.warningVisible ? counter.format(counter.remainingSeconds) : "󰒲"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function updateSettings(next) {
    var normalized = Logic.normalizedSettings(next, root.moduleName)
    root.settings = normalized
    if (!root.bar || !root.bar.shell) return
    var shell = root.bar.shell
    // Keep Omarchy's actual idle service in lockstep with the controls. The
    // warning remains this plugin's own setting; screensaver and lock are
    // shared system deadlines and therefore live under top-level `idle`.
    // Only a shell that hands us the whole config can do that. Newer shells
    // give third-party widgets a scoped API whose mutateShellConfig exists
    // but returns false, so fall through to the entry-only write there.
    // Older shells return nothing from a successful mutation.
    var persisted = false
    if (typeof shell.mutateShellConfig === "function") {
      persisted = shell.mutateShellConfig(function(config) {
        if (!config || !config.bar || !config.bar.layout) return
        var sections = ["left", "center", "right"]
        for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
          var entries = config.bar.layout[sections[sectionIndex]] || []
          for (var index = 0; index < entries.length; index++) {
            if (entries[index] && entries[index].id === root.moduleName) entries[index] = normalized
          }
        }
        if (!config.idle) config.idle = ({})
        config.idle.screensaver = Number(normalized.screensaverSeconds)
        config.idle.lock = Number(normalized.lockSeconds)
      }) !== false
    }
    if (!persisted && typeof shell.updateEntryInline === "function") {
      shell.updateEntryInline(root.moduleName, normalized)
    }
  }

  function toggleEnabled() {
    var next = Object.assign({}, root.settings, { enabled: !root.counterEnabled })
    updateSettings(next)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.hostWidget = root
    target.anchorItem = button
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  IpcHandler {
    target: "io.github.wbuf81.idle-screencounter"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function enable() { if (!root.counterEnabled) root.toggleEnabled() }
    function disable() { if (root.counterEnabled) root.toggleEnabled() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    slotSize: root.counter && root.counter.warningVisible && !root.vertical ? Style.bar.iconSlot * 2.4 : Style.bar.iconSlot
    active: root.counter && root.counter.warningVisible
    tooltipText: root.counterEnabled ? "Idle Screen Counter" : "Idle Screen Counter (off)"
    dimmed: !root.counterEnabled
    onPressed: function(button) {
      if (button === Qt.RightButton) root.toggleEnabled()
      else root.toggle()
    }
  }
}
