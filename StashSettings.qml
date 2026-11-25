import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Commands.js" as Commands

PluginSettings {
  id: root
  pluginId: "stash"

  ToggleSetting {
    settingKey: "closeOnFocusLoss"
    label: "Close when another window is focused"
    description: "Hide Stash as soon as focus moves to a different window"
    defaultValue: false
  }

  SliderSetting {
    settingKey: "autoLockMinutes"
    label: "Lock encrypted tabs after (minutes)"
    description: "Idle time before encrypted tabs lock again; 0 locks only on Ctrl+L or when the screen locks"
    defaultValue: 10
    minimum: 0
    maximum: 120
  }

  StringSetting {
    settingKey: "editorCommand"
    label: "External editor command"
    description: "Used by Ctrl+O; the file path is appended. Empty runs $VISUAL or $EDITOR in your terminal"
    placeholder: "e.g. zeditor"
    defaultValue: ""
  }

  ListSettingWithInput {
    settingKey: "commands"
    label: "Custom commands"
    description: "Ctrl+K in Stash runs these on the selected item. The text arrives on stdin and in $STASH_TEXT. Output: copy, paste, replace (rewrite the item) or none. Kinds limits the command to item types (text, url, code, email, path, color, note); empty means all. On copy: yes runs it on everything you copy and replaces the entry with the output (copy and replace outputs only)"
    defaultValue: Commands.defaults
    fields: [
      { id: "name", label: "Name", placeholder: "Format JSON", width: 130, required: true },
      { id: "command", label: "Command", placeholder: "jq .", width: 200, required: true },
      { id: "output", label: "Output", placeholder: "copy", width: 80, default: "copy" },
      { id: "kinds", label: "Kinds", placeholder: "all", width: 110 },
      { id: "auto", label: "On copy", placeholder: "no", width: 70 }
    ]
  }

  StringSetting {
    id: slotMod
    settingKey: "slotModifier"
    label: "Slot shortcut modifier"
    description: "Modifier for the paste-slot binds (niri syntax, e.g. Mod+Alt, Mod+Ctrl, Ctrl+Alt). Click Write niri binds after changing it"
    placeholder: "Mod+Alt"
    defaultValue: "Mod+Alt"
  }

  StringSetting {
    id: cycleKey
    settingKey: "cycleKey"
    label: "Copy-older-entry shortcut"
    description: "Each press copies the next older clipboard entry (2nd, 3rd, …) so you can paste it. 'none' skips the bind. Click Write niri binds after changing it"
    placeholder: "Mod+C"
    defaultValue: "Mod+C"
  }

  Column {
    width: parent.width
    spacing: 6

    Text {
      width: parent.width
      text: "Global shortcuts"
      color: Theme.surfaceText
      font.pixelSize: Theme.fontSizeMedium
      font.weight: Font.Medium
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Writes ~/.config/niri/stash-binds.kdl (Mod+V opens Stash, <modifier>+1–9 paste slots, the copy-older-entry key) and includes it from config.kdl. Keys already bound elsewhere are skipped; if niri rejects the config, nothing changes."
      color: Theme.surfaceVariantText
      font.pixelSize: Theme.fontSizeSmall
    }
    DButton {
      text: "Write niri binds"
      busy: writer.running
      enabled: !writer.running
      onClicked: writer.running = true
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      visible: !!text
      text: writer.result
      color: writer.ok ? Theme.surfaceVariantText : Theme.error
      font.family: Theme.monoFontFamily
      font.pixelSize: Theme.fontSizeSmall
    }

    Process {
      id: writer
      property string result: ""
      property bool ok: true
      command: ["sh", decodeURIComponent(Qt.resolvedUrl("niri-binds.sh").toString().replace(/^file:\/\//, "")), slotMod.value.trim() || "Mod+Alt", cycleKey.value.trim() || "Mod+C"]
      stdout: StdioCollector { id: out }
      onExited: code => {
        ok = code === 0;
        result = out.text.trim() || (ok ? "Done" : "Failed (exit " + code + ")");
      }
    }
  }
}
