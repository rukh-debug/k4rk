pragma Singleton

import QtQuick

// Fixed interaction cues, governed by the host's UI sound preferences.
QtObject {
    function click() { if (Puente.feedback) Puente.feedback.click() }
    function tick() { if (Puente.feedback) Puente.feedback.tick() }
}
