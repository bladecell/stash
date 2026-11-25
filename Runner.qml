import QtQuick
import Quickshell.Io

// Runs processes with input on stdin. run(): custom commands (sh -c, 20 s limit, emits finished);
// exec(): argv + callback, used for gpg.
QtObject {
  id: root
  signal finished(var job, string out, string err, int code)

  property Component proc: Component {
    Process {
      id: p
      property var cb: null
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
        stdinEnabled = false;  // closes stdin so filters like jq/base64/gpg see EOF
      }
      onExited: c => { code = c; done(); }
      function done() {
        if (--pending === 0) {
          cb(so.text, se.text, code);
          destroy();
        }
      }
    }
  }

  function exec(args, input, cb, env) {
    proc.createObject(root, { cb: cb, input: input, command: args, environment: env || {} }).running = true;
  }

  function run(job, text, kind) {
    exec(["timeout", "20", "sh", "-c", job.cmd.command], text,
      (out, err, code) => root.finished(job, out, err, code),
      { "STASH_TEXT": text, "STASH_KIND": kind || "" });
  }
}
