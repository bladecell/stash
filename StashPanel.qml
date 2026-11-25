import QtQuick
import qs.Common
import "Commands.js" as Commands
import "icons.js" as Icons

Rectangle {
  id: panel
  property var history
  property var store
  signal closeRequested
  signal pasteRequested(var entry, bool textOnly)
  signal externalRequested(string text, string ext, var onSave, bool secret)
  signal commandRequested(var entry, var cmd)
  property var commands: []

  // Command menu (Ctrl+K): typing filters, Enter or 1–9 runs, Esc closes.
  property bool menuOpen: false
  property int menuIndex: 0
  property string menuFilter: ""
  property var menuEntry: null
  readonly property var menuItems: !menuEntry ? [] : commands.filter(c => Commands.appliesTo(c, menuEntry.kind)
      && (!menuFilter || c.name.toLowerCase().includes(menuFilter.toLowerCase())))
  onMenuItemsChanged: menuIndex = Math.min(menuIndex, Math.max(0, menuItems.length - 1))

  // Overlays: "" | "help" | "icons"
  property string overlay: ""
  property int iconIndex: 0
  readonly property var tabIcons: ["folder", "note-sticky", "code", "terminal", "key", "lock", "star", "heart", "bookmark", "briefcase", "house", "user", "globe", "bolt", "flask", "music", "book", "cart-shopping", "server", "database", "shield", "key-skeleton", "wallet", "graduation-cap", "gamepad", "camera", "calendar", "lightbulb", "rocket", "bug", "cloud", "leaf", "paw", "mug-hot", "chart-line", "list-check", "link", "image", "palette", "envelope", "file-lines", "face-smile"]
  readonly property int iconCols: 14

  function openIconPicker() {
    if (!tab.collection)
      return notify("Only Notes, Snippets and your own tabs have custom icons");
    iconIndex = Math.max(0, tabIcons.indexOf(tab.icon));
    overlay = "icons";
  }

  function overlayKey(event) {
    if (overlay === "icons") {
      const n = tabIcons.length;
      if (event.key === Qt.Key_Left) iconIndex = (iconIndex + n - 1) % n;
      else if (event.key === Qt.Key_Right) iconIndex = (iconIndex + 1) % n;
      else if (event.key === Qt.Key_Up) iconIndex = Math.max(0, iconIndex - iconCols);
      else if (event.key === Qt.Key_Down) iconIndex = Math.min(n - 1, iconIndex + iconCols);
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { store.setTabIcon(tab.collection, tabIcons[iconIndex]); overlay = ""; }
      else if (event.key === Qt.Key_Escape) overlay = "";
    } else {
      overlay = "";  // help: any key closes
    }
    event.accepted = true;
  }

  readonly property var helpKeys: [
    ["Enter / Shift+Enter", "Paste / paste as plain text"], ["Ctrl+Enter", "Copy without pasting"],
    ["Alt+1–9", "Paste item 1–9"], ["↑ ↓ PgUp PgDn Home End", "Move"],
    ["Tab / Shift+Tab", "Next / previous tab"], ["F2 / Ctrl+E", "Edit (Ctrl+S save, Esc cancel)"],
    ["Ctrl+O", "Open in external editor"], ["Ctrl+N", "New item"], ["Del / Ctrl+Z", "Delete / undo"],
    ["Ctrl+P", "Pin clipboard entry"], ["Ctrl+K", "Run a custom command"],
    ["Ctrl+Shift+1–9 / 0", "Put item on slot / clear"], ["Ctrl+T / Ctrl+R", "New tab / rename tab"],
    ["Ctrl+I", "Tab icon"], ["Ctrl+Shift+Del ×2", "Delete tab"],
    ["Ctrl+Shift+L", "Encrypt tab (×2 on encrypted: decrypt)"], ["Ctrl+L", "Lock encrypted tabs"],
    ["Ctrl+Shift+P", "Change master passphrase"], ["Esc", "Clear search / close"]
  ]

  function openMenu() {
    const e = selectedEntry;
    if (!e || e.draft || e.kind === "image")
      return;
    menuEntry = e;
    menuFilter = "";
    menuIndex = 0;
    menuOpen = true;
  }

  function runMenu(i) {
    const cmd = menuItems[i];
    const e = menuEntry;
    menuOpen = false;
    if (cmd)
      commandRequested(e, cmd);
  }

  function menuKey(event) {
    const d = digitOf(event);
    if (event.key === Qt.Key_Escape) menuOpen = false;
    else if (event.key === Qt.Key_Down) menuIndex = Math.min(menuItems.length - 1, menuIndex + 1);
    else if (event.key === Qt.Key_Up) menuIndex = Math.max(0, menuIndex - 1);
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) runMenu(menuIndex);
    else if (event.key === Qt.Key_Backspace) menuFilter = menuFilter.slice(0, -1);
    else if (d >= 1 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) runMenu(d - 1);
    else if (event.text && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) menuFilter += event.text;
    event.accepted = true;
  }

  readonly property var builtinTabs: [
    { id: "all", label: "Clipboard", icon: "clipboard" },
    { id: "pinned", label: "Pinned", icon: "thumbtack" },
    { id: "url", label: "URLs", icon: "link" },
    { id: "image", label: "Images", icon: "image" },
    { id: "color", label: "Colors", icon: "palette" },
    { id: "code", label: "Code", icon: "code" },
    { id: "email", label: "Emails", icon: "envelope" },
    { id: "path", label: "Paths", icon: "folder" }
  ]
  readonly property var tabs: builtinTabs.concat(store ? store.tabs.map(t => ({ id: "c" + t.id, label: t.name, icon: t.icon, collection: t.id, encrypted: t.encrypted, locked: t.locked })) : [])
  property int tabIndex: 0
  property int current: 0
  readonly property var tab: tabs[Math.min(tabIndex, tabs.length - 1)]

  property var draft: null          // unsaved new item, shown first while editing
  property string editingId: ""
  property string naming: ""        // "" | "new" | "rename" — header turns into a name field
  property int confirmTabDelete: 0  // collection id awaiting a second Ctrl+Shift+Del

  // Vault prompt: unlock a locked tab, or set the master passphrase / unlock before encrypting a tab.
  property string vaultPrompt: ""   // "" | "setup" | "unlock" | "change"
  property int pendingEncrypt: 0
  property int confirmDecrypt: 0
  property bool authBusy: false
  property string authError: ""
  readonly property string authMode: tab.locked ? "unlock" : vaultPrompt

  function focusAuth() {
    authError = "";
    pass1.input.text = "";
    pass2.input.text = "";
    pass3.input.text = "";
    pass1.input.forceActiveFocus();
  }

  function startChangePassphrase() {
    if (!store.hasMaster)
      return notify("No master passphrase yet · Ctrl+Shift+L on a tab sets one");
    vaultPrompt = "change";
  }

  // Tab moves between the setup fields; other routed keys (Ctrl+Tab, Tab in unlock, Ctrl+L…) act as usual.
  function authKey(event) {
    if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ControlModifier) && (authMode === "setup" || authMode === "change")) {
      const fields = authMode === "change" ? [pass1, pass2, pass3] : [pass1, pass2];
      const i = fields.findIndex(f => f.input.activeFocus);
      fields[(i + 1) % fields.length].input.forceActiveFocus();
    } else {
      handleKey(event);
    }
  }

  function cancelAuth() {
    if (!vaultPrompt)
      return closeRequested();
    vaultPrompt = "";
    pendingEncrypt = 0;
    search.forceActiveFocus();
  }

  function submitAuth() {
    const p = pass1.input.text;
    if (authBusy || !p)
      return;
    const done = err => {
      authBusy = false;
      if (err) {
        authError = err;
        pass1.input.selectAll();
        return;
      }
      afterAuth();
    };
    if (authMode === "setup") {
      if (p.length < 8) return authError = "Use at least 8 characters";
      if (p !== pass2.input.text) return authError = "Passphrases don't match";
      authBusy = true;
      store.setMaster(p, done);
    } else if (authMode === "change") {
      const np = pass2.input.text;
      if (np.length < 8) return authError = "Use at least 8 characters for the new passphrase";
      if (np !== pass3.input.text) return authError = "New passphrases don't match";
      authBusy = true;
      store.changeMaster(p, np, err => { done(err); if (!err) notify("Master passphrase changed"); });
    } else {
      authBusy = true;
      store.unlock(p, done);
    }
  }

  function afterAuth() {
    pass1.input.text = "";
    pass2.input.text = "";
    pass3.input.text = "";
    authError = "";
    vaultPrompt = "";
    if (pendingEncrypt) {
      const id = pendingEncrypt;
      pendingEncrypt = 0;
      doEncrypt(id);
    }
    search.forceActiveFocus();
  }

  function doEncrypt(id) {
    notify("Encrypting…");
    store.encryptTab(id, err => notify(err ? "Encryption failed: " + err : "Tab encrypted · Ctrl+L locks"));
  }

  function toggleEncryption() {
    if (!tab.collection)
      return notify("Only Notes, Snippets and your own tabs can be encrypted");
    if (tab.encrypted) {
      if (tab.locked)
        return;
      if (confirmDecrypt !== tab.collection) {
        notify("Ctrl+Shift+L again stores this tab unencrypted");
        confirmDecrypt = tab.collection;
        return;
      }
      confirmDecrypt = 0;
      store.decryptTab(tab.collection);
      return notify("Tab is no longer encrypted");
    }
    if (!store.hasMaster || !store.unlocked) {
      pendingEncrypt = tab.collection;
      vaultPrompt = store.hasMaster ? "unlock" : "setup";
      return;
    }
    doEncrypt(tab.collection);
  }

  onAuthModeChanged: Qt.callLater(() => authMode ? focusAuth() : search.forceActiveFocus())

  readonly property var baseItems: !history || tab.locked ? [] : tab.collection ? store.filtered(tab.collection, search.text) : history.filtered(tab.id, search.text)
  readonly property var items: draft ? [draft].concat(baseItems) : baseItems
  readonly property var selectedEntry: items[current] || null
  readonly property bool undoable: tab.collection ? !!(store && store.lastDeleted) : !!(history && history.pendingDelete)

  onItemsChanged: current = Math.min(current, Math.max(0, items.length - 1))
  onTabIndexChanged: {
    vaultPrompt = "";
    pendingEncrypt = 0;
    confirmDecrypt = 0;
    cancelEdit();
    confirmTabDelete = 0;
    if (store) store.lastDeleted = null;
    current = 0;
    list.positionViewAtBeginning();
  }

  function reset() {
    menuOpen = false;
    overlay = "";
    vaultPrompt = "";
    pendingEncrypt = 0;
    cancelEdit();
    naming = "";
    search.text = "";
    tabIndex = 0;
    current = 0;
    list.positionViewAtBeginning();
    search.forceActiveFocus();
  }

  function move(delta) {
    if (!items.length)
      return;
    current = Math.max(0, Math.min(items.length - 1, current + delta));
    list.positionViewAtIndex(current, ListView.Contain);
  }

  function cycleTab(delta) {
    tabIndex = (tabIndex + delta + tabs.length) % tabs.length;
  }

  // ---- editing ----
  function startNew() {
    search.text = "";
    draft = {
      id: "draft", draft: true, collection: !!tab.collection, tabId: tab.collection || 0,
      title: "", preview: "", lang: "", size: 0, timestamp: new Date().toISOString(),
      kind: tab.label === "Notes" ? "note" : tab.label === "Snippets" ? "code" : "text"
    };
    current = 0;
    editingId = "draft";
    list.positionViewAtBeginning();
  }

  function startEdit() {
    const e = selectedEntry;
    if (e && e.kind !== "image")
      editingId = String(e.id);
  }

  function cancelEdit() {
    if (!editingId)
      return;
    editingId = "";
    draft = null;
    search.forceActiveFocus();
  }

  // Saves without touching UI state; also used for external-editor saves.
  // title/lang undefined → left unchanged (collection items only)
  function persist(e, text, lang, title, onNewEntry) {
    if (e.draft) {
      if (e.collection)
        return { dbId: store.addItem(e.tabId, text, title, lang), collection: true };
      if (text)
        history.copyText(text, null);
      return null;
    }
    if (e.collection)
      store.updateItem(e.dbId, { content: text, lang: lang, title: title });
    else
      history.edit(e, text, onNewEntry);
    return e;
  }

  function saveEdit(e, text, lang, title) {
    editingId = "";
    draft = null;
    persist(e, text, lang, title);
    if (e.draft || !e.collection)
      current = 0;  // new and edited clipboard entries land at the top
    search.forceActiveFocus();
  }

  function openExternal(e, text, lang, title) {
    editingId = "";
    draft = null;
    let target = e;
    if (e.draft && e.collection)
      target = persist(e, text, lang, title);
    else if (e.collection && !e.draft)
      persist(e, text, lang, title);  // keep title/lang typed before Ctrl+O
    const ext = lang || (e.kind === "note" ? "md" : "txt");
    const secret = !!e.secret || !!(tab.encrypted && e.draft);
    externalRequested(text, ext, t => {
      if (target.draft)
        history.copyText(t, null);  // new clipboard text: each save becomes the clipboard
      else
        persist(target, t, undefined, undefined, ne => target = ne);
    }, secret);
  }

  function openSelectedExternal() {
    const e = selectedEntry;
    if (!e || e.kind === "image")
      return;
    if (e.collection || e.size <= 100)
      openExternal(e, e.preview || "", e.lang || "");
    else
      history.loadFull(e, t => openExternal(e, t, ""));
  }

  // ---- tabs ----
  function startNaming(mode) {
    if (mode === "rename" && !tab.collection)
      return;
    naming = mode;
    nameInput.text = mode === "rename" ? tab.label : "";
    nameInput.forceActiveFocus();
  }

  function commitNaming() {
    const name = nameInput.text.trim();
    const mode = naming;
    naming = "";
    if (name && mode === "new") {
      const id = store.addTab(name, "folder");
      tabIndex = tabs.findIndex(t => t.collection === id);
    } else if (name && mode === "rename") {
      store.renameTab(tab.collection, name);
    }
    search.forceActiveFocus();
  }

  function deleteTab() {
    if (!tab.collection)
      return;
    if (confirmTabDelete !== tab.collection) {
      confirmTabDelete = tab.collection;
      confirmTimer.restart();
      return;
    }
    const id = tab.collection;
    confirmTabDelete = 0;
    tabIndex = 0;
    store.deleteTab(id);
  }

  Timer {
    id: confirmTimer
    interval: 4000
    onTriggered: panel.confirmTabDelete = 0
  }

  // Popup transparency like the DMS launcher; niri's blur rule shows through.
  color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
  clip: true

  // Rail
  Rectangle {
    id: rail
    width: 52
    height: parent.height
    color: Theme.withAlpha(Theme.surface, 0.35)
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.outlineVariant }

    Flickable {
      anchors.fill: parent
      anchors.topMargin: 10
      contentHeight: railCol.implicitHeight + 10
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: railCol
        x: 8
        spacing: 4
        Repeater {
          model: panel.tabs
          delegate: Column {
            id: railItem
            required property var modelData
            required property int index
            readonly property bool on: index === panel.tabIndex
            spacing: 4
            // divider before the first collection tab
            Rectangle {
              visible: railItem.index === panel.builtinTabs.length
              width: 36
              height: 9
              color: "transparent"
              Rectangle { anchors.centerIn: parent; width: 20; height: 1; color: Theme.outlineVariant }
            }
            Rectangle {
              width: 28
              height: 28
              radius: 8
              color: railItem.on ? Theme.withAlpha(Theme.primary, 0.12) : railMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"
              Accessible.name: railItem.modelData.label
              Accessible.role: Accessible.PageTab
              Rectangle {
                visible: railItem.on
                x: -8
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 18
                radius: 2
                color: Theme.primary
              }
              Icon {
                visible: !!railItem.modelData.encrypted && !railItem.modelData.locked
                anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                name: "lock"
                size: 8
                color: Theme.surfaceVariantText
              }
              Icon {
                anchors.centerIn: parent
                name: railItem.modelData.locked ? "lock" : railItem.modelData.icon
                size: 15
                color: railItem.on ? Theme.primary : Theme.surfaceVariantText
              }
              MouseArea {
                id: railMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { panel.tabIndex = railItem.index; search.forceActiveFocus(); }
              }
            }
          }
        }
        Rectangle {
          width: 36
          height: 36
          radius: 10
          color: addMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"
          Accessible.name: "New tab"
          Icon { anchors.centerIn: parent; name: "plus"; size: 13; color: Theme.surfaceVariantText }
          MouseArea {
            id: addMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: panel.startNaming("new")
          }
        }
      }
    }
  }

  Item {
    id: main
    anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }

    // Header
    Item {
      id: header
      width: parent.width
      height: 34
      Text {
        visible: !panel.naming
        x: 14
        anchors.bottom: parent.bottom
        text: panel.tab.label
        color: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
      }
      TextInput {
        id: nameInput
        visible: !!panel.naming
        x: 14
        width: parent.width - 120
        anchors.bottom: parent.bottom
        color: Theme.surfaceText
        selectionColor: Theme.primarySelected
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        clip: true
        Accessible.name: "Tab name"
        Text {
          visible: !nameInput.text
          text: panel.naming === "new" ? "New tab name…" : "Tab name…"
          color: Theme.surfaceVariantText
          font: nameInput.font
        }
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) panel.commitNaming();
          else if (event.key === Qt.Key_Escape) { panel.naming = ""; search.forceActiveFocus(); }
          else return;
          event.accepted = true;
        }
      }
      Rectangle {
        anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom }
        height: 18
        width: countText.implicitWidth + 14
        radius: 9
        color: Theme.surfaceContainerHighest
        Text {
          id: countText
          anchors.centerIn: parent
          text: panel.baseItems.length.toLocaleString()
          color: Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }
      }
    }

    // Vault prompt
    Item {
      visible: panel.authMode !== ""
      anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top }
      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 300)
        spacing: 10
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "lock"; size: 26; color: Theme.primary }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: panel.authMode === "setup" ? "Set a master passphrase" : panel.authMode === "change" ? "Change master passphrase" : panel.tab.locked ? panel.tab.label + " is locked" : "Unlock to encrypt " + panel.tab.label
          color: Theme.surfaceText
          font.family: Theme.fontFamily
          font.pixelSize: 14
          font.bold: true
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: panel.authMode === "setup" ? "One passphrase unlocks every encrypted tab. It can't be recovered if you forget it."
              : panel.authMode === "change" ? "Every encrypted tab is re-encrypted with the new passphrase." : "Enter your master passphrase"
          color: Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        PassField {
          id: pass1
          placeholder: panel.authMode === "change" ? "Current passphrase" : "Passphrase"
          onSubmitted: panel.submitAuth()
          onCancelled: panel.cancelAuth()
          onKeyRouted: event => panel.authKey(event)
        }
        PassField {
          id: pass2
          visible: panel.authMode === "setup" || panel.authMode === "change"
          placeholder: panel.authMode === "change" ? "New passphrase" : "Repeat passphrase"
          onSubmitted: panel.submitAuth()
          onCancelled: panel.cancelAuth()
          onKeyRouted: event => panel.authKey(event)
        }
        PassField {
          id: pass3
          visible: panel.authMode === "change"
          placeholder: "Repeat new passphrase"
          onSubmitted: panel.submitAuth()
          onCancelled: panel.cancelAuth()
          onKeyRouted: event => panel.authKey(event)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: panel.authBusy ? "Working…" : panel.authError || ("⏎ " + (panel.authMode === "setup" ? "set passphrase" : panel.authMode === "change" ? "change" : "unlock") + " · Esc " + (panel.vaultPrompt ? "cancel" : "close"))
          color: panel.authError && !panel.authBusy ? Theme.error : Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
    }

    // Search
    Rectangle {
      id: searchBox
      visible: panel.authMode === ""
      anchors { top: header.bottom; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
      height: 36
      radius: 10
      color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
      Icon {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        name: "magnifying-glass"
        size: 13
        color: Theme.surfaceVariantText
      }
      TextInput {
        id: search
        anchors { left: parent.left; right: parent.right; leftMargin: 35; rightMargin: 12; verticalCenter: parent.verticalCenter }
        color: Theme.surfaceText
        selectionColor: Theme.primarySelected
        font.family: Theme.fontFamily
        font.pixelSize: 12
        clip: true
        focus: true
        Accessible.name: "Search"
        onTextChanged: { panel.current = 0; list.positionViewAtBeginning(); }
        Text {
          visible: !search.text
          anchors.verticalCenter: parent.verticalCenter
          text: "Search " + panel.tab.label.toLowerCase() + "…"
          color: Theme.surfaceVariantText
          font: search.font
        }
        Keys.onPressed: event => panel.handleKey(event)
      }
    }

    ListView {
      id: list
      visible: panel.authMode === ""
      anchors { top: searchBox.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: footer.top }
      clip: true
      model: panel.items
      reuseItems: true
      cacheBuffer: 400
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: panel.current
      highlightFollowsCurrentItem: false
      delegate: EntryRow {
        history: panel.history
        selected: index === panel.current
        editing: panel.editingId !== "" && String(modelData.id) === panel.editingId
        onHovered: i => { if (!panel.editingId) panel.current = i; }
        onActivated: entry => panel.pasteRequested(entry, false)
        onSaveRequested: (entry, text, lang, title) => panel.saveEdit(entry, text, lang, title)
        onCancelRequested: panel.cancelEdit()
        onExternalRequested: (entry, text, lang, title) => panel.openExternal(entry, text, lang, title)
      }

      Text {
        anchors.centerIn: parent
        visible: panel.items.length === 0
        text: panel.history && !panel.history.available && !panel.tab.collection ? "DMS clipboard service is not connected" : search.text ? "No matches" : panel.tab.collection ? "Empty · Ctrl+N to add" : "Nothing here yet"
        color: Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    // Command menu
    Rectangle {
      visible: panel.menuOpen
      z: 5
      anchors { left: parent.left; right: parent.right; bottom: footer.top; margins: 12 }
      height: menuCol.implicitHeight + 16
      radius: 12
      color: Theme.surfaceContainerHigh
      border.width: 1
      border.color: Theme.outlineVariant
      Column {
        id: menuCol
        x: 8
        y: 8
        width: parent.width - 16
        spacing: 2
        Row {
          x: 6
          spacing: 8
          height: 24
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "terminal"; size: 12; color: Theme.primary }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: panel.menuFilter ? panel.menuFilter : "Run on selected item · type to filter"
            color: panel.menuFilter ? Theme.surfaceText : Theme.surfaceVariantText
            font.family: Theme.fontFamily
            font.pixelSize: 12
          }
        }
        Repeater {
          model: panel.menuItems
          delegate: Rectangle {
            id: menuRow
            required property var modelData
            required property int index
            width: menuCol.width
            height: 30
            radius: 8
            color: index === panel.menuIndex ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"
            Text {
              x: 8
              width: 16
              anchors.verticalCenter: parent.verticalCenter
              text: menuRow.index < 9 ? String(menuRow.index + 1) : ""
              color: Theme.surfaceVariantText
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
            Text {
              x: 30
              width: parent.width - 30 - outText.width - 16
              anchors.verticalCenter: parent.verticalCenter
              text: menuRow.modelData.name
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: 13
              elide: Text.ElideRight
            }
            Text {
              id: outText
              anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
              text: menuRow.modelData.output || "copy"
              color: Theme.surfaceVariantText
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: panel.menuIndex = menuRow.index
              onClicked: panel.runMenu(menuRow.index)
            }
          }
        }
        Text {
          visible: panel.menuItems.length === 0
          x: 8
          height: 28
          verticalAlignment: Text.AlignVCenter
          text: "No commands for this item · add them in Stash settings"
          color: Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    // Help / icon picker
    Rectangle {
      visible: panel.overlay !== ""
      z: 6
      anchors { left: parent.left; bottom: footer.top; margins: 12 }
      width: panel.overlay === "icons" ? Math.min(parent.width - 24, iconGrid.implicitWidth + 24) : parent.width - 24
      height: Math.min(footer.y - header.height - 24, ovCol.implicitHeight + 20)
      radius: 12
      color: Theme.surfaceContainerHigh
      border.width: 1
      border.color: Theme.outlineVariant
      clip: true
      Flickable {
        id: ovFlick
        anchors.fill: parent
        anchors.margins: 10
        contentHeight: ovCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
      Column {
        id: ovCol
        x: 2
        width: ovFlick.width - 4
        spacing: 6
        Text {
          text: panel.overlay === "icons" ? "Icon for " + panel.tab.label + " · arrows, Enter" : "Shortcuts · any key closes"
          color: Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
        Grid {
          id: iconGrid
          visible: panel.overlay === "icons"
          columns: panel.iconCols
          spacing: 2
          Repeater {
            model: panel.overlay === "icons" ? panel.tabIcons : []
            delegate: Rectangle {
              required property string modelData
              required property int index
              width: 28
              height: 28
              radius: 8
              color: index === panel.iconIndex ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"
              border.width: index === panel.iconIndex ? 1 : 0
              border.color: Theme.primary
              Icon { anchors.centerIn: parent; name: parent.modelData; size: 13; color: parent.index === panel.iconIndex ? Theme.primary : Theme.surfaceText }
              MouseArea {
                anchors.fill: parent
                onClicked: { store.setTabIcon(panel.tab.collection, parent.modelData); panel.overlay = ""; }
              }
            }
          }
        }
        Grid {
          id: helpGrid
          visible: panel.overlay === "help"
          columns: ovCol.width > 760 ? 2 : 1
          columnSpacing: 20
          rowSpacing: 6
          readonly property real cellWidth: (ovCol.width - columnSpacing * (columns - 1)) / columns
        Repeater {
          model: panel.overlay === "help" ? panel.helpKeys : []
          delegate: Row {
            required property var modelData
            width: helpGrid.cellWidth
            spacing: 12
            Text {
              width: 150
              text: modelData[0]
              color: Theme.primary
              font.family: Theme.monoFontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
            Text {
              width: helpGrid.cellWidth - 162
              text: modelData[1]
              color: Theme.surfaceText
              font.family: Theme.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
            }
          }
        }
        }
      }
      }
    }

    // Footer
    Rectangle {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      height: 34
      color: "transparent"
      Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }
      Text {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool alert: panel.confirmTabDelete !== 0 || panel.undoable || !!panel.notice
        text: panel.notice ? panel.notice
            : panel.confirmTabDelete ? "Ctrl+Shift+Del again deletes this tab and " + panel.baseItems.length + " items"
            : panel.undoable ? "Deleted · Ctrl+Z to undo"
            : panel.items.length ? (panel.current + 1) + " of " + panel.items.length.toLocaleString() : ""
        color: panel.confirmTabDelete ? Theme.error : alert ? Theme.primary : Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
      Text {
        visible: !panel.confirmTabDelete && !panel.notice
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: panel.tab.encrypted ? (panel.tab.locked ? "Tab other tabs · F1 keys" : "⏎ paste · F2 edit · ^L lock · F1 keys")
            : panel.tab.collection ? "⏎ paste · F2 edit · ^N new · F1 keys" : "⏎ paste · F2 edit · ^K run · F1 keys"
        color: Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
    }
  }

  // Digit 0–9 from the key, or from the physical number row (non-US layouts, e.g. cz types ěšč…).
  function digitOf(event) {
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
      return event.key - Qt.Key_0;
    const sc = event.nativeScanCode;  // XKB keycode = evdev + 8: 1..9 → 10..18, 0 → 19
    return sc >= 10 && sc <= 18 ? sc - 9 : sc === 19 ? 0 : -1;
  }

  property string notice: ""
  Timer {
    id: noticeTimer
    interval: 3000
    onTriggered: { panel.notice = ""; panel.confirmDecrypt = 0; }
  }
  function notify(text) {
    notice = text;
    noticeTimer.restart();
  }

  function assignSlot(n) {
    const e = selectedEntry;
    if (!e || e.draft)
      return;
    if (!e.collection) {
      notify("Slots hold Notes/Snippets items; unassigned slots paste history item N");
      return;
    }
    if (!store.setSlot(n, e.dbId))
      return notify("Encrypted items can't be put on slots");
    notify(n ? "Slot " + n + " now pastes this item" : "Slot cleared");
  }

  function handleKey(event) {
    if (menuOpen)
      return menuKey(event);
    if (overlay)
      return overlayKey(event);
    const ctrl = event.modifiers & Qt.ControlModifier;
    const shift = event.modifiers & Qt.ShiftModifier;
    const alt = event.modifiers & Qt.AltModifier;
    const e = selectedEntry;
    switch (event.key) {
    case Qt.Key_Escape:
      if (search.text) search.text = ""; else closeRequested();
      break;
    case Qt.Key_Down: move(1); break;
    case Qt.Key_Up: move(-1); break;
    case Qt.Key_PageDown: move(8); break;
    case Qt.Key_PageUp: move(-8); break;
    case Qt.Key_Home: move(-items.length); break;
    case Qt.Key_End: move(items.length); break;
    case Qt.Key_Tab:      // Tab / Ctrl+Tab next, Shift+Tab / Ctrl+Shift+Tab previous
    case Qt.Key_Backtab:
      cycleTab(event.key === Qt.Key_Backtab || shift ? -1 : 1);
      break;
    case Qt.Key_Left:
    case Qt.Key_Right:
      if (!ctrl) return;
      cycleTab(event.key === Qt.Key_Left ? -1 : 1);
      break;
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (!e) break;
      if (ctrl) {
        if (e.collection) history.copyText(e.preview, () => closeRequested(), e.secret);
        else history.copy(e, false, () => closeRequested());
      } else {
        pasteRequested(e, !!shift);
      }
      break;
    case Qt.Key_F2: startEdit(); break;
    case Qt.Key_E:
      if (!ctrl) return;
      startEdit();
      break;
    case Qt.Key_N:
      if (!ctrl) return;
      startNew();
      break;
    case Qt.Key_O:
      if (!ctrl) return;
      openSelectedExternal();
      break;
    case Qt.Key_K:
      if (!ctrl) return;
      openMenu();
      break;
    case Qt.Key_F1: overlay = "help"; break;
    case Qt.Key_Slash:
      if (!ctrl) return;
      overlay = "help";
      break;
    case Qt.Key_I:
      if (!ctrl) return;
      openIconPicker();
      break;
    case Qt.Key_L:
      if (!ctrl) return;
      if (shift) toggleEncryption();
      else if (store.unlocked) { store.lock(); notify("Encrypted tabs locked"); }
      break;
    case Qt.Key_T:
      if (!ctrl) return;
      startNaming("new");
      break;
    case Qt.Key_R:
      if (!ctrl) return;
      startNaming("rename");
      break;
    case Qt.Key_Delete:
      if (ctrl && shift) deleteTab();
      else if (e && e.collection) store.deleteItem(e);
      else if (e) history.softDelete(e);
      break;
    case Qt.Key_Z:
      if (!ctrl) return;
      if (tab.collection) store.undoDelete(); else history.undoDelete();
      break;
    case Qt.Key_P:
      if (!ctrl) return;
      if (shift) startChangePassphrase();
      else if (e && !e.collection) history.setPinned(e, !e.pinned);
      break;
    default: {
      const d = digitOf(event);
      if (ctrl && shift && d >= 0) {
        assignSlot(d);
        break;
      }
      if (alt && !ctrl && d >= 1) {
        const target = items[d - 1];
        if (target) pasteRequested(target, false);
        break;
      }
      return;
    }
    }
    event.accepted = true;
  }
}
