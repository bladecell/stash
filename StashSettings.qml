import QtQuick
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
}
