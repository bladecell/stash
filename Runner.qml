import QtQuick
import Quickshell.Io

// Runs a shell command with the item text on stdin and in $STASH_TEXT; 20 s limit.
QtObject {
  id: root
  signal finished(var job, string out, string err, int code)

  property Component proc: Component {
    Process {
      id: p
      property var job
      property string input: ""
      property int code: 0
      property int pending: 2  // exit + stdout end
      stdinEnabled: true
      stdout: StdioCollector {
        id: so
        onStreamFinished: p.done()
      }
      stderr: StdioCollector { id: se }
      onStarted: {
        write(input);
        stdinEnabled = false;  // closes stdin so filters like jq/base64 see EOF
      }
      onExited: c => { code = c; done(); }
      function done() {
        if (--pending === 0) {
          root.finished(job, so.text, se.text, code);
          destroy();
        }
      }
    }
  }

  function run(job, text, kind) {
    proc.createObject(root, {
      job: job,
      input: text,
      command: ["timeout", "20", "sh", "-c", job.cmd.command],
      environment: { "STASH_TEXT": text, "STASH_KIND": kind || "" }
    }).running = true;
  }
}
