import QtQuick
import Quickshell
import Quickshell.Io

// Writes an item to a temp file in $XDG_RUNTIME_DIR (RAM-backed), opens it in the default
// editor (or a configured command), and calls back on every save.
QtObject {
  id: root
  property string command: ""   // e.g. "zeditor --wait"; empty → xdg-open
  readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/stash-edit"
  property int counter: 0

  property Component _watcher: Component {
    FileView {
      property var saveCb: null
      property string last: ""
      watchChanges: true
      onFileChanged: reload()
      onLoaded: {
        const t = text();
        if (t !== last) {
          last = t;
          saveCb && saveCb(t);
        }
      }
    }
  }

  function open(text, ext, onSave) {
    const path = dir + "/item-" + Date.now() + "-" + (++counter) + "." + (ext || "txt");
    const w = _watcher.createObject(root, { path: path, last: text, saveCb: onSave, blockLoading: true });
    w.setText(text);
    // short delay so FileView has flushed the file before the editor reads it
    const cmd = ["sh", "-c", "sleep 0.2; " + (command.trim() || "xdg-open") + " \"$1\"", "sh", path];
    launch.createObject(root, { command: cmd }).running = true;
  }

  property Component launch: Component {
    Process {
      onExited: destroy()
    }
  }

  // Leftovers from a previous session may hold secrets; clear them on start.
  Component.onCompleted: Quickshell.execDetached(["sh", "-c", "rm -rf \"$1\" && mkdir -m 700 \"$1\"", "sh", dir])
}
