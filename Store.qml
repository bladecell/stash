import QtQuick
import QtQuick.LocalStorage
import Quickshell
import Quickshell.Io
import qs.Services
import "Classify.js" as C

// Collections (Notes, Snippets, user tabs) in SQLite via Qt LocalStorage, all in-process.
QtObject {
  id: root

  property var db: null
  property var tabs: []        // [{id, name, icon, pos}]
  property var items: ({})     // tabId → [row], newest first (row shape matches history entries)
  property int version: 0      // bumped on every change so filters re-run
  property var lastDeleted: null
  property var slots: ({})     // slot number → dbId (unassigned slots paste history item N)

  // Encrypted tabs: each tab's items are one gpg-encrypted JSON block in `vault`. Decrypted items
  // live only in memory while unlocked; vault item ids are negative.
  property string passphrase: ""
  readonly property bool unlocked: passphrase !== ""
  property bool hasMaster: false
  property var vault: ({})      // tabId → [{id, tab_id, title, content, lang, created, updated}]
  property var _latest: ({})    // tabId → JSON waiting to be encrypted
  property var _saving: ({})
  property int _vseq: 0
  signal locked
  readonly property string _check: "stash-vault-v1"
  readonly property var _gpgBase: ["gpg", "--batch", "--quiet", "--yes", "--pinentry-mode", "loopback", "--passphrase-fd", "0", "--no-symkey-cache"]
  property Runner _gpg: Runner {}

  function _open() {
    db = LocalStorage.openDatabaseSync("stash", "", "Stash collections", 64 * 1024 * 1024);
    db.transaction(tx => {
      tx.executeSql("PRAGMA secure_delete = ON");  // deleted plaintext is overwritten, not left in free pages
      tx.executeSql("CREATE TABLE IF NOT EXISTS vault (tab_id INTEGER PRIMARY KEY, blob TEXT NOT NULL)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS tabs (id INTEGER PRIMARY KEY, name TEXT NOT NULL, icon TEXT, pos INTEGER, encrypted INTEGER DEFAULT 0)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, tab_id INTEGER NOT NULL, title TEXT DEFAULT '', content TEXT NOT NULL DEFAULT '', lang TEXT DEFAULT '', created INTEGER, updated INTEGER)");
      tx.executeSql("CREATE INDEX IF NOT EXISTS items_tab ON items(tab_id, updated)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS slots (n INTEGER PRIMARY KEY, item_id INTEGER NOT NULL)");
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
      timestamp: new Date(r.updated).toISOString(), slot: 0, secret: r.id < 0,
      kind: tabName === "Notes" ? "note" : tabName === "Snippets" ? "code" : C.kind({ preview: r.content.slice(0, 200) })
    };
  }

  function _load() {
    const t = [], it = {}, sl = {}, byId = {};
    db.readTransaction(tx => {
      const tr = tx.executeSql("SELECT * FROM tabs ORDER BY pos, id").rows;
      for (let i = 0; i < tr.length; i++) {
        const tab = tr.item(i);
        const enc = !!tab.encrypted;
        t.push({ id: tab.id, name: tab.name, icon: tab.icon || "folder", pos: tab.pos, encrypted: enc, locked: enc && !vault[tab.id] });
        it[tab.id] = enc && vault[tab.id] ? vault[tab.id].slice().sort((a, b) => b.updated - a.updated).map(v => _row(v, tab.name)) : [];
      }
      const ir = tx.executeSql("SELECT * FROM items ORDER BY updated DESC").rows;
      const names = {};
      t.forEach(x => names[x.id] = x.name);
      for (let i = 0; i < ir.length; i++) {
        const r = ir.item(i);
        if (it[r.tab_id])
          it[r.tab_id].push(byId[r.id] = _row(r, names[r.tab_id]));
      }
      const sr = tx.executeSql("SELECT * FROM slots").rows;
      for (let i = 0; i < sr.length; i++) {
        const s = sr.item(i);
        if (byId[s.item_id]) {
          sl[s.n] = s.item_id;
          byId[s.item_id].slot = s.n;
        }
      }
    });
    tabs = t;
    items = it;
    slots = sl;
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

  // Assign slot n (1–9) to an item; n = 0 clears the item's slot. One item per slot.
  function setSlot(n, dbId) {
    if (dbId < 0)
      return false;  // encrypted items never sit on a global shortcut
    db.transaction(tx => {
      tx.executeSql("DELETE FROM slots WHERE item_id = ?", [dbId]);
      if (n > 0)
        tx.executeSql("INSERT OR REPLACE INTO slots (n, item_id) VALUES (?, ?)", [n, dbId]);
    });
    _load();
    return true;
  }

  function slotItem(n) {
    const id = slots[n];
    if (!id)
      return null;
    for (const k in items) {
      const r = items[k].find(x => x.dbId === id);
      if (r) return r;
    }
    return null;
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
      tx.executeSql("DELETE FROM slots WHERE item_id IN (SELECT id FROM items WHERE tab_id = ?)", [id]);
      tx.executeSql("DELETE FROM items WHERE tab_id = ?", [id]);
      tx.executeSql("DELETE FROM tabs WHERE id = ?", [id]);
      tx.executeSql("DELETE FROM vault WHERE tab_id = ?", [id]);
    });
    delete vault[id];
    _load();
  }

  // ---- vault ----
  function _vaultId() {
    return -(Date.now() * 100 + (++_vseq % 100));
  }

  function _vaultItem(dbId) {
    for (const k in vault) {
      const v = vault[k].find(x => x.id === dbId);
      if (v) return v;
    }
    return null;
  }

  function _changed(tabId) {
    _load();
    _save(tabId);
  }

  function _encrypt(pass, text, cb) {
    _gpg.exec(_gpgBase.concat(["--symmetric", "--armor", "--cipher-algo", "AES256", "-o", "-"]), pass + "\n" + text,
      (out, err, code) => cb(code === 0 ? "" : (err.trim() || "gpg failed"), out));
  }

  function _decrypt(pass, armored, cb) {
    _gpg.exec(_gpgBase.concat(["--decrypt"]), pass + "\n" + armored,
      (out, err, code) => cb(code === 0 ? "" : (err.trim() || "gpg failed"), out));
  }

  // Saves are serialized per tab; the newest snapshot always wins, even if the vault locks meanwhile.
  function _save(tabId) {
    _latest[tabId] = JSON.stringify(vault[tabId] || []);
    if (!_saving[tabId])
      _flush(tabId, passphrase);
  }

  function _flush(tabId, pass) {
    const json = _latest[tabId];
    delete _latest[tabId];
    _saving[tabId] = true;
    _encrypt(pass, json, (err, armored) => {
      _saving[tabId] = false;
      if (err) {
        ToastService.showError("Stash: could not save encrypted tab", err);
        return;
      }
      db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO vault (tab_id, blob) VALUES (?, ?)", [tabId, armored]));
      if (_latest[tabId] !== undefined)
        _flush(tabId, pass);
    });
  }

  // cb(error) — "" on success
  function setMaster(pass, cb) {
    _encrypt(pass, _check, (err, armored) => {
      if (err) return cb(err);
      setMeta("vault_check", armored);
      hasMaster = true;
      passphrase = pass;
      _load();
      cb("");
    });
  }

  function unlock(pass, cb) {
    const check = meta("vault_check");
    if (!check)
      return cb("No master passphrase set");
    _decrypt(pass, check, (err, out) => {
      if (err || out !== _check)
        return cb("Wrong passphrase");
      const blobs = [];
      db.readTransaction(tx => {
        const r = tx.executeSql("SELECT * FROM vault").rows;
        for (let i = 0; i < r.length; i++) blobs.push(r.item(i));
      });
      const v = {};
      let left = blobs.length, failed = "";
      const finish = () => {
        if (failed) return cb(failed);
        tabs.filter(t => t.encrypted).forEach(t => v[t.id] = v[t.id] || []);
        vault = v;
        passphrase = pass;
        _load();
        cb("");
      };
      if (!left) return finish();
      for (const b of blobs) {
        _decrypt(pass, b.blob, (e2, json) => {
          if (e2) failed = "Could not decrypt a tab: " + e2;
          else try { v[b.tab_id] = JSON.parse(json); } catch (x) { failed = "Corrupt encrypted tab"; }
          if (--left === 0) finish();
        });
      }
    });
  }

  function lock() {
    if (!unlocked)
      return;
    passphrase = "";
    vault = {};
    if (lastDeleted && lastDeleted.vaultItem)
      lastDeleted = null;
    _load();
    locked();
  }

  // Moves a plain tab's items into its encrypted block; plaintext rows are removed only after it is stored.
  function encryptTab(tabId, cb) {
    const items0 = (items[tabId] || []).map(r => ({ id: _vaultId(), tab_id: tabId, title: r.title, content: r.preview, lang: r.lang, created: Date.parse(r.timestamp), updated: Date.parse(r.timestamp) }));
    _encrypt(passphrase, JSON.stringify(items0), (err, armored) => {
      if (err) return cb(err);
      db.transaction(tx => {
        tx.executeSql("INSERT OR REPLACE INTO vault (tab_id, blob) VALUES (?, ?)", [tabId, armored]);
        tx.executeSql("UPDATE tabs SET encrypted = 1 WHERE id = ?", [tabId]);
        tx.executeSql("DELETE FROM slots WHERE item_id IN (SELECT id FROM items WHERE tab_id = ?)", [tabId]);
        tx.executeSql("DELETE FROM items WHERE tab_id = ?", [tabId]);
      });
      vault[tabId] = items0;
      _load();
      cb("");
    });
  }

  function decryptTab(tabId) {
    const list = vault[tabId];
    if (!list)
      return;
    db.transaction(tx => {
      for (const v of list)
        tx.executeSql("INSERT INTO items (tab_id, title, content, lang, created, updated) VALUES (?, ?, ?, ?, ?, ?)", [tabId, v.title, v.content, v.lang, v.created, v.updated]);
      tx.executeSql("DELETE FROM vault WHERE tab_id = ?", [tabId]);
      tx.executeSql("UPDATE tabs SET encrypted = 0 WHERE id = ?", [tabId]);
    });
    delete vault[tabId];
    _load();
  }

  function addItem(tabId, content, title, lang) {
    const now = Date.now();
    if (vault[tabId]) {
      const v = { id: _vaultId(), tab_id: tabId, title: title || "", content: content || "", lang: lang || "", created: now, updated: now };
      vault[tabId].push(v);
      _changed(tabId);
      return v.id;
    }
    let id = 0;
    db.transaction(tx => {
      id = parseInt(tx.executeSql("INSERT INTO items (tab_id, title, content, lang, created, updated) VALUES (?, ?, ?, ?, ?, ?)", [tabId, title || "", content || "", lang || "", now, now]).insertId);
    });
    _load();
    return id;
  }

  function updateItem(dbId, fields) {
    if (dbId < 0) {
      const v = _vaultItem(dbId);
      if (!v) return;
      for (const k of ["title", "content", "lang"])
        if (fields[k] !== undefined) v[k] = fields[k];
      v.updated = Date.now();
      return _changed(v.tab_id);
    }
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
    if (row.dbId < 0) {
      const list = vault[row.tabId] || [];
      const i = list.findIndex(v => v.id === row.dbId);
      if (i < 0) return;
      lastDeleted = { vaultItem: list.splice(i, 1)[0] };
      return _changed(row.tabId);
    }
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
    if (r.vaultItem) {
      lastDeleted = null;
      if (!vault[r.vaultItem.tab_id]) return false;
      vault[r.vaultItem.tab_id].push(r.vaultItem);
      _changed(r.vaultItem.tab_id);
      return true;
    }
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
    hasMaster = meta("vault_check") !== null;
    if (meta("imported_clipboardplus") === null)
      _import.running = true;
  }
}
