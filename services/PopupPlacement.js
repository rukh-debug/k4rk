// Screen-local allocation shared by independent plugin islands and notices.
// Corners are ordered clockwise, with stable ties and a least-overlap fallback.
function rectangle(placement, width, height, screenWidth, screenHeight) {
    const freeX = Math.max(0, screenWidth - width)
    const freeY = Math.max(0, screenHeight - height)
    const fraction = Math.max(0, Math.min(1, placement.align / 100))
    return {
        x: placement.side === "left" ? 0 : placement.side === "right" ? freeX : freeX * fraction,
        y: placement.side === "top" ? 0 : placement.side === "bottom" ? freeY : freeY * fraction,
        width: width, height: height, side: placement.side, align: placement.align
    }
}

function overlap(rect, occupied, clearance) {
    let area = 0
    for (let i = 0; i < occupied.length; ++i) {
        const other = occupied[i]
        if (other.width <= 0 || other.height <= 0)
            continue
        area += Math.max(0, Math.min(rect.x + rect.width, other.x + other.width + clearance)
                           - Math.max(rect.x, other.x - clearance))
              * Math.max(0, Math.min(rect.y + rect.height, other.y + other.height + clearance)
                           - Math.max(rect.y, other.y - clearance))
    }
    return area
}

function choose(request, occupied, clearance, previous) {
    const preferred = request.placement
    const make = function (placement) {
        return rectangle(placement, request.width, request.height,
                         request.screenWidth, request.screenHeight)
    }
    // Keep an allocated corner until it is obstructed or the request changes.
    if (previous && overlap(previous, occupied, clearance) === 0)
        return previous
    const home = make(preferred)
    if (overlap(home, occupied, clearance) === 0)
        return home

    const corners = [
        { side: "top", align: 0 }, { side: "top", align: 100 },
        { side: "bottom", align: 100 }, { side: "bottom", align: 0 }
    ]
    // For a non-corner position, begin at the next corner along its edge.
    let start = preferred.side === "top" ? 1 : preferred.side === "right" ? 2
              : preferred.side === "bottom" ? 3 : 0
    if (preferred.align <= 0.5)
        start = preferred.side === "top" || preferred.side === "left" ? 0
              : preferred.side === "right" ? 1 : 3
    else if (preferred.align >= 99.5)
        start = preferred.side === "top" ? 1 : preferred.side === "left" ? 3 : 2

    let best = null
    let least = Infinity
    for (let i = 0; i < 4; ++i) {
        const candidate = make(corners[(start + i) % 4])
        const area = overlap(candidate, occupied, clearance)
        if (area < least) {
            best = candidate
            least = area
        }
        if (area === 0)
            break
    }
    return best
}
