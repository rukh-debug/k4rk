import QtQuick

Text {
    //  Plain text, always.
    //
    //  Text defaults to AutoText: it inspects the string and INTERPRETS it
    //  when it looks like markup. Hundreds of shell labels use this component,
    //  and much of their text is external: any application can send a
    //  notification body, window owners supply titles, and media players
    //  supply track names. A notification containing `<img src="http://…">`
    //  would cause QML to create and fetch an image instead of displaying the
    //  literal text, turning the shell into a notification-read beacon.
    //
    //  Measured: `<img src="x.png" width=400 height=60>` occupies 475x60 as
    //  markup (the image box), versus 440x19 in PlainText (the literal text).
    textFormat: Text.PlainText
    color: Theme.ink
    font.family: Theme.uiFont
    font.pixelSize: 12
}
