import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
  id: root
  property var pluginService: null
  property string pluginId: "stash"

  property bool open: false
  property bool terminalTarget: false

  History {
    id: history
    active: root.open
  }

  function focusedScreen() {
    const name = NiriService.currentOutput;
    return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
  }

  function show() {
    terminalTarget = history.terminalFocused();  // decide before our overlay takes focus
    win.screen = focusedScreen();
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

  PanelWindow {
    id: win
    visible: root.open
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "dms-stash"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.hide()
    }

    StashPanel {
      id: panel
      anchors.centerIn: parent
      history: history
      onCloseRequested: root.hide()
      onPasteRequested: (entry, textOnly) => root.paste(entry, textOnly)
      MouseArea { anchors.fill: parent; z: -1 }  // swallow clicks so the backdrop doesn't close
    }
  }
}
