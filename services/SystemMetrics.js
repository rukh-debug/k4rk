.pragma library

// Pure parsers: kernel counters stay separate from the rendering and polling.
function cpu(text) {
    const lines = text.trim().split("\n")
    const values = lines[0].trim().split(/\s+/).slice(1, 9).map(Number)
    if (values.length < 4 || values.some(v => !isFinite(v))) return null
    // guest and guest_nice are already included in user and nice.
    return { total: values.reduce((a, b) => a + b, 0), idle: values[3] + (values[4] || 0),
        threads: lines.filter(l => /^cpu\d+\s/.test(l)).length }
}

function cpuPercent(previous, current) {
    if (!previous || !current || current.total <= previous.total) return -1
    const idle = current.idle - previous.idle
    if (idle < 0) return -1
    return Math.max(0, Math.min(100, 100 * (1 - idle / (current.total - previous.total))))
}

function memory(text) {
    const data = {}
    text.split("\n").forEach(line => {
        const parts = line.split(":")
        if (parts.length === 2) data[parts[0]] = parseFloat(parts[1]) * 1024
    })
    if (!(data.MemTotal > 0) || !isFinite(data.MemAvailable)) return null
    return { total: data.MemTotal, used: Math.max(0, data.MemTotal - data.MemAvailable),
        swapTotal: data.SwapTotal || 0, swapUsed: Math.max(0, (data.SwapTotal || 0) - (data.SwapFree || 0)) }
}

function defaultInterface(ipv4, ipv6) {
    const routes = []
    ipv4.trim().split("\n").slice(1).forEach(line => {
        const p = line.trim().split(/\s+/)
        if (p.length >= 8 && p[1] === "00000000" && p[7] === "00000000" && (parseInt(p[3], 16) & 1)
                && !(parseInt(p[3], 16) & 0x200))
            routes.push({ name: p[0], metric: Number(p[6]) })
    })
    if (!routes.length) ipv6.trim().split("\n").forEach(line => {
        const p = line.trim().split(/\s+/)
        if (p.length >= 10 && /^0{32}$/.test(p[0]) && p[1] === "00" && p[9] !== "lo"
                && (parseInt(p[8], 16) & 1) && !(parseInt(p[8], 16) & 0x200))
            routes.push({ name: p[9], metric: parseInt(p[5], 16) })
    })
    routes.sort((a, b) => a.metric - b.metric || a.name.localeCompare(b.name))
    return routes.length ? routes[0].name : ""
}

function network(text, name) {
    for (const line of text.split("\n")) {
        const cut = line.indexOf(":")
        if (cut < 0 || line.slice(0, cut).trim() !== name) continue
        const fields = line.slice(cut + 1).trim().split(/\s+/)
        const rx = Number(fields[0]), tx = Number(fields[8])
        if (isFinite(rx) && isFinite(tx)) return { name: name, rx: rx, tx: tx }
    }
    return null
}

function rates(previous, current, dt) {
    if (!previous || !current || previous.name !== current.name || dt <= 0 || dt > 5
            || current.rx < previous.rx || current.tx < previous.tx) return null
    return { rx: (current.rx - previous.rx) / dt, tx: (current.tx - previous.tx) / dt }
}
