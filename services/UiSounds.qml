pragma Singleton

import QtQuick
import QtMultimedia

QtObject {
    id: sounds

    readonly property bool available: Settings.cargado && Settings.uiSoundsEnabled
        && Settings.uiSoundVolume > 0 && !!Audio.salidaActiva
        && !!Audio.salidaActiva.audio && !Audio.muted && Audio.volume > 0
    readonly property real gain: Math.max(0, Math.min(100, Settings.uiSoundVolume)) / 100

    property MediaDevices _devices: MediaDevices { id: devices }

    // Keep both samples resident. No process launch or decode on each interaction.
    property SoundEffect _clickSound: SoundEffect {
        id: clickSound
        audioDevice: devices.defaultAudioOutput
        source: Qt.resolvedUrl("../assets/sounds/click.wav")
        volume: sounds.gain
    }
    property SoundEffect _tickSound: SoundEffect {
        id: tickSound
        audioDevice: devices.defaultAudioOutput
        source: Qt.resolvedUrl("../assets/sounds/tick.wav")
        volume: sounds.gain * 0.55
    }

    // Drop extra ticks instead of queuing them after the user stops dragging.
    property Timer _tickCooldown: Timer { id: tickCooldown; interval: 80 }

    function click() {
        if (!available || clickSound.status !== SoundEffect.Ready) return
        tickSound.stop()
        clickSound.play()
        tickCooldown.restart()
    }

    function tick() {
        if (!available || tickCooldown.running || tickSound.status !== SoundEffect.Ready) return
        tickSound.play()
        tickCooldown.start()
    }

    onAvailableChanged: if (!available) {
        clickSound.stop()
        tickSound.stop()
        tickCooldown.stop()
    }
}
