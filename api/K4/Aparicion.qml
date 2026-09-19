//  Fade in rather than appear abruptly. Wrap anything that should enter
//  smoothly when your plugin takes the island.

import QtQuick

Item {
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
}
