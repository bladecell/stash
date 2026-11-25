import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets

// Numbered list on an overlay layer (no focus, no tiling, not resizable, clicks pass through).
// Used for the Mod+C cycle preview and the hold-Mod+Alt slot list.
PanelWindow {
  id: win
  property var rows: []   // [{ n, text, current, badge }]
  property bool shown: false

  function flash() {    // show, then hide shortly after the last call
    shown = true;
    hideTimer.restart();
  }
  function show() { hideTimer.stop(); shown = true; }
  function hide() { hideTimer.stop(); shown = false; }

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
  WlrLayershell.namespace: "dms:stash-overlay"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

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
        model: win.rows
        delegate: Rectangle {
          required property var modelData
          width: col.width
          height: 36
          radius: 10
          color: modelData.current ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

          Text {
            x: 10
            width: 26
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.n
            color: modelData.current ? Theme.primary : Theme.surfaceVariantText
            font.family: Theme.monoFontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
          Text {
            x: 40
            width: parent.width - 50 - (badge.visible ? badge.width + 8 : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.text
            color: modelData.current ? Theme.surfaceText : Theme.surfaceVariantText
            font.family: Theme.fontFamily
            font.pixelSize: modelData.current ? 14 : 13
            font.weight: modelData.current ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          Rectangle {
            id: badge
            visible: !!modelData.badge
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: badgeText.implicitWidth + 14
            height: 20
            radius: 10
            color: Theme.withAlpha(Theme.primary, 0.16)
            Text {
              id: badgeText
              anchors.centerIn: parent
              text: modelData.badge || ""
              color: Theme.primary
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }
    }
  }
}
