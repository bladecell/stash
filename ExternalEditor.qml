import QtQuick
import Quickshell
import Quickshell.Io

// Writes an item to a temp file in $XDG_RUNTIME_DIR (RAM-backed), opens it in the default
// editor (or a configured command), and calls back on every save.
QtObject {
  id: root
  property string command: ""   // e.g. "zeditor"; empty → $VISUAL/$EDITOR in a terminal, else xdg-open
  readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/stash-edit"
  property int counter: 0

  property Component _watcher: Component {
    FileView {
      property var saveCb: null
      property string last: ""
      watchChanges: true
      printErrors: false  // first read races the initial write
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

  property var secrets: []  // watchers of decrypted items; dropped and their files removed on lock

  function open(text, ext, onSave, secret) {
    const path = dir + "/item-" + Date.now() + "-" + (++counter) + "." + (ext || "txt");
    const w = _watcher.createObject(root, { path: path, last: text, saveCb: onSave, blockLoading: true });
    if (secret)
      secrets.push(w);
    w.setText(text);
    // Default: terminal editors ($VISUAL/$EDITOR) need a terminal; xdg-open would start them headless.
    // Secrets: vim/nvim without swap or shada files, so no plaintext copy lands on disk.
    const fallback = 't=$(command -v ghostty || command -v alacritty || command -v kitty || command -v foot); e=${VISUAL:-$EDITOR}; '
      + (secret ? 'case "${e##*/}" in vim|nvim) e="$e -n -i NONE";; esac; ' : '')
      + 'if [ -n "$t" ] && [ -n "$e" ]; then exec "$t" -e $e "$1"; else exec xdg-open "$1"; fi';
    // short delay so FileView has flushed the file before the editor reads it
    const cmd = ["sh", "-c", "sleep 0.2; " + (command.trim() ? command + ' "$1"' : fallback), "sh", path];
    launch.createObject(root, { command: cmd }).running = true;
  }

  function forgetSecrets() {
    for (const w of secrets) {
      Quickshell.execDetached(["rm", "-f", w.path]);
      w.destroy();
    }
    secrets = [];
  }

  property Component launch: Component {
    Process {
      onExited: destroy()
    }
  }

  // Leftovers from a previous session may hold secrets; clear them on start.
  Component.onCompleted: Quickshell.execDetached(["sh", "-c", "rm -rf \"$1\" && mkdir -m 700 \"$1\"", "sh", dir])
}
