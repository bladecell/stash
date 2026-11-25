import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Commands.js" as Commands

// Custom commands list: each row opens in place for editing; "Add command" opens an empty editor.
ListSetting {
  id: root
  settingKey: "commands"
  label: "Custom commands"
  description: "Ctrl+K in Stash runs these on the selected item. The text arrives on stdin and in $STASH_TEXT ($STASH_KIND = item kind, $STASH_DIR = plugin folder). Kinds limits a command to item types (text, url, code, email, path, color, note); empty means all. Commands marked on paste run when you paste with Ctrl+Shift+V; Enter pastes the original."
  defaultValue: Commands.defaults

  property int editing: -1  // row being edited; items.length = new command

  function saveAt(i, cmd) {
    const next = items.slice();
    next[i] = cmd;
    items = next;
    editing = -1;
  }

  function remove(i) {
    editing = -1;
    removeItem(i);
  }

  delegate: Item {
    required property int index
    required property var modelData
    width: parent.width
    height: root.editing === index ? rowEditor.height : 44

    StyledRect {
      visible: root.editing !== index
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.chipSurface

      Row {
        anchors { left: parent.left; leftMargin: Theme.spacingM; right: rowButtons.left; rightMargin: Theme.spacingM; verticalCenter: parent.verticalCenter }
        spacing: Theme.spacingM
        StyledText {
          width: 130
          text: modelData.name || ""
          wrapMode: Text.NoWrap
          color: Theme.surfaceText
          font.weight: Theme.fontWeightMedium
          elide: Text.ElideRight
        }
        StyledText {
          width: parent.width - 130 - 70 - 72 - Theme.spacingM * 3
          text: (modelData.command || "").replace(/\s+/g, " ")
          wrapMode: Text.NoWrap
          maximumLineCount: 1
          color: Theme.surfaceVariantText
          font.family: Theme.monoFontFamily
          font.pixelSize: Theme.fontSizeSmall
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
          width: 70
          text: modelData.output || "copy"
          color: Theme.surfaceVariantText
          font.pixelSize: Theme.fontSizeSmall
          anchors.verticalCenter: parent.verticalCenter
        }
        StyledRect {
          opacity: Commands.onPaste(modelData) ? 1 : 0
          width: 72
          height: 20
          radius: 10
          color: Theme.withAlpha(Theme.primary, 0.16)
          anchors.verticalCenter: parent.verticalCenter
          StyledText { id: badgeText; anchors.centerIn: parent; text: "on paste"; color: Theme.primary; font.pixelSize: Theme.fontSizeSmall }
        }
      }

      Row {
        id: rowButtons
        anchors { right: parent.right; rightMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
        spacing: Theme.spacingS
        DButton { text: "Edit"; variant: "tonal"; onClicked: root.editing = index }
        DButton { text: "Remove"; variant: "tonal"; danger: true; onClicked: root.remove(index) }
      }
    }

    CommandEditor {
      id: rowEditor
      visible: root.editing === index
      width: parent.width
      cmd: modelData
      active: root.editing === index
      onSaved: c => root.saveAt(index, c)
      onCancelled: root.editing = -1
    }
  }

  inputs: [
    Row {
      spacing: Theme.spacingS
      DButton { text: "Add command"; iconName: "add"; onClicked: root.editing = root.items.length }
      DButton { text: "Restore defaults"; variant: "tonal"; onClicked: { root.editing = -1; root.items = Commands.defaults; } }
    },
    CommandEditor {
      visible: root.editing === root.items.length
      width: parent.width
      cmd: ({})
      active: visible
      onSaved: c => root.saveAt(root.items.length, c)
      onCancelled: root.editing = -1
    }
  ]

  component CommandEditor: StyledRect {
    id: ed
    property var cmd: ({})
    property bool active: false
    property string output: "copy"
    property bool auto: false
    signal saved(var cmd)
    signal cancelled

    height: edCol.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.chipSurface
    border.width: 1
    border.color: Theme.primary

    // reload the fields each time the editor opens
    onActiveChanged: if (active) {
      nameField.text = cmd.name || "";
      commandField.text = cmd.command || "";
      kindsField.text = cmd.kinds || "";
      output = cmd.output || "copy";
      auto = Commands.onPaste(cmd);
      error.text = "";
      nameField.forceActiveFocus();
    }

    readonly property bool autoAllowed: output !== "none"

    function save() {
      if (!nameField.text.trim()) return error.text = "Give the command a name";
      if (!commandField.text.trim()) return error.text = "Enter a shell command";
      saved({ name: nameField.text.trim(), command: commandField.text.trim(), output: output, kinds: kindsField.text.trim(), onPaste: auto && autoAllowed });
    }

    Column {
      id: edCol
      x: Theme.spacingM
      y: Theme.spacingM
      width: parent.width - Theme.spacingM * 2
      spacing: Theme.spacingS

      Row {
        width: parent.width
        spacing: Theme.spacingS
        DTextField { id: nameField; width: 180; placeholderText: "Name"; onAccepted: ed.save() }
        DTextField { id: kindsField; width: parent.width - 180 - Theme.spacingS; placeholderText: "Kinds, e.g. url,text (empty = all)"; onAccepted: ed.save() }
      }
      DTextField {
        id: commandField
        width: parent.width
        placeholderText: "Shell command, e.g. jq ."
        font.family: Theme.monoFontFamily
        onAccepted: ed.save()
      }
      Row {
        spacing: Theme.spacingS
        StyledText { text: "Output"; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter; width: 60 }
        Repeater {
          model: Commands.outputs
          delegate: StyledRect {
            required property string modelData
            width: chipText.implicitWidth + 24
            height: 30
            radius: 15
            color: ed.output === modelData ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
            border.width: 1
            border.color: ed.output === modelData ? Theme.primary : Theme.outlineVariant
            StyledText { id: chipText; anchors.centerIn: parent; text: parent.modelData; color: ed.output === parent.modelData ? Theme.primary : Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.output = parent.modelData }
          }
        }
      }
      DToggle {
        width: parent.width
        text: "Run on Ctrl+Shift+V paste"
        description: ed.autoAllowed ? "Ctrl+Shift+V in Stash pastes the item after running it through every command with this on (if Kinds match)" : "Not for commands with output none"
        checked: ed.auto && ed.autoAllowed
        enabled: ed.autoAllowed
        onToggled: v => ed.auto = v
      }
      StyledText { id: error; visible: text !== ""; color: Theme.error; font.pixelSize: Theme.fontSizeSmall }
      Row {
        spacing: Theme.spacingS
        DButton { text: "Save"; onClicked: ed.save() }
        DButton { text: "Cancel"; variant: "tonal"; onClicked: ed.cancelled() }
      }
    }
  }
}
