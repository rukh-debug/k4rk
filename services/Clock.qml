pragma Singleton

// One clock for the whole bar: two SystemClock instances would poll twice.

import QtQuick
import Quickshell

Singleton {
    readonly property date date: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
