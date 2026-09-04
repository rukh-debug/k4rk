//  A terminal session inside the bar.
//
//  It is a `k4term-isla` and what it takes to talk to it: commands go
//  over as JSON lines and it answers frames with the grid already
//  resolved. Nothing more — who is shown, in what order and with which
//  keys is the plugin's business.
//
//  It lives in its own file precisely so there can be SEVERAL: this
//  used to live loose inside the plugin, and that is why only one
//  could exist.

import QtQuick
import K4 as K4
import "../../services"

QtObject {
    id: sesion

    //  A session that already exists waiting on that socket: it comes
    //  from a window giving it back. With this the binary opens no
    //  shell — it adopts the one there, with whatever was running
    //  inside it.
    property string heredar: ""

    //  Which server it is connected to right now, if any. The plugin
    //  notes it when sending the `ssh` and erases it when that command
    //  ends.
    property string conectadoA: ""

    //  A number that does not repeat, to be able to refer to it even
    //  when others close in between. It is not called `id` because in
    //  QML that word is taken.
    property int numero: 0

    //  The last thing it sent.
    property var marco: null
    property int estela: 8
    //  Whether the binary on the other side can type passwords. It
    //  says so at startup; an older one says nothing and stays
    //  false.
    property bool sabeClaves: false
    property string fuente: "MesloLGS Nerd Font Mono"
    property int cuerpo: 13

    //  What to call it in the selector: whatever the application
    //  inside says, and if it has said nothing, where it is.
    readonly property string titulo: marco && marco.titulo ? marco.titulo : ""
    readonly property string cwd: marco && marco.cwd ? marco.cwd : ""

    //  Asked and answered: the plugin uses it to know where to open a
    //  window with this same session inside.
    signal donde(string ruta)

    //  What is cooking in here. The session reports facts; what is
    //  shown and when is the plugin's call, the only one knowing
    //  whether you are watching this terminal right now.
    signal trabajo(string estado, string mandato, int salida, int segundos)
    signal campana(string titulo)

    //  What the application inside asked to copy (OSC 52). There is
    //  no clipboard here: the bar has it, so it is passed to it.
    signal portapapeles(string texto)

    //  A piece of history asked for with `texto_de`. It comes back
    //  with the reason it was asked for, which is what tells copying
    //  apart from sending to a note — otherwise the answer would not
    //  say what it came for.
    signal texto(string contenido, string motivo)

    //  Where a search landed, and whether it landed on anything.
    signal buscado(bool hay, int fila)

    //  A loose message for the user: in here there is no room to say
    //  «saved» without covering itself.
    signal aviso(string texto)

    //  «There stays the session»: through that socket a window can
    //  take it away. Until somebody picks it up, nothing has been let
    //  go here.
    signal emigrando(string socket)

    //  It died on its own —an `exit`, the shell closed—, so the
    //  plugin takes it off the list instead of leaving a dead slot.
    signal difunta()

    property bool viva: true

    function mandar(orden) {
        if (viva)
            proceso.escribir(JSON.stringify(orden) + "\n")
    }

    property K4.Process proceso: K4.Process {
        command: sesion.heredar ? ["k4term-isla", "--heredar", sesion.heredar]
                                : ["k4term-isla"]
        running: sesion.viva
        porLineas: true
        entradaAbierta: true

        onLinea: function (linea) {
            let m = null
            try {
                m = JSON.parse(linea)
            } catch (e) {
                return
            }
            if (!m)
                return
            if (m.que === "marco") {
                sesion.marco = m
            } else if (m.que === "config") {
                //  `estela` without a guard was the only field
                //  without one: a k4term that does not send it leaves
                //  `undefined`, which becomes 0 and kills the cursor
                //  trail without a word.
                if (m.estela !== undefined)
                    sesion.estela = m.estela
                if (m.fuente)
                    sesion.fuente = m.fuente
                if (m.tamano)
                    sesion.cuerpo = Math.round(m.tamano)
                //  What the binary on the other side can do. A
                //  k4term older than passwords does not send this,
                //  and then none are sent to it: better said than
                //  left waiting for a password nobody will type.
                sesion.sabeClaves = m.claves === true
            } else if (m.que === "donde") {
                sesion.donde(m.ruta || "")
            } else if (m.que === "trabajo") {
                sesion.trabajo(m.estado, m.mandato || "", m.salida || 0, m.segundos || 0)
            } else if (m.que === "campana") {
                sesion.campana(m.titulo || "")
            } else if (m.que === "portapapeles") {
                sesion.portapapeles(m.texto || "")
            } else if (m.que === "texto") {
                sesion.texto(m.texto || "", m.motivo || "")
            } else if (m.que === "buscado") {
                sesion.buscado(m.hay === true, m.fila || 0)
            } else if (m.que === "aviso") {
                sesion.aviso(m.texto || "")
            } else if (m.que === "emigrando") {
                sesion.emigrando(m.socket || "")
            }
        }

        onTerminado: {
            //  Dead having painted NOTHING: either the binary is no
            //  longer there, or it does not start. In both cases the
            //  answer is the same —look again at what is installed—,
            //  and so the plugin turns itself off with its reason
            //  instead of trying over and over.
            if (!sesion.marco)
                Consola.revisar()
            sesion.viva = false
            sesion.marco = null
            sesion.difunta()
        }
    }
}
