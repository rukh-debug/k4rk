pragma Singleton

// Unified surface registry: native host features plus dynamically loaded plugins.
//
// Native features are always-on bar chrome (pill, volume HUD, clock, player,
// notifications, control centre, sound mixer, session). Plugins are user
// enableable extensions loaded by PluginManager. Island arbitration,
// placement, applications and cross-reference injection read from here so
// both ownership types behave as one ordered surface list.

import QtQuick
import Quickshell

Singleton {
    id: registry

    // The fallback pill id, said once. Every "is this the pill?" check
    // reads this instead of a mistypable string literal.
    readonly property string pillId: "idle"

    // Stable host order. Arbitration uses strict greater-than, so the first
    // surface wins equal-priority ties. User plugins always sort after all
    // shipped modules regardless of any manifest field.
    readonly property var nativeOrder: [
        "idle", "volume", "sound", "clock", "player", "toast", "panel",
        "launcher", "openwebui", "settings", "clipboard", "system", "keys",
        "session", "apps", "terminal", "packages", "ssh", "agents",
        "hyprland-submap", "tray"
    ]

    // Native metadata for icons, applications and placement. Plugin metadata
    // continues to come from PluginManager.catalogo.
    readonly property var nativeMetadata: ({
        "idle": { title: "Pill", icon: "0xF0765" },
        "volume": { title: "Volume", icon: "0xF057E" },
        "sound": { title: "Sound", icon: "0xF02CB" },
        "clock": { title: "Clock", icon: "0xF0954" },
        "player": { title: "Player", icon: "0xF0387" },
        "toast": { title: "Notifications", icon: "0xF0369" },
        "panel": { title: "Control centre", icon: "0xF0492" },
        "session": { title: "Session", icon: "0xF0425", application: true },
        "tray": { title: "Tray", icon: "0xF1296" }
    })

    // Reserved native ids and IPC targets. tools/plugins.py reads the same
    // lists from features/catalog.json; they are duplicated here so the
    // running bar does not need to parse JSON.
    readonly property var nativeIds: [
        "idle", "volume", "sound", "clock", "player", "toast", "panel",
        "session", "tray"
    ]
    readonly property var nativeIpcTargets: [
        "k4", "k4.panel", "k4.sound", "k4.session", "k4.tray"
    ]

    // Live native instances, in nativeOrder. Each entry is added as its
    // feature migrates; TrayIsland was already native.
    readonly property var nativeInstances: [IdleIsland, VolumeIsland, SoundIsland, ClockIsland, PlayerIsland, ToastIsland, PanelIsland, SessionIsland, TrayIsland]

    function nativeInstance(id) {
        for (let i = 0; i < nativeInstances.length; ++i) {
            if (nativeInstances[i] && nativeInstances[i].name === id)
                return nativeInstances[i]
        }
        return null
    }

    // Unified lookup: native first, then dynamically loaded plugins.
    function instance(id) {
        const n = nativeInstance(id)
        if (n)
            return n
        return PluginManager.instancia(id)
    }

    // Combined arbitration list in stable host order, then user plugins.
    // While migration is in progress most ids still resolve to plugins;
    // natives that already moved resolve to their singleton and the plugin
    // copy is skipped once its catalog entry is gone.
    readonly property var surfaces: {
        const byId = {}
        const plugins = PluginManager.instancias
        for (let i = 0; i < plugins.length; ++i) {
            if (plugins[i] && plugins[i].name)
                byId[plugins[i].name] = plugins[i]
        }
        for (let j = 0; j < nativeInstances.length; ++j) {
            const n = nativeInstances[j]
            if (n && n.name)
                byId[n.name] = n
        }
        const ordered = []
        for (let k = 0; k < nativeOrder.length; ++k) {
            const hit = byId[nativeOrder[k]]
            if (hit) {
                ordered.push(hit)
                delete byId[nativeOrder[k]]
            }
        }
        // Any remaining plugin (user-installed) sorts after shipped modules.
        for (let m = 0; m < plugins.length; ++m) {
            const p = plugins[m]
            if (p && ordered.indexOf(p) < 0 && nativeInstances.indexOf(p) < 0)
                ordered.push(p)
        }
        // Natives not in nativeOrder (should not happen) go last but
        // before user leftovers are already handled; keep them visible.
        for (let n2 = 0; n2 < nativeInstances.length; ++n2) {
            const nn = nativeInstances[n2]
            if (nn && ordered.indexOf(nn) < 0)
                ordered.push(nn)
        }
        return ordered
    }

    // Every live surface that can be placed: colocable plugins plus natives.
    readonly property var placeableSurfaces: {
        const out = []
        const list = surfaces
        for (let i = 0; i < list.length; ++i) {
            const p = list[i]
            if (p && p.colocable)
                out.push({ id: p.name, nombre: p.title || p.name,
                           ipc: p.summonCommand || "" })
        }
        return out
    }

    // Combined icon lookup for launcher fallback and settings rows.
    function iconFor(id) {
        const meta = nativeMetadata[id]
        if (meta && meta.icon)
            return { imagen: "", glifo: parseInt(meta.icon, 16) }
        if (typeof PluginManager !== "undefined" && PluginManager.iconoDe)
            return PluginManager.iconoDe(id)
        return { imagen: "", glifo: 0xF06A5 }
    }

    // Combined application list: native session plus plugin applications.
    // Native entries sort in nativeOrder; plugin entries keep catalog order.
    readonly property var aplicaciones: {
        const out = []
        const seen = {}
        // Native applications first in stable order.
        for (let i = 0; i < nativeOrder.length; ++i) {
            const id = nativeOrder[i]
            const meta = nativeMetadata[id]
            if (!meta || meta.application !== true)
                continue
            const inst = nativeInstance(id) || PluginManager.instancia(id)
            // During transition the plugin copy still provides state.
            const pluginApp = PluginManager.aplicaciones.find(function (a) {
                return a.id === id
            })
            out.push({
                id: id,
                nombre: (meta.title || id),
                imagen: pluginApp ? pluginApp.imagen : "",
                glifo: meta.icon ? parseInt(meta.icon, 16) : 0xF0431,
                externo: false,
                habilitado: true,
                disponible: pluginApp ? pluginApp.disponible : !!inst
            })
            seen[id] = true
        }
        const plugins = PluginManager.aplicaciones
        for (let j = 0; j < plugins.length; ++j) {
            if (!seen[plugins[j].id])
                out.push(plugins[j])
        }
        return out
    }

    function abrirAplicacion(id) {
        const n = nativeInstance(id)
        if (n) {
            if (typeof n.abrir === "function") {
                n.abrir()
                return true
            }
            if (typeof n.toggle === "function") {
                n.toggle()
                return true
            }
            return false
        }
        return PluginManager.abrirAplicacion(id)
    }

    // Cross-reference handout across ownership types. A component declaring
    // `property var <id>` receives the live instance or null when absent.
    // Runs after every plugin creation and after native boot.
    function repartir() {
        const all = surfaces
        const byId = {}
        for (let i = 0; i < all.length; ++i) {
            if (all[i] && all[i].name)
                byId[all[i].name] = all[i]
        }
        const ids = Object.keys(byId)
        for (let a = 0; a < all.length; ++a) {
            const obj = all[a]
            if (!obj)
                continue
            for (let b = 0; b < ids.length; ++b) {
                const otro = ids[b]
                if (otro === obj.name || !(otro in obj))
                    continue
                const destino = byId[otro] || null
                if (obj[otro] !== destino)
                    obj[otro] = destino
            }
        }
    }

    // Native view-load errors surface through host health instead of the
    // plugin error map. Keys are native ids, values are error strings.
    property var erroresNativos: ({})

    function reportarErrorNativo(id, motivo) {
        const d = Object.assign({}, erroresNativos)
        if (!motivo)
            delete d[id]
        else
            d[id] = String(motivo)
        erroresNativos = d
    }

    function hostStatus() {
        const natives = []
        for (let i = 0; i < nativeOrder.length; ++i) {
            const id = nativeOrder[i]
            // Only report ids that have migrated or are tray; plugins still
            // report through pluginStatus during transition.
            const inst = nativeInstance(id)
            if (!inst) {
                if (nativeIds.indexOf(id) >= 0 && id !== "tray")
                    continue
                continue
            }
            natives.push({ id: id, ready: true,
                           error: erroresNativos[id] || "" })
        }
        // Native ids with a recorded error but no instance (failed root).
        for (const failed in erroresNativos) {
            let found = false
            for (let k = 0; k < natives.length; ++k) {
                if (natives[k].id === failed) {
                    found = true
                    break
                }
            }
            if (!found)
                natives.push({ id: failed, ready: false,
                               error: erroresNativos[failed] || "error" })
        }
        const plugins = PluginManager.catalogo.map(function (m) {
            return { id: m.id,
                     enabled: PluginManager.estaHabilitado(m.id),
                     error: PluginManager.errores[m.id] || "" }
        })
        return JSON.stringify({ native: natives, plugins: plugins })
    }
}
