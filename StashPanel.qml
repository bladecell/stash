import QtQuick
import qs.Common

Rectangle {
  id: panel
  property var history
  property var store
  signal closeRequested
  signal pasteRequested(var entry, bool textOnly)
  signal externalRequested(string text, string ext, var onSave)

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
  readonly property var tabs: builtinTabs.concat(store ? store.tabs.map(t => ({ id: "c" + t.id, label: t.name, icon: t.icon, collection: t.id })) : [])
  property int tabIndex: 0
  property int current: 0
  readonly property var tab: tabs[Math.min(tabIndex, tabs.length - 1)]

  property var draft: null          // unsaved new item, shown first while editing
  property string editingId: ""
  property string naming: ""        // "" | "new" | "rename" — header turns into a name field
  property int confirmTabDelete: 0  // collection id awaiting a second Ctrl+Shift+Del

  readonly property var baseItems: !history ? [] : tab.collection ? store.filtered(tab.collection, search.text) : history.filtered(tab.id, search.text)
  readonly property var items: draft ? [draft].concat(baseItems) : baseItems
  readonly property var selectedEntry: items[current] || null
  readonly property bool undoable: tab.collection ? !!(store && store.lastDeleted) : !!(history && history.pendingDelete)

  onItemsChanged: current = Math.min(current, Math.max(0, items.length - 1))
  onTabIndexChanged: {
    cancelEdit();
    confirmTabDelete = 0;
    if (store) store.lastDeleted = null;
    current = 0;
    list.positionViewAtBeginning();
  }

  function reset() {
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
  function persist(e, text, lang, onNewEntry) {
    if (e.draft) {
      if (e.collection)
        return { dbId: store.addItem(e.tabId, text, "", lang), collection: true };
      if (text)
        history.copyText(text, null);
      return null;
    }
    if (e.collection)
      store.updateItem(e.dbId, { content: text, lang: lang });
    else
      history.edit(e, text, onNewEntry);
    return e;
  }

  function saveEdit(e, text, lang) {
    editingId = "";
    draft = null;
    persist(e, text, lang);
    if (e.draft || !e.collection)
      current = 0;  // new and edited clipboard entries land at the top
    search.forceActiveFocus();
  }

  function openExternal(e, text, lang) {
    editingId = "";
    draft = null;
    let target = e;
    if (e.draft && e.collection)
      target = persist(e, text, lang);
    const ext = lang || (e.kind === "note" ? "md" : "txt");
    externalRequested(text, ext, t => {
      if (target.draft)
        history.copyText(t, null);  // new clipboard text: each save becomes the clipboard
      else
        persist(target, t, target.collection ? undefined : "", ne => target = ne);
    });
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
              width: 36
              height: 36
              radius: 10
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
                anchors.centerIn: parent
                name: railItem.modelData.icon
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

    // Search
    Rectangle {
      id: searchBox
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
        onSaveRequested: (entry, text, lang) => panel.saveEdit(entry, text, lang)
        onCancelRequested: panel.cancelEdit()
        onExternalRequested: (entry, text, lang) => panel.openExternal(entry, text, lang)
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
        readonly property bool alert: panel.confirmTabDelete !== 0 || panel.undoable
        text: panel.confirmTabDelete ? "Ctrl+Shift+Del again deletes this tab and " + panel.baseItems.length + " items"
            : panel.undoable ? "Deleted · Ctrl+Z to undo"
            : panel.items.length ? (panel.current + 1) + " of " + panel.items.length.toLocaleString() : ""
        color: panel.confirmTabDelete ? Theme.error : alert ? Theme.primary : Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
      Text {
        visible: !panel.confirmTabDelete
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: panel.tab.collection ? "⏎ paste · F2 edit · ^N new · Del delete" : "⏎ paste · F2 edit · Del delete · ^P pin"
        color: Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
    }
  }

  function handleKey(event) {
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
        if (e.collection) history.copyText(e.preview, () => closeRequested());
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
      if (!ctrl || !e || e.collection) return;
      history.setPinned(e, !e.pinned);
      break;
    default:
      if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
        const target = items[event.key - Qt.Key_1];
        if (target) pasteRequested(target, false);
        break;
      }
      return;
    }
    event.accepted = true;
  }
}
