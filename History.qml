import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "Classify.js" as C

// History from the DMS clipboard daemon, classified once per entry and filtered in-process.
QtObject {
  id: root

  property int limit: 2000
  property var entries: []          // [{id, hash, kind, preview, ...}], newest first
  property bool active: false       // window open → keep in sync
  property bool dirty: true
  property var hidden: ({})         // id → true while a delete is pending undo

  // caches: full text for long entries, data URLs for images
  property var textCache: ({})
  property var imageCache: ({})
  property var imageOrder: []
  property int inflight: 0
  property var queue: []

  readonly property bool available: DMSService.isConnected

  property var _kinds: ({})
  property int _seq: 0

  readonly property Connections _dms: Connections {
    target: DMSService
    function onClipboardStateUpdate(data) {
      root.dirty = true;
      if (root.active)
        root.refresh();
    }
  }

  function refresh() {
    if (!available)
      return;
    const seq = ++_seq;
    DMSService.sendRequest("clipboard.search", { "limit": limit, "offset": 0 }, response => {
      if (seq !== root._seq || response.error)
        return;
      const list = (response.result || {}).entries || [];
      const kinds = root._kinds;
      for (const e of list) {
        const key = e.id + ":" + e.hash;
        e.kind = kinds[key] || (kinds[key] = C.kind(e));
      }
      root.entries = list;
      root.dirty = false;
    });
  }

  function filtered(tab, query) {
    const q = query.trim().toLowerCase();
    const out = [];
    for (const e of entries) {
      if (hidden[e.id])
        continue;
      if (tab === "pinned" ? !e.pinned : tab !== "all" && e.kind !== tab)
        continue;
      if (q && !(e.preview || "").toLowerCase().includes(q) && !(textCache[e.id] || "").toLowerCase().includes(q))
        continue;
      out.push(e);
    }
    return out;
  }

  // Lazy loads, at most 3 in flight; callbacks fire with cached data when it arrives.
  function _pump() {
    while (inflight < 3 && queue.length) {
      const job = queue.shift();
      inflight++;
      DMSService.sendRequest("clipboard.getEntry", { "id": job.id }, response => {
        inflight--;
        const r = response.result;
        if (r && r.data !== undefined)
          job.done(r);
        _pump();
      });
    }
  }

  function fullText(e, cb) {
    if (textCache[e.id] !== undefined)
      return textCache[e.id];
    if (!queue.some(j => j.id === e.id))
      queue.push({ id: e.id, done: r => {
        const t = r.data.length > 600 ? r.data.slice(0, 600) : r.data;
        root.textCache[e.id] = t;  // mutated in place: no rebinding of every filter
        cb && cb(t);
      } });
    _pump();
    return null;
  }

  function image(e, cb) {
    if (imageCache[e.id])
      return imageCache[e.id];
    if (!queue.some(j => j.id === e.id))
      queue.push({ id: e.id, done: r => {
        const url = r.data.startsWith("data:") ? r.data : "data:" + e.mimeType + ";base64," + r.data;
        root.imageCache[e.id] = url;
        root.imageOrder.push(e.id);
        while (root.imageOrder.length > 60)
          delete root.imageCache[root.imageOrder.shift()];
        cb && cb(url);
      } });
    _pump();
    return "";
  }

  function _after(ok) {
    return response => {
      if (response.error)
        ToastService.showError("Stash: " + response.error);
      else
        ok && ok();
    };
  }

  function copy(e, textOnly, done) {
    DMSService.sendRequest("clipboard.copyEntry", { "id": e.id, "textOnly": !!textOnly }, _after(done));
  }

  // delay: ms before the paste keystroke (longer for global binds, so held modifiers are released)
  function paste(e, textOnly, terminal, beforePaste, delay) {
    DMSService.sendRequest("clipboard.copyEntry", { "id": e.id, "textOnly": !!textOnly }, _after(() => {
      beforePaste && beforePaste();
      _schedulePaste(terminal, delay);
    }));
  }

  function _schedulePaste(terminal, delay) {
    pasteTimer.shift = terminal;
    pasteTimer.interval = delay || 120;
    pasteTimer.restart();
  }

  property Timer pasteTimer: Timer {
    property bool shift: false
    interval: 120
    onTriggered: DMSService.sendRequest("clipboard.sendPaste", { "shift": shift }, root._after(null))
  }

  // Untruncated text for editing (fullText caps at 600 chars for previews).
  function loadFull(e, cb) {
    DMSService.sendRequest("clipboard.getEntry", { "id": e.id }, response => {
      const r = response.result;
      if (r && r.data !== undefined)
        cb(r.data);
    });
  }

  // Rewrites a history entry; DMS replaces it with a new newest entry (new id), passed to done.
  function edit(e, text, done) {
    DMSService.sendRequest("clipboard.editEntry", { "id": e.id, "text": text }, _after(() => {
      delete root.textCache[e.id];
      refresh();
      if (done)
        DMSService.sendRequest("clipboard.search", { "limit": 1, "offset": 0 }, r => {
          const top = ((r.result || {}).entries || [])[0];
          if (top) done(top);
        });
    }));
  }

  function copyText(text, done) {
    DMSService.sendRequest("clipboard.copy", { "text": text }, _after(done));
  }

  function pasteText(text, terminal, beforePaste, delay) {
    copyText(text, () => {
      beforePaste && beforePaste();
      _schedulePaste(terminal, delay);
    });
  }

  // Newest-first history entry n (1-based), fetched fresh so it is right even while the window is closed.
  function nth(n, cb) {
    DMSService.sendRequest("clipboard.search", { "limit": n, "offset": 0 }, r => {
      const e = ((r.result || {}).entries || [])[n - 1];
      cb(e || null);
    });
  }

  function setPinned(e, pinned) {
    DMSService.sendRequest(pinned ? "clipboard.pinEntry" : "clipboard.unpinEntry", { "id": e.id }, _after(() => refresh()));
  }

  // Soft delete: hidden now, removed from DMS when committed (timeout, next delete, or window close).
  property var pendingDelete: null
  property Timer deleteTimer: Timer {
    interval: 6000
    onTriggered: root.commitDelete()
  }

  function softDelete(e) {
    commitDelete();
    const h = Object.assign({}, hidden);
    h[e.id] = true;
    hidden = h;
    pendingDelete = e;
    deleteTimer.restart();
  }

  function undoDelete() {
    if (!pendingDelete)
      return false;
    const h = Object.assign({}, hidden);
    delete h[pendingDelete.id];
    hidden = h;
    pendingDelete = null;
    deleteTimer.stop();
    return true;
  }

  function commitDelete() {
    const e = pendingDelete;
    if (!e)
      return;
    pendingDelete = null;
    deleteTimer.stop();
    DMSService.sendRequest("clipboard.deleteEntry", { "id": e.id }, response => {
      const h = Object.assign({}, root.hidden);
      delete h[e.id];
      root.hidden = h;
      root.entries = root.entries.filter(x => x.id !== e.id);
    });
  }

  function terminalFocused() {
    const appId = (ToplevelManager.activeToplevel?.appId ?? "").toLowerCase();
    return !!appId && (ClipboardService.terminalAppIds.includes(appId) || appId.endsWith("term") || appId.includes("terminal"));
  }
}
