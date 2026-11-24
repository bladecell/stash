import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
  id: root
  pluginId: "stash"

  ToggleSetting {
    settingKey: "closeOnFocusLoss"
    label: "Close when another window is focused"
    description: "Hide Stash as soon as focus moves to a different window"
    defaultValue: false
  }

  StringSetting {
    settingKey: "editorCommand"
    label: "External editor command"
    description: "Used by Ctrl+O; the file path is appended. Empty runs $VISUAL or $EDITOR in your terminal"
    placeholder: "e.g. zeditor"
    defaultValue: ""
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
