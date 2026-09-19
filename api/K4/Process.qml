//  An external process.
//
//  Wraps Quickshell's process and handles the awkward part: choosing how to
//  read output. k4 uses two modes, individual lines (such as one JSON sample
//  per line) or the complete output on exit. Set `porLineas` instead of
//  assembling a SplitParser or StdioCollector manually.
//
//      K4.Process {
//          command: ["python3", K4.Paths.guion("system.py")]
//          running: mirando
//          porLineas: true
//          onLinea: function (l) { ... }
//      }

import QtQuick
import Quickshell.Io as Qs

QtObject {
    id: self

    property list<string> command: []
    property bool running: false
    property string workingDirectory: ""

    // Extra environment variables. A typical example is LC_ALL=C, which
    // keeps command output in English so parsing does not depend on the
    // user's language.
    property var environment: ({})

    // Emit `linea` for each line instead of one final `salida` with everything.
    // For a process reporting while it works, this lets callers show progress
    // instead of waiting for completion.
    property bool porLineas: false

    // Allow writes to standard input. Off by default: when nobody will write,
    // leaving input open only prevents the process from learning that there
    // is nothing more to read.
    property bool entradaAbierta: false

    signal arrancado()
    signal linea(string texto)
    signal salida(string texto)
    signal terminado(int codigo)

    // Standard error is always delivered line by line.
    signal lineaError(string texto)

    function escribir(texto) { _proc.write(texto) }

    //  Request a graceful stop. Signal 2 is SIGINT, allowing file-writing
    //  processes to finish their output. Abruptly killing a recorder can
    //  leave a partial video without the index needed to open it.
    function parar(senal) { _proc.signal(senal === undefined ? 2 : senal) }

    // Use 0 while stopped: `processId` is null then, and assigning null to an
    // integer makes Qt warn on every evaluation.
    readonly property int pid: _proc.processId || 0

    // ── implementation ────────────────────────────────────────────
    property Qs.SplitParser _lineas: Qs.SplitParser {
        onRead: function (l) { self.linea(l) }
    }

    property Qs.StdioCollector _todo: Qs.StdioCollector {
        onStreamFinished: self.salida(this.text)
    }

    property Qs.SplitParser _error: Qs.SplitParser {
        onRead: function (l) { self.lineaError(l) }
    }

    property Qs.Process _proc: Qs.Process {
        command: self.command
        running: self.running
        workingDirectory: self.workingDirectory
        environment: self.environment
        stdinEnabled: self.entradaAbierta
        stdout: self.porLineas ? self._lineas : self._todo
        stderr: self._error

        onStarted: self.arrancado()
        onExited: function (codigo) {
            // Reset our own flag; otherwise callers believe the process is
            // still running and never launch it again.
            self.running = false
            self.terminado(codigo)
        }
    }
}
