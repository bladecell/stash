import QtQuick
import qs.Common

// Password input for the vault prompt; reports keys instead of handling them.
Rectangle {
  id: field
  property alias input: ti
  property string placeholder: ""
  signal submitted
  signal cancelled
  signal keyRouted(var event)  // Tab / Ctrl+arrows etc., handled by the panel

  width: parent.width
  height: 36
  radius: 10
  color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
  border.width: ti.activeFocus ? 1 : 0
  border.color: Theme.primary

  TextInput {
    id: ti
    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
    verticalAlignment: TextInput.AlignVCenter
    echoMode: TextInput.Password
    passwordCharacter: "•"
    color: Theme.surfaceText
    selectionColor: Theme.primarySelected
    font.family: Theme.fontFamily
    font.pixelSize: 13
    clip: true
    Accessible.name: field.placeholder
    Text {
      visible: !ti.text
      anchors.verticalCenter: parent.verticalCenter
      text: field.placeholder
      color: Theme.surfaceVariantText
      font: ti.font
    }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) field.submitted();
      else if (event.key === Qt.Key_Escape) field.cancelled();
      else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
          || ((event.modifiers & Qt.ControlModifier) && [Qt.Key_Left, Qt.Key_Right, Qt.Key_L].includes(event.key))) field.keyRouted(event);
      else return;
      event.accepted = true;
    }
  }
}
