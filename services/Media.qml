pragma Singleton

//  Active player (MPRIS) and cover-art resolution.
//
//  Browsers may omit mpris:artUrl but publish xesam:url, which is enough
//  to construct a thumbnail. Each fallback is tried only if the previous
//  step returned nothing.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: media

    readonly property var activePlayer: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players.length > 0 ? players[0] : null
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.isPlaying

    // Some players (Firefox/Zen) never publish mpris:length, so hide their
    // timeline. Delay hiding it so a track change, with length briefly at
    // zero, does not make the island jump.
    readonly property bool hasTimelineRaw: hasPlayer && activePlayer.lengthSupported && activePlayer.length > 0
    property bool hasTimeline: false

    onHasTimelineRawChanged: {
        if (hasTimelineRaw)
            hasTimeline = true
        else
            timelineDropTimer.restart()
    }

    Component.onCompleted: hasTimeline = hasTimelineRaw

    // ── position polling ─────────────────────────────────────────
    // MPRIS does not notify position changes, so query it only while a view
    // is watching. Views register on creation and unregister on destruction,
    // avoiding polling while the island is folded.
    property int positionWatchers: 0

    function watchPosition() { positionWatchers += 1 }
    function unwatchPosition() { positionWatchers = Math.max(0, positionWatchers - 1) }

    function trackUrl(player) {
        if (!player || !player.metadata)
            return ""

        const url = player.metadata["xesam:url"]
        return url ? String(url) : ""
    }

    function coverFor(player) {
        if (!player)
            return ""

        if (player.trackArtUrl && player.trackArtUrl.length > 0)
            return player.trackArtUrl

        const url = trackUrl(player)
        if (url.length === 0)
            return ""

        const yt = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/)
        if (yt)
            return "https://i.ytimg.com/vi/" + yt[1] + "/mqdefault.jpg"

        const tw = url.match(/^https?:\/\/(?:www\.)?twitch\.tv\/([A-Za-z0-9_]+)\/?(?:\?.*)?$/)
        if (tw && ["videos", "directory", "settings", "downloads", "subscriptions", "u", "p"].indexOf(tw[1].toLowerCase()) === -1)
            return "https://static-cdn.jtvnw.net/previews-ttv/live_user_" + tw[1].toLowerCase() + "-440x248.jpg"

        return ""
    }

    // Last fallbacks before the music-note glyph: site favicon, then app icon.
    function faviconFor(player) {
        const host = trackUrl(player).match(/^https?:\/\/([^\/]+)/)
        return host ? "https://" + host[1] + "/favicon.ico" : ""
    }

    function appIconFor(player) {
        return player && player.desktopEntry ? Quickshell.iconPath(player.desktopEntry, true) : ""
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0)
            seconds = 0

        const total = Math.floor(seconds)
        const mins = Math.floor(total / 60)
        const secs = total % 60
        return mins + ":" + (secs < 10 ? "0" + secs : secs)
    }

    function seekTo(fraction) {
        if (!hasPlayer)
            return

        const player = activePlayer
        if (!player.canSeek || !player.positionSupported || !(player.length > 0))
            return

        player.position = Math.max(0, Math.min(1, fraction)) * player.length
    }

    function siguiente() {
        if (activePlayer && activePlayer.canGoNext)
            activePlayer.next()
    }

    function anterior() {
        if (activePlayer && activePlayer.canGoPrevious)
            activePlayer.previous()
    }

    function togglePlaying() {
        if (hasPlayer)
            activePlayer.togglePlaying()
    }

    Timer {
        interval: 500
        repeat: true
        running: media.isPlaying && media.positionWatchers > 0
        onTriggered: media.activePlayer.positionChanged()
    }

    Timer {
        id: timelineDropTimer
        interval: 1500
        onTriggered: media.hasTimeline = media.hasTimelineRaw
    }
}
