import QtQuick
import QtTest
import QtMultimedia
import K4 as K4
import "../services" as Services

Item {
    id: fixture
    TestCase {
        name: "UiSounds"
        when: fixture.Window.window !== null
        property var clickSound
        property var tickSound
        property var cooldown

        function initTestCase() {
            verify(Services.UiSounds.available)
            clickSound = Services.UiSounds._clickSound
            tickSound = Services.UiSounds._tickSound
            cooldown = Services.UiSounds._tickCooldown
            verify(clickSound !== null && tickSound !== null && cooldown !== null)
            // Exercise playback without making the test suite audible.
            clickSound.muted = true
            tickSound.muted = true
            tryCompare(clickSound, "status", SoundEffect.Ready, 5000)
            tryCompare(tickSound, "status", SoundEffect.Ready, 5000)
            K4.Puente.feedback = Services.UiSounds
        }

        function init() {
            Services.Settings.uiSoundsEnabled = false
            Services.Settings.cargado = true
            Services.Settings.uiSoundVolume = 35
            Services.Audio.salidaActiva = { audio: {} }
            Services.Audio.muted = false
            Services.Audio.volume = 50
            Services.Settings.uiSoundsEnabled = true
            verify(Services.UiSounds.available)
        }

        function test_clickAndTickPlayback() {
            K4.Feedback.click()
            compare(clickSound.playing, true)
            compare(tickSound.playing, false)
            tryCompare(clickSound, "playing", false)
            tryCompare(cooldown, "running", false)
            K4.Feedback.tick()
            compare(tickSound.playing, true)
            tryCompare(tickSound, "playing", false)
        }

        function test_tickBurstIsDropped() {
            Services.UiSounds.tick()
            compare(tickSound.playing, true)
            tickSound.stop()
            for (let i = 0; i < 100; ++i) Services.UiSounds.tick()
            compare(tickSound.playing, false)
            compare(cooldown.running, true)
            wait(120)
            compare(tickSound.playing, false, "No delayed burst after cooldown")
            Services.UiSounds.tick()
            compare(tickSound.playing, true)
        }

        function test_clickReplacesTick() {
            Services.UiSounds.tick()
            Services.UiSounds.click()
            compare(tickSound.playing, false)
            compare(clickSound.playing, true)
            Services.UiSounds.tick()
            compare(tickSound.playing, false)
        }

        function test_silentStates_data() {
            return [
                { tag: "disabled", object: Services.Settings, key: "uiSoundsEnabled", value: false },
                { tag: "settings-loading", object: Services.Settings, key: "cargado", value: false },
                { tag: "feedback-zero", object: Services.Settings, key: "uiSoundVolume", value: 0 },
                { tag: "muted", object: Services.Audio, key: "muted", value: true },
                { tag: "system-zero", object: Services.Audio, key: "volume", value: 0 },
                { tag: "no-output", object: Services.Audio, key: "salidaActiva", value: null },
                { tag: "output-not-ready", object: Services.Audio, key: "salidaActiva", value: {} }
            ]
        }
        function test_silentStates(data) {
            Services.UiSounds.click()
            data.object[data.key] = data.value
            compare(Services.UiSounds.available, false)
            compare(clickSound.playing, false, "Disabling feedback stops active playback")
            Services.UiSounds.click()
            Services.UiSounds.tick()
            compare(clickSound.playing, false)
            compare(tickSound.playing, false)
            compare(cooldown.running, false)
        }

        function test_gainAndDefaultOutput() {
            Services.Settings.uiSoundVolume = 60
            fuzzyCompare(clickSound.volume, 0.6, 0.001)
            fuzzyCompare(tickSound.volume, 0.33, 0.001)
            Services.Settings.uiSoundVolume = 150
            compare(clickSound.volume, 1)
            Services.Settings.uiSoundVolume = -5
            compare(clickSound.volume, 0)
            compare(clickSound.audioDevice.id, tickSound.audioDevice.id)
            verify(clickSound.audioDevice.isDefault)
        }

        function cleanup() {
            if (qtest_results.failed) console.error("FAIL! " + qtest_results.functionName + " " + qtest_results.dataTag)
            Services.Settings.uiSoundsEnabled = false
        }
        function cleanupTestCase() {
            K4.Puente.feedback = null
            const failures = qtest_results.failCount
            console.log("UI sound service: " + qtest_results.passCount + " passed, " + failures + " failed")
            Qt.callLater(function () { Qt.exit(failures ? 1 : 0) })
        }
    }
}
