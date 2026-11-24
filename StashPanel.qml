import QtQuick
import qs.Common

Rectangle {
  id: panel
  property var history
  signal closeRequested
  signal pasteRequested(var entry, bool textOnly)

  readonly property var tabs: [
    { id: "all", label: "Clipboard", icon: "clipboard" },
    { id: "pinned", label: "Pinned", icon: "thumbtack" },
    { id: "url", label: "URLs", icon: "link" },
    { id: "image", label: "Images", icon: "image" },
    { id: "color", label: "Colors", icon: "palette" },
    { id: "code", label: "Code", icon: "code" },
    { id: "email", label: "Emails", icon: "envelope" },
    { id: "path", label: "Paths", icon: "folder" }
  ]
  property int tabIndex: 0
  property int current: 0
  readonly property var tab: tabs[tabIndex]
  readonly property var items: history ? history.filtered(tab.id, search.text) : []
  readonly property var selectedEntry: items[current] || null

  onItemsChanged: current = Math.min(current, Math.max(0, items.length - 1))
  onTabIndexChanged: { current = 0; list.positionViewAtBeginning(); }

  function reset() {
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

    Column {
      y: 10
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 4
      Repeater {
        model: panel.tabs
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool on: index === panel.tabIndex
          width: 36
          height: 36
          radius: 10
          color: on ? Theme.withAlpha(Theme.primary, 0.12) : railMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"
          Accessible.name: modelData.label
          Accessible.role: Accessible.PageTab
          Rectangle {
            visible: parent.on
            x: -8
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 18
            radius: 2
            color: Theme.primary
          }
          Icon {
            anchors.centerIn: parent
            name: modelData.icon
            size: 15
            color: parent.on ? Theme.primary : Theme.surfaceVariantText
          }
          MouseArea {
            id: railMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { panel.tabIndex = index; search.forceActiveFocus(); }
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
        x: 14
        anchors.bottom: parent.bottom
        text: panel.tab.label
        color: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
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
          text: panel.items.length.toLocaleString()
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
        onHovered: i => panel.current = i
        onActivated: entry => panel.pasteRequested(entry, false)
      }

      Text {
        anchors.centerIn: parent
        visible: panel.items.length === 0
        text: panel.history && !panel.history.available ? "DMS clipboard service is not connected" : search.text ? "No matches" : "Nothing here yet"
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
        text: panel.history && panel.history.pendingDelete ? "Deleted · Ctrl+Z to undo" : panel.items.length ? (panel.current + 1) + " of " + panel.items.length.toLocaleString() : ""
        color: panel.history && panel.history.pendingDelete ? Theme.primary : Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
      Text {
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: "⏎ paste · ^⏎ copy · Del delete · ^P pin"
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
    case Qt.Key_Tab:
    case Qt.Key_Backtab:
      if (!ctrl) return;
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
      if (ctrl) history.copy(e, false, () => closeRequested());
      else pasteRequested(e, !!shift);
      break;
    case Qt.Key_Delete:
      if (e) history.softDelete(e);
      break;
    case Qt.Key_Z:
      if (!ctrl || !history.undoDelete()) return;
      break;
    case Qt.Key_P:
      if (!ctrl || !e) return;
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
