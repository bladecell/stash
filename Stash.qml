import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

Item {
  id: root
  property var pluginService: null
  property string pluginId: "stash"

  property bool open: false
  onOpenChanged: win.visible = open
  property bool terminalTarget: false

  History {
    id: history
    active: root.open
  }

  function show() {
    terminalTarget = history.terminalFocused();  // decide before our window takes focus
    if (history.dirty)
      history.refresh();
    open = true;
    panel.reset();
  }

  function hide() {
    open = false;
    history.commitDelete();
  }

  function toggle() {
    open ? hide() : show();
  }

  function paste(entry, textOnly) {
    history.paste(entry, textOnly, terminalTarget, () => hide());
  }

  // Preload history once DMS is up so the first open is instant.
  Connections {
    target: DMSService
    function onIsConnectedChanged() {
      if (DMSService.isConnected)
        history.refresh();
    }
  }
  Component.onCompleted: if (DMSService.isConnected) history.refresh()

  IpcHandler {
    target: "stash"
    function toggle(): string { root.toggle(); return root.open ? "opened" : "closed"; }
    function open(): string { root.show(); return "opened"; }
    function close(): string { root.hide(); return "closed"; }
  }

  // Regular xdg toplevel so niri can move/resize it; the "org.quickshell" floating rule applies.
  DFloatingWindow {
    id: win
    title: "Stash"
    surfaceColor: "transparent"
    visible: false
    onVisibleChanged: if (!visible && root.open) root.hide()  // closed by the compositor (e.g. Mod+Q)
    implicitWidth: root.pluginService ? root.pluginService.loadPluginData("stash", "windowWidth", 560) : 560
    implicitHeight: root.pluginService ? root.pluginService.loadPluginData("stash", "windowHeight", 480) : 480
    minimumSize: Qt.size(380, 300)

    onWidthChanged: saveSize.restart()
    onHeightChanged: saveSize.restart()
    Timer {
      id: saveSize
      interval: 800
      onTriggered: if (root.open && root.pluginService) {
        root.pluginService.savePluginData("stash", "windowWidth", Math.round(win.width));
        root.pluginService.savePluginData("stash", "windowHeight", Math.round(win.height));
      }
    }

    StashPanel {
      id: panel
      anchors.fill: parent
      history: history
      onCloseRequested: root.hide()
      onPasteRequested: (entry, textOnly) => root.paste(entry, textOnly)
      // CopyQ-like: close when focus moves to another window
      Window.onActiveChanged: if (!Window.active && root.open) root.hide()
    }
  }
}
