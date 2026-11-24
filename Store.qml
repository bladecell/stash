import QtQuick
import QtQuick.LocalStorage
import Quickshell
import Quickshell.Io
import "Classify.js" as C

// Collections (Notes, Snippets, user tabs) in SQLite via Qt LocalStorage, all in-process.
QtObject {
  id: root

  property var db: null
  property var tabs: []        // [{id, name, icon, pos}]
  property var items: ({})     // tabId → [row], newest first (row shape matches history entries)
  property int version: 0      // bumped on every change so filters re-run
  property var lastDeleted: null

  function _open() {
    db = LocalStorage.openDatabaseSync("stash", "", "Stash collections", 64 * 1024 * 1024);
    db.transaction(tx => {
      tx.executeSql("CREATE TABLE IF NOT EXISTS tabs (id INTEGER PRIMARY KEY, name TEXT NOT NULL, icon TEXT, pos INTEGER, encrypted INTEGER DEFAULT 0)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, tab_id INTEGER NOT NULL, title TEXT DEFAULT '', content TEXT NOT NULL DEFAULT '', lang TEXT DEFAULT '', created INTEGER, updated INTEGER)");
      tx.executeSql("CREATE INDEX IF NOT EXISTS items_tab ON items(tab_id, updated)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)");
      if (tx.executeSql("SELECT COUNT(*) AS n FROM tabs").rows.item(0).n === 0) {
        tx.executeSql("INSERT INTO tabs (name, icon, pos) VALUES ('Notes', 'note-sticky', 0)");
        tx.executeSql("INSERT INTO tabs (name, icon, pos) VALUES ('Snippets', 'code', 1)");
      }
    });
    _load();
  }

  function _row(r, tabName) {

    return {
      id: "db" + r.id, dbId: r.id, tabId: r.tab_id, collection: true,
      title: r.title || "", preview: r.content, lang: r.lang || "", size: r.content.length,
      timestamp: new Date(r.updated).toISOString(),
      kind: tabName === "Notes" ? "note" : tabName === "Snippets" ? "code" : C.kind({ preview: r.content.slice(0, 200) })
    };
  }

  function _load() {
    const t = [], it = {};
    db.readTransaction(tx => {
      const tr = tx.executeSql("SELECT * FROM tabs ORDER BY pos, id").rows;
      for (let i = 0; i < tr.length; i++) {
        const tab = tr.item(i);
        t.push({ id: tab.id, name: tab.name, icon: tab.icon || "folder", pos: tab.pos });
        it[tab.id] = [];
      }
      const ir = tx.executeSql("SELECT * FROM items ORDER BY updated DESC").rows;
      const names = {};
      t.forEach(x => names[x.id] = x.name);
      for (let i = 0; i < ir.length; i++) {
        const r = ir.item(i);
        if (it[r.tab_id])
          it[r.tab_id].push(_row(r, names[r.tab_id]));
      }
    });
    tabs = t;
    items = it;
    version++;
  }

  function tabById(id) {
    return tabs.find(t => t.id === id) || null;
  }

  function meta(key) {
    let v = null;
    db.readTransaction(tx => {
      const r = tx.executeSql("SELECT value FROM meta WHERE key = ?", [key]).rows;
      if (r.length) v = r.item(0).value;
    });
    return v;
  }

  function setMeta(key, value) {
    db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [key, String(value)]));
  }

  function filtered(tabId, query) {
    version;  // dependency
    const q = query.trim().toLowerCase();
    const list = items[tabId] || [];
    return q ? list.filter(r => r.preview.toLowerCase().includes(q) || r.title.toLowerCase().includes(q)) : list;
  }

  function addTab(name, icon) {
    let id = 0;
    db.transaction(tx => {
      const pos = tx.executeSql("SELECT COALESCE(MAX(pos), 0) + 1 AS p FROM tabs").rows.item(0).p;
      id = parseInt(tx.executeSql("INSERT INTO tabs (name, icon, pos) VALUES (?, ?, ?)", [name, icon || "folder", pos]).insertId);
    });
    _load();
    return id;
  }

  function renameTab(id, name) {
    db.transaction(tx => tx.executeSql("UPDATE tabs SET name = ? WHERE id = ?", [name, id]));
    _load();
  }

  function deleteTab(id) {
    db.transaction(tx => {
      tx.executeSql("DELETE FROM items WHERE tab_id = ?", [id]);
      tx.executeSql("DELETE FROM tabs WHERE id = ?", [id]);
    });
    _load();
  }

  function addItem(tabId, content, title, lang) {
    const now = Date.now();
    let id = 0;
    db.transaction(tx => {
      id = parseInt(tx.executeSql("INSERT INTO items (tab_id, title, content, lang, created, updated) VALUES (?, ?, ?, ?, ?, ?)", [tabId, title || "", content || "", lang || "", now, now]).insertId);
    });
    _load();
    return id;
  }

  function updateItem(dbId, fields) {
    const sets = [], args = [];
    for (const k of ["title", "content", "lang", "tab_id"]) {
      if (fields[k] !== undefined) {
        sets.push(k + " = ?");
        args.push(fields[k]);
      }
    }
    sets.push("updated = ?");
    args.push(Date.now(), dbId);
    db.transaction(tx => tx.executeSql("UPDATE items SET " + sets.join(", ") + " WHERE id = ?", args));
    _load();
  }

  function deleteItem(row) {
    let saved = null;
    db.transaction(tx => {
      const r = tx.executeSql("SELECT * FROM items WHERE id = ?", [row.dbId]).rows;
      if (r.length) saved = Object.assign({}, r.item(0));
      tx.executeSql("DELETE FROM items WHERE id = ?", [row.dbId]);
    });
    lastDeleted = saved;
    _load();
  }

  function undoDelete() {
    const r = lastDeleted;
    if (!r)
      return false;
    db.transaction(tx => tx.executeSql("INSERT INTO items (id, tab_id, title, content, lang, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?)", [r.id, r.tab_id, r.title, r.content, r.lang, r.created, r.updated]));
    lastDeleted = null;
    _load();
    return true;
  }

  // One-time import of ClipBoard+ (dux-copyq fork) notecards and pins.
  property Process _import: Process {
    property string dir: Quickshell.env("HOME") + "/.config/dms-dux-copyq/data"
    command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; printf '{\"notes\":['; s=; for f in notecards/*.json; do [ -f \"$f\" ] || continue; printf '%s' \"$s\"; cat \"$f\"; s=,; done; printf '],\"pins\":'; cat pinned.json 2>/dev/null || printf '{}'; printf '}'", "sh", dir]
    stdout: StdioCollector {
      onStreamFinished: {
        let data = null;
        try { data = JSON.parse(text); } catch (e) { console.warn("Stash: import parse failed", e); return; }
        const notesTab = root.tabs.find(t => t.name === "Notes");
        let n = 0;
        root.db.transaction(tx => {
          for (const note of data.notes || []) {
            if (!note.content && !note.title) continue;
            const ts = Date.parse(note.lastModified || note.createdAt) || Date.now();
            tx.executeSql("INSERT INTO items (tab_id, title, content, lang, created, updated) VALUES (?, ?, ?, '', ?, ?)", [notesTab.id, note.title || "", note.content || "", Date.parse(note.createdAt) || ts, ts]);
            n++;
          }
          const pins = (data.pins && data.pins.items) || [];
          if (pins.length) {
            const pos = tx.executeSql("SELECT COALESCE(MAX(pos), 0) + 1 AS p FROM tabs").rows.item(0).p;
            const tabId = parseInt(tx.executeSql("INSERT INTO tabs (name, icon, pos) VALUES ('Pinned (imported)', 'thumbtack', ?)", [pos]).insertId);
            for (const p of pins) {
              const content = p.content || p.text || p.preview || "";
              if (!content) continue;
              tx.executeSql("INSERT INTO items (tab_id, content, created, updated) VALUES (?, ?, ?, ?)", [tabId, content, Date.now(), Date.now()]);
              n++;
            }
          }
          tx.executeSql("INSERT OR REPLACE INTO meta (key, value) VALUES ('imported_clipboardplus', ?)", [String(n)]);
        });
        root._load();
        if (n)
          console.info("Stash: imported", n, "items from ClipBoard+");
      }
    }
  }

  Component.onCompleted: {
    _open();
    if (meta("imported_clipboardplus") === null)
      _import.running = true;
  }
}
