//  Is there a new k4?
//
//  The updater is `./instalar` and has been there from the start —it
//  does the `git pull`, goes over packages and shortcuts and offers
//  to restart the bar—, but the bar never mentioned it: you learned
//  there was a new version if it occurred to you to run it by hand.
//  This is the missing half: looking, and saying it where everything
//  else is looked at.
//
//  THREE things are found out and all three are needed:
//
//   · which commit you are on, which is what answers «what version
//     do I have?» —until now shown nowhere—;
//   · how many commits `origin` is ahead, which is the real news;
//   · and whether you have uncommitted changes. This last one is not
//     a detail: with a dirty tree `./instalar` does NOT touch the
//     code on purpose —losing somebody's work to an «update» is
//     exactly what must not happen— so showing «there is news»
//     without saying that is sending somebody to press a button that
//     will do nothing, and without explaining why.
//
//  All in ONE process and not four: they are four chained git
//  commands, each with its possible failure, and coordinating them
//  from QML is four `onSalida` with a state machine in between. In
//  `sh` they are six lines and each one's failure is answered right
//  there.

import QtQuick
import K4 as K4

QtObject {
    id: version

    //  What has been found out.
    //
    //  `detras` at -1 means «not known yet», which is NOT the same
    //  as 0: at zero one says «up to date» and at -1 one says
    //  nothing, which is the honest thing while it could not be
    //  looked at.
    property string commit: ""
    property int detras: -1
    property bool sucio: false

    //  And why it is not known, when it is not. Empty means «known».
    //
    //   "no-git"      not a git clone: installed by hand or unzipped.
    //   "no-remote"   the branch tracks nothing, so there is nothing to compare against.
    //   "no-network"  nothing could be fetched. Whatever is shown then comes
    //                 from the last time there was network, and that
    //                 must be said.
    property string pega: ""

    property bool mirando: false

    readonly property bool hayNovedad: version.detras > 0

    //  When it was last looked at, so it does not hit the network
    //  every time Settings opens. In memory and not saved to disk:
    //  on a bar restart, looking again is exactly what is wanted,
    //  not what is to be avoided.
    property double ultima: 0
    readonly property int gracia: 10 * 60 * 1000

    function mirar(forzando) {
        if (version.mirando)
            return
        if (!forzando && version.ultima > 0
                && Date.now() - version.ultima < version.gracia)
            return
        version.mirando = true
        ojeada.running = true
    }

    //  And updating is launching the installer where it can be seen.
    //
    //  In a terminal and not in a silent process, on purpose:
    //  `./instalar` asks —whether to restart the bar, whether to
    //  install what is missing— and may ask the package manager's
    //  password. With k4term it moreover comes out INSIDE the
    //  island, so updating the bar is seen in the bar itself.
    function actualizar() {
        K4.Terminal.ejecutar("cd " + JSON.stringify(K4.Paths.raiz)
                             + " && ./instalar;" + K4.Terminal.cierre)
    }

    property K4.Process ojeada: K4.Process {
        //  `$0` is the name and `$1` the first argument: hence the
        //  loose "sh" between the script and the root. The same
        //  workaround dual mode uses to launch applications without
        //  inheriting the bar's directory.
        command: ["sh", "-c", [
            'cd "$1" 2>/dev/null || exit 0',
            'c=$(git rev-parse --short HEAD 2>/dev/null) || { echo hitch=no-git; exit 0; }',
            'echo "commit=$c"',
            '[ -n "$(git status --porcelain 2>/dev/null)" ] && echo dirty=1',
            //  Without a tracking branch there is nothing to compare
            //  against, and `rev-list HEAD..@{u}` would fail
            //  silently leaving a -1 with no explanation. It is
            //  asked first so the hitch can be named.
            'git rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1 || { echo hitch=no-remote; exit 0; }',
            //  And if the network fails it does NOT exit: the
            //  `rev-list` below still counts against the last thing
            //  fetched. It answers with the old count and the hitch
            //  set, which is more useful than not answering.
            'git fetch --quiet 2>/dev/null || echo hitch=no-network',
            'n=$(git rev-list --count "HEAD..@{u}" 2>/dev/null) && echo "behind=$n"'
        ].join("\n"), "sh", K4.Paths.raiz]

        //  In English, the way it parses the same on any machine.
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            let c = "", d = -1, su = false, pe = ""
            const lineas = String(texto).split("\n")
            for (let i = 0; i < lineas.length; ++i) {
                const l = lineas[i].trim()
                if (l.indexOf("commit=") === 0)
                    c = l.substring(7)
                else if (l.indexOf("behind=") === 0)
                    d = parseInt(l.substring(7), 10)
                else if (l === "dirty=1")
                    su = true
                else if (l.indexOf("hitch=") === 0)
                    pe = l.substring(6)
            }
            version.commit = c
            version.detras = isNaN(d) ? -1 : d
            version.sucio = su
            version.pega = pe
        }

        //  The stamp is set on ENDING and not on reading: a process
        //  that dies without writing anything emits no `salida`, and
        //  without a stamp the grace does not run and it would retry
        //  on every Settings opening.
        onTerminado: function (codigo) {
            version.mirando = false
            version.ultima = Date.now()
        }
    }
}
