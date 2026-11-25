import QtQuick
import qs.Common
import "Classify.js" as C

Item {
  id: row
  required property var modelData
  required property int index
  property var history
  property bool selected: false
  property bool editing: false
  signal activated(var entry)
  signal hovered(int index)
  signal saveRequested(var entry, string text, string lang, string title)
  signal cancelRequested
  signal externalRequested(var entry, string text, string lang, string title)

  readonly property var e: modelData
  readonly property string kind: e.kind
  readonly property var kinds: ({
    "text": { icon: "font", tint: Theme.primary, label: "Text" },
    "url": { icon: "link", tint: Theme.warning, label: "URL" },
    "code": { icon: "code", tint: Theme.success, label: "Code" },
    "image": { icon: "image", tint: Theme.error, label: "Image" },
    "color": { icon: "palette", tint: Theme.primary, label: "Color" },
    "email": { icon: "envelope", tint: Theme.secondary, label: "Email" },
    "path": { icon: "folder", tint: Theme.surfaceVariantText, label: "Path" },
    "note": { icon: "note-sticky", tint: Theme.primary, label: "Note" }
  })
  readonly property var k: kinds[kind] || kinds.text
  readonly property var swatch: kind === "color" ? C.parseColor(e.preview) : null

  // Full text only for entries whose preview DMS truncated (≈100 chars, newlines collapsed).
  property string body: e.preview || ""
  property string thumb: ""
  readonly property bool needsFull: !e.collection && kind !== "image" && e.size > 100

  function load() {
    if (kind === "image") {
      const id = e.id;  // the row may be destroyed or reused before the load lands
      thumb = history.image(e, url => { if (row && row.e && row.e.id === id) row.thumb = url; }) || "";
    } else if (needsFull) {
      const id = e.id;
      const t = history.fullText(e, t2 => { if (row && row.e && row.e.id === id) row.body = t2; });
      body = t !== null ? t : (e.preview || "");
    } else {
      body = e.preview || "";
    }
  }
  Component.onCompleted: { load(); if (editing) startEdit(); }
  ListView.onReused: { thumb = ""; load(); }
  onModelDataChanged: load()
  onEditingChanged: if (editing) startEdit()

  // Load the untruncated text, then hand focus to the editor.
  function startEdit() {
    editor.text = e.preview || "";
    langInput.text = e.lang || "";
    titleInput.text = e.title || "";
    if (!e.collection && e.size > 100)
      history.loadFull(e, t => { if (row.editing) editor.text = t; });
    editor.cursorPosition = editor.length;
    (e.draft && e.collection ? titleInput : editor).forceActiveFocus();
  }

  width: ListView.view ? ListView.view.width : 400
  implicitHeight: content.implicitHeight + 18

  Rectangle {
    anchors.fill: parent
    color: row.selected ? Theme.withAlpha(Theme.primary, 0.12) : mouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.04) : "transparent"
  }
  Rectangle {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14 }
    height: 1
    color: Theme.withAlpha(Theme.outlineVariant, 0.45)
  }

  Row {
    id: content
    x: 14
    y: 9
    width: parent.width - 28
    spacing: 12

    Rectangle {
      width: 32
      height: 32
      radius: 8
      color: row.swatch ? Qt.rgba(row.swatch.r, row.swatch.g, row.swatch.b, row.swatch.a) : Theme.withAlpha(row.k.tint, 0.16)
      border.width: row.swatch ? 1 : 0
      border.color: Theme.withAlpha(Theme.surfaceText, 0.18)
      Icon {
        anchors.centerIn: parent
        visible: !row.swatch
        name: row.k.icon
        color: row.k.tint
        size: 15
      }
    }

    Column {
      width: content.width - 32 - 12 - num.width - 12
      spacing: 3

      Text {
        visible: !row.editing && !!row.e.title
        width: parent.width
        text: row.e.title || ""
        color: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
        elide: Text.ElideRight
      }

      Rectangle {
        visible: row.kind === "image"
        width: 168
        height: 94
        radius: 8
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true
        Image {
          anchors.fill: parent
          anchors.margins: 1
          source: row.thumb
          asynchronous: true
          cache: false
          fillMode: Image.PreserveAspectCrop
          sourceSize: Qt.size(336, 188)
        }
      }

      Text {
        visible: row.kind !== "image" && !row.editing
        width: parent.width
        // titled encrypted items show the title only; the secret stays masked in the list
        text: row.e.secret && row.e.title ? "••••••••" : row.kind === "color" ? row.body.trim() + "  <font color='" + Theme.surfaceVariantText + "'>" + C.rgbLabel(row.swatch) + "</font>" : row.body
        textFormat: row.kind === "color" ? Text.StyledText : Text.PlainText
        color: Theme.surfaceText
        font.family: row.kind === "code" || row.kind === "path" ? Theme.monoFontFamily : Theme.fontFamily
        font.pixelSize: 13
        wrapMode: Text.WrapAnywhere
        maximumLineCount: row.e.title ? 2 : 3
        elide: Text.ElideRight
        lineHeight: 1.15
      }

      Rectangle {
        visible: row.editing && !!row.e.collection
        width: parent.width
        height: 30
        radius: 8
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
        border.width: titleInput.activeFocus ? 1 : 0
        border.color: Theme.primary
        TextInput {
          id: titleInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.surfaceText
          selectionColor: Theme.primarySelected
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.bold: true
          clip: true
          Accessible.name: "Title"
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              editor.forceActiveFocus();
              event.accepted = true;
            } else {
              row.editorKey(event);
            }
          }
          Text {
            visible: !titleInput.text
            anchors.verticalCenter: parent.verticalCenter
            text: "Title (optional)"
            color: Theme.surfaceVariantText
            font: titleInput.font
          }
        }
      }

      Rectangle {
        visible: row.editing
        width: parent.width
        height: Math.min(220, Math.max(96, editor.contentHeight + 20))
        radius: 8
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
        border.width: editor.activeFocus ? 1 : 0
        border.color: Theme.primary
        Flickable {
          id: flick
          anchors.fill: parent
          anchors.margins: 10
          contentHeight: editor.contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          function ensureVisible(r) {
            if (contentY >= r.y) contentY = r.y;
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
          }
          TextEdit {
            id: editor
            width: flick.width
            wrapMode: TextEdit.Wrap
            color: Theme.surfaceText
            selectionColor: Theme.primarySelected
            font.family: row.kind === "note" || row.kind === "text" ? Theme.fontFamily : Theme.monoFontFamily
            font.pixelSize: 12
            onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
            Keys.onPressed: event => row.editorKey(event)
          }
        }
      }

      Row {
        visible: row.editing
        spacing: 10
        Rectangle {
          visible: !!row.e.collection
          width: 90
          height: 22
          radius: 6
          color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
          TextInput {
            id: langInput
            anchors.fill: parent
            anchors.leftMargin: 7
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.surfaceText
            font.family: Theme.monoFontFamily
            font.pixelSize: 11
            clip: true
            Keys.onPressed: event => row.editorKey(event)
            Text {
              visible: !langInput.text
              anchors.verticalCenter: parent.verticalCenter
              text: "language"
              color: Theme.surfaceVariantText
              font: langInput.font
            }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "^S save · Esc cancel · ^O editor" + (row.e.collection ? " · Tab next" : "")
          color: Theme.surfaceVariantText
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }

      Text {
        visible: !row.editing
        width: parent.width
        text: (row.e.pinned ? "★ " : "") + (row.e.slot ? "Slot " + row.e.slot + " · " : "") + row.k.label + (row.e.lang ? " · " + row.e.lang : "") + (row.kind === "image" ? " · " + C.imageLabel(row.e.preview) + " · " + C.fmtSize(row.e.size) : "") + " · " + C.age(row.e.timestamp)
        color: Theme.surfaceVariantText
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }

    Text {
      id: num
      width: 22
      horizontalAlignment: Text.AlignRight
      text: row.index < 9 ? String(row.index + 1) : ""
      color: Theme.surfaceVariantText
      font.family: Theme.fontFamily
      font.pixelSize: 11
    }
  }

  function editorKey(event) {
    const ctrl = event.modifiers & Qt.ControlModifier;
    if (event.key === Qt.Key_Escape) {
      cancelRequested();
    } else if (ctrl && event.key === Qt.Key_S) {
      saveRequested(e, editor.text, langInput.text.trim(), titleInput.text.trim());
    } else if (ctrl && event.key === Qt.Key_O) {
      externalRequested(e, editor.text, langInput.text.trim(), titleInput.text.trim());
    } else if (event.key === Qt.Key_Tab && e.collection) {
      (titleInput.activeFocus ? editor : editor.activeFocus ? langInput : titleInput).forceActiveFocus();
    } else {
      return;
    }
    event.accepted = true;
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: !row.editing
    hoverEnabled: true
    onPositionChanged: row.hovered(row.index)
    onClicked: row.activated(row.e)
  }
}
