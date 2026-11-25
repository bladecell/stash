import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "Commands.js" as Commands
import "Classify.js" as C

Item {
  id: root
  property var pluginService: null
  property string pluginId: "stash"

  property bool open: false
  property bool terminalTarget: false
  property bool closeOnFocusLoss: setting("closeOnFocusLoss", false)
  property var commands: setting("commands", Commands.defaults)
  property int autoLockMinutes: setting("autoLockMinutes", 10)
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
      root.commands = root.setting("commands", Commands.defaults);
      root.autoLockMinutes = root.setting("autoLockMinutes", 10);
      externalEditor.command = root.setting("editorCommand", "");
    }
  }

  History {
    id: history
    active: root.open
  }

  Store {
    id: store
    onLocked: externalEditor.forgetSecrets()
    onUnlockedChanged: if (unlocked) autoLock.restart()
  }

  // Lock the vault after N idle minutes (not while Stash is open) and whenever the session locks.
  Timer {
    id: autoLock
    interval: Math.max(1, root.autoLockMinutes) * 60000
    onTriggered: {
      if (root.autoLockMinutes <= 0) return;
      if (root.open) restart();
      else store.lock();
    }
  }
  Connections {
    target: SessionService
    function onSessionLocked() { store.lock(); }
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
    if (store.unlocked) autoLock.restart();
    panel.reset();
  }

  function hide() {
    open = false;
    win.visible = false;
    if (store.unlocked) autoLock.restart();
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
    DMSService.sendRequest("clipboard.copyEntry", { "id": e.id }, r => {
      if (r.error)
        ToastService.showError("Stash: " + r.error);
      else
        cycleOverlay.flash();
    });
  }

  CycleOverlay {
    id: cycleOverlay
    entries: root.cycleList
    index: root.cycleIndex
  }

  // Ctrl+Shift+V: run the item through every "On paste" command for its kind (in list order), paste the result.
  function pasteProcessed(e) {
    const terminal = terminalTarget;
    hide();
    processAndPaste(e, terminal, 0);
  }

  // Global clean paste (niri bind → IPC): the current clipboard through the On paste commands.
  function pasteCleanClipboard() {
    if (open)
      hide();
    const terminal = history.terminalFocused();
    DMSService.sendRequest("clipboard.search", { "limit": 1, "offset": 0 }, r => {
      const e = ((r.result || {}).entries || [])[0];
      if (!e) return;
      e.kind = C.kind(e);
      root.processAndPaste(e, terminal, 250);
    });
  }

  // delay: ms before the paste keystroke (longer for global binds, so held modifiers are released)
  function processAndPaste(e, terminal, delay) {
    const todo = (commands || []).filter(c => Commands.onPaste(c) && Commands.appliesTo(c, e.kind));
    if (e.isImage || !todo.length) {
      if (e.collection) history.pasteText(e.preview || "", terminal, null, delay, e.secret);
      else history.paste(e, true, terminal, null, delay);
      return;
    }
    let i = 0;
    const step = text => {
      if (i >= todo.length)
        return history.pasteText(text, terminal, null, delay, e.secret);
      const c = todo[i++];
      runner.exec(["timeout", "10", "sh", "-c", c.command], text, (out, err, code) => {
        if (code !== 0) {
          ToastService.showError("Stash: " + c.name + " failed", (err || out).trim().split("\n").slice(-3).join("\n") || "exit " + code);
          return step(text);
        }
        step(out.replace(/\n$/, ""));
      }, { "STASH_TEXT": text, "STASH_KIND": e.kind || "", "STASH_DIR": runner.dir });
    };
    if (e.collection) step(e.preview || "");
    else history.loadFull(e, step);
  }

  // ---- custom commands ----
  Runner {
    id: runner
    onFinished: (job, out, err, code) => root.commandDone(job, out, err, code)
  }

  function runCommand(e, cmd) {
    const out = cmd.output || "copy";
    if (out === "paste" || out === "none")
      hide();
    else
      panel.notify("Running " + cmd.name + "…");
    const go = text => runner.run({ cmd: cmd, entry: e, terminal: terminalTarget }, text, e.kind);
    if (e.collection || e.size <= 100)
      go(e.preview || "");
    else
      history.loadFull(e, go);
  }

  function commandDone(job, out, err, code) {
    const name = job.cmd.name;
    if (code !== 0) {
      const msg = code === 124 ? "timed out after 20 s" : (err || out).trim().split("\n").slice(-3).join("\n") || "exit " + code;
      ToastService.showError("Stash: " + name + " failed", msg);
      panel.notify(name + " failed");
      return;
    }
    out = out.replace(/\n$/, "");
    switch (job.cmd.output || "copy") {
    case "copy":
      history.copyText(out, () => panel.notify(name + ": output copied"), job.entry.secret);
      break;
    case "paste":
      history.pasteText(out, job.terminal, null, 0, job.entry.secret);
      break;
    case "replace":
      if (job.entry.collection)
        store.updateItem(job.entry.dbId, { content: out });
      else
        history.edit(job.entry, out);
      panel.notify(name + ": item updated");
      break;
    }
  }

  function paste(entry, textOnly) {
    if (entry.collection)
      history.pasteText(entry.preview, terminalTarget, () => hide(), 0, entry.secret);
    else
      history.paste(entry, textOnly, terminalTarget, () => hide());
  }

  // Preload history once DMS is up so the first open is instant.
  Connections {
    target: DMSService
    function onIsConnectedChanged() {
      if (DMSService.isConnected) {
        history.refresh();
      }
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
    function pasteClean(): string {
      root.pasteCleanClipboard();
      return "ok";
    }
    function cycle(): string {
      root.cycleCopy();
      return "ok";
    }
    function lock(): string { store.lock(); return "locked"; }
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
      commands: root.commands
      onCommandRequested: (entry, cmd) => root.runCommand(entry, cmd)
      onExternalRequested: (text, ext, onSave, secret) => externalEditor.open(text, ext, onSave, secret)
      onCloseRequested: root.hide()
      onPasteRequested: (entry, textOnly) => root.paste(entry, textOnly)
      onPasteProcessedRequested: entry => root.pasteProcessed(entry)
      // CopyQ-like: close when focus moves to another window
      Window.onActiveChanged: {
        if (Window.active) root.hadFocus = true;
        else if (root.closeOnFocusLoss && root.hadFocus && root.open) root.hide();
      }
    }
  }
}
