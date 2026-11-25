import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import "Classify.js" as C

// Mod+C cycle preview: the entry now on the clipboard plus the next two, on an overlay layer
// (no focus, no tiling, not resizable). Hides shortly after the last press.
PanelWindow {
  id: win
  property var entries: []   // cycle snapshot: [{id, preview, isImage}]
  property int index: 0      // entry now on the clipboard
  property bool shown: false

  function flash() {
    shown = true;
    hideTimer.restart();
  }

  Timer {
    id: hideTimer
    interval: 1500
    onTriggered: win.shown = false
  }

  visible: shown
  color: "transparent"
  implicitWidth: 460
  implicitHeight: box.height
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "dms:stash-cycle"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}  // clicks pass through

  WindowBlur {
    targetWindow: win
    blurWidth: box.width
    blurHeight: box.height
    blurRadius: box.radius
  }

  Rectangle {
    id: box
    width: parent.width
    height: col.implicitHeight + 16
    radius: 14
    color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    border.width: 1
    border.color: Theme.withAlpha(Theme.primary, 0.5)

    Column {
      id: col
      x: 8
      y: 8
      width: parent.width - 16
      spacing: 2

      Repeater {
        model: 3
        delegate: Rectangle {
          required property int index
          readonly property int pos: win.entries.length ? (win.index + index) % win.entries.length : 0
          readonly property var e: win.entries[pos] || null
          readonly property bool current: index === 0
          visible: !!e && (index === 0 || win.entries.length > index)
          width: col.width
          height: 38
          radius: 10
          color: current ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

          Text {
            x: 10
            width: 26
            anchors.verticalCenter: parent.verticalCenter
            text: pos + 1
            color: parent.current ? Theme.primary : Theme.surfaceVariantText
            font.family: Theme.monoFontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
          Text {
            x: 40
            width: parent.width - 50
            anchors.verticalCenter: parent.verticalCenter
            text: !e ? "" : e.isImage ? "Image · " + C.imageLabel(e.preview) : (e.preview || "").replace(/\s+/g, " ").trim()
            color: parent.current ? Theme.surfaceText : Theme.surfaceVariantText
            font.family: Theme.fontFamily
            font.pixelSize: parent.current ? 14 : 13
            font.weight: parent.current ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }
    }
  }
}
