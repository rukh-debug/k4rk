pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One shared worker, bounded cache, and one outstanding job per reader.
Singleton {
    id: engine
    property int nextId: 0
    property bool ready: false
    property bool busy: false
    property var queue: []
    property var cache: ({})
    property var cacheKeys: []
    property var active: null
    signal rendered(int reader, int revision, var blocks)
    signal failed(int reader, int revision)

    function request(reader, revision, text, palette) {
        const key = JSON.stringify([text, palette])
        if (cache[key] !== undefined) {
            rendered(reader, revision, cache[key])
            return
        }
        queue = queue.filter(function (job) { return job.id !== reader })
        queue.push({ id: reader, revision: revision, text: text, palette: palette, key: key })
        worker.running = true
        pump()
    }

    function release(reader) {
        queue = queue.filter(function (job) { return job.id !== reader })
    }

    function pump() {
        if (!ready || busy || !queue.length) return
        active = queue.shift()
        busy = true
        worker.write(JSON.stringify({ id: active.id, revision: active.revision,
                                     text: active.text, palette: active.palette }) + "\n")
    }

    Process {
        id: worker
        command: ["python3", Qt.resolvedUrl("../../../tools/markdown_render.py").toString().replace(/^file:\/\//, "")]
        stdinEnabled: true
        onStarted: { engine.ready = true; engine.pump() }
        onExited: {
            engine.ready = false
            engine.busy = false
            if (engine.active) engine.failed(engine.active.id, engine.active.revision)
            for (const job of engine.queue) engine.failed(job.id, job.revision)
            engine.queue = []
            engine.active = null
        }
        stdout: SplitParser {
            onRead: function (line) {
                try {
                    const result = JSON.parse(line)
                    if (result.error) {
                        engine.failed(result.id, result.revision)
                    } else {
                        // Large streams are rendered but not retained in the cache.
                        if (engine.active && engine.active.text.length < 100000) {
                            const key = engine.active.key
                            engine.cache[key] = result.blocks
                            engine.cacheKeys.push(key)
                            while (engine.cacheKeys.length > 24)
                                delete engine.cache[engine.cacheKeys.shift()]
                        }
                        engine.rendered(result.id, result.revision, result.blocks)
                    }
                } catch (error) {
                    if (engine.active) engine.failed(engine.active.id, engine.active.revision)
                }
                engine.busy = false
                engine.active = null
                engine.pump()
            }
        }
    }
}
