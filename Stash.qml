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
  property bool terminalTarget: false
  property bool closeOnFocusLoss: setting("closeOnFocusLoss", false)
  property bool hadFocus: false  // showing the window emits a spurious inactive change; ignore until focused once

  function setting(key, fallback) {
    return pluginService ? pluginService.loadPluginData("stash", key, fallback) : fallback;
  }

  // Settings page writes through PluginService; re-read on change.
  Connections {
    target: root.pluginService
    function onPluginDataChanged(id) {
      if (id !== "stash") return;
      root.closeOnFocusLoss = root.setting("closeOnFocusLoss", false);
      externalEditor.command = root.setting("editorCommand", "");
    }
  }

  History {
    id: history
    active: root.open
  }

  Store {
    id: store
  }

  ExternalEditor {
    id: externalEditor
    command: root.setting("editorCommand", "")
  }

  function show() {
    terminalTarget = history.terminalFocused();  // decide before our window takes focus
    if (history.dirty)
      history.refresh();
    open = true;
    hadFocus = false;
    win.visible = true;
    panel.reset();
  }

  function hide() {
    open = false;
    win.visible = false;
    history.commitDelete();
    store.lastDeleted = null;
  }

  function toggle() {
    open ? hide() : show();
  }

  // Global slot paste (niri bind → IPC). Assigned slot → that item; otherwise history item n.
  function pasteSlot(n) {
    if (open)
      hide();
    const terminal = history.terminalFocused();
    const item = store.slotItem(n);
    if (item)
      history.pasteText(item.preview, terminal, null, 250);
    else
      history.nth(n, e => { if (e) history.paste(e, false, terminal, null, 250); });
  }

  // Cycle copy: each press copies the next older entry. Copying moves an entry to the top, so walk a
  // snapshot taken on the first press; the session ends 5 s after the last press.
  property var cycleList: []
  property int cycleIndex: 0
  property int cyclePending: 0
  property bool cycleFetching: false
  Timer {
    id: cycleReset
    interval: 5000
    onTriggered: root.cycleList = []
  }

  function cycleCopy() {
    cycleReset.restart();
    if (cycleList.length)
      return _cycleStep();
    cyclePending++;
    if (cycleFetching)
      return;
    cycleFetching = true;
    DMSService.sendRequest("clipboard.search", { "limit": 50, "offset": 0 }, r => {
      root.cycleFetching = false;
      root.cycleList = ((r.result || {}).entries || []).map(e => ({ id: e.id, preview: e.preview, isImage: e.isImage }));
      root.cycleIndex = 0;
      const n = root.cyclePending;
      root.cyclePending = 0;
      for (let i = 0; i < n && root.cycleList.length > 1; i++)
        root._cycleStep();
    });
  }

  function _cycleStep() {
    if (cycleList.length < 2)
      return;
    cycleIndex = (cycleIndex + 1) % cycleList.length;  // wraps back to the original clipboard
    const e = cycleList[cycleIndex];
    const n = cycleIndex + 1;
    DMSService.sendRequest("clipboard.copyEntry", { "id": e.id }, r => {
      if (r.error)
        ToastService.showError("Stash: " + r.error);
      else
        ToastService.showInfo("Clipboard #" + n + (e.isImage ? " (image)" : ": " + e.preview.slice(0, 60)));
    });
  }

  function paste(entry, textOnly) {
    if (entry.collection)
      history.pasteText(entry.preview, terminalTarget, () => hide());
    else
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
    function pasteSlot(n: int): string {
      if (n < 1 || n > 9) return "slot must be 1-9";
      root.pasteSlot(n);
      return "slot " + n;
    }
    function cycle(): string {
      root.cycleCopy();
      return "ok";
    }
    function slots(): string {
      const out = [];
      for (let n = 1; n <= 9; n++) {
        const it = store.slotItem(n);
        out.push(n + ": " + (it ? (it.title || it.preview.split("\n")[0]).slice(0, 40) : "history #" + n));
      }
      return out.join("\n");
    }
    function openTab(name: string): string {
      root.show();
      const i = panel.tabs.findIndex(t => t.label.toLowerCase() === name.toLowerCase() || t.id === name);
      if (i < 0) return "no tab " + name;
      panel.tabIndex = i;
      return "opened " + panel.tabs[i].label;
    }
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
      store: store
      onExternalRequested: (text, ext, onSave) => externalEditor.open(text, ext, onSave)
      onCloseRequested: root.hide()
      onPasteRequested: (entry, textOnly) => root.paste(entry, textOnly)
      // CopyQ-like: close when focus moves to another window
      Window.onActiveChanged: {
        if (Window.active) root.hadFocus = true;
        else if (root.closeOnFocusLoss && root.hadFocus && root.open) root.hide();
      }
    }
  }
}
