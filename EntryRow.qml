import QtQuick
import qs.Common
import "Classify.js" as C

Item {
  id: row
  required property var modelData
  required property int index
  property var history
  property bool selected: false
  signal activated(var entry)
  signal hovered(int index)

  readonly property var e: modelData
  readonly property string kind: e.kind
  readonly property var kinds: ({
    "text": { icon: "font", tint: Theme.primary, label: "Text" },
    "url": { icon: "link", tint: Theme.warning, label: "URL" },
    "code": { icon: "code", tint: Theme.success, label: "Code" },
    "image": { icon: "image", tint: Theme.error, label: "Image" },
    "color": { icon: "palette", tint: Theme.primary, label: "Color" },
    "email": { icon: "envelope", tint: Theme.secondary, label: "Email" },
    "path": { icon: "folder", tint: Theme.surfaceVariantText, label: "Path" }
  })
  readonly property var k: kinds[kind] || kinds.text
  readonly property var swatch: kind === "color" ? C.parseColor(e.preview) : null

  // Full text only for entries whose preview DMS truncated (≈100 chars, newlines collapsed).
  property string body: e.preview || ""
  property string thumb: ""
  readonly property bool needsFull: kind !== "image" && e.size > 100

  function load() {
    if (kind === "image") {
      thumb = history.image(e, url => { if (row.e && row.e.kind === "image") row.thumb = url; }) || "";
    } else if (needsFull) {
      const t = history.fullText(e, t2 => row.body = t2);
      body = t !== null ? t : (e.preview || "");
    } else {
      body = e.preview || "";
    }
  }
  Component.onCompleted: load()
  ListView.onReused: { thumb = ""; load(); }
  onModelDataChanged: load()

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
        visible: row.kind !== "image"
        width: parent.width
        text: row.kind === "color" ? row.body.trim() + "  <font color='" + Theme.surfaceVariantText + "'>" + C.rgbLabel(row.swatch) + "</font>" : row.body
        textFormat: row.kind === "color" ? Text.StyledText : Text.PlainText
        color: Theme.surfaceText
        font.family: row.kind === "code" || row.kind === "path" ? Theme.monoFontFamily : Theme.fontFamily
        font.pixelSize: 13
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        lineHeight: 1.15
      }

      Text {
        width: parent.width
        text: (row.e.pinned ? "★ " : "") + row.k.label + (row.kind === "image" ? " · " + C.imageLabel(row.e.preview) + " · " + C.fmtSize(row.e.size) : "") + " · " + C.age(row.e.timestamp)
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

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: row.hovered(row.index)
    onClicked: row.activated(row.e)
  }
}
