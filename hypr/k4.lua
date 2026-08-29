-- Generado por el instalador de k4. NO LO EDITES: se reescribe al actualizar.
-- Fork de rukh-debug: distribución de teclas propia (hábitos de noctalia).
--
-- Todo lo que k4 necesita de Hyprland: los atajos y el arranque.
--
-- Para revertirlo: borra este fichero y la línea `require("config.k4")` de
-- hyprland.lua. Al actualizar, el instalador puede retirar líneas antiguas de
-- k4 de tus ficheros de Hyprland; antes deja una copia *.k4.bak al lado.
--
-- OJO con los choques: la API Lua de Hyprland ACUMULA atajos — no los
-- reemplaza como hace el formato clásico con dos `bind` sobre la misma
-- tecla. Dos atajos sobre una tecla son DOS atajos vivos, no uno que gana.
-- Las teclas que la configuración de rukh ya usa (Z, C, B, G, Tab,
-- SHIFT+Space, SHIFT+E, ALT+S, CTRL+C y las XF86 de multimedia) no se atan
-- aquí. Si algo choca, se quita de este fichero — no se re-ata encima.

local mod = "SUPER"
local raiz = "@RAIZ@"

-- Las tres llamadas de IPC. `k4` es el objetivo general, que se mantiene por
-- compatibilidad; los módulos nuevos publican el suyo propio.
local k4 = "quickshell ipc -p " .. raiz .. "/shell.qml call k4 "
local captura = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.captura "
local editor = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.editor "
local apps = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.apps "
local term = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.term "
local ssh = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.ssh "

----------------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------------
-- Se lanza `arrancar` y no `quickshell` a secas a propósito: es quien pone
-- QML_IMPORT_PATH para que los plugins puedan escribir `import K4`. Lanzando
-- quickshell directamente la barra no levanta.
hl.on("hyprland.start", function()
    hl.exec_cmd(raiz .. "/arrancar --no-duplicate -d")
end)

----------------------------------------------------------------------------
-- La island
----------------------------------------------------------------------------
-- Lanzador en SUPER+D y panel en SUPER+Space: donde noctalia los tenía.
-- (El SUPER+D de arriba era «pantalla completa» en la configuración de
-- CachyOS; en la de rukh está libre.)
hl.bind(mod .. " + D",           hl.dsp.exec_cmd(k4 .. "toggleLauncher"))
hl.bind(mod .. " + Space",       hl.dsp.exec_cmd(k4 .. "togglePanel"))
-- El cajón de aplicaciones de la barra: lo que la propia k4 sabe abrir.
-- SUPER+SHIFT+Space es toggle_float en la configuración de rukh, así que va
-- con ALT.
hl.bind(mod .. " + ALT + Space",  hl.dsp.exec_cmd(apps .. "toggle"))
hl.bind(mod .. " + I",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
-- X era el no-molestar de noctalia; k4 no tiene DND por IPC todavía y se
-- asoma el panel de notificaciones, que es lo más parecido.
hl.bind(mod .. " + X",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
-- Y el acento grave, que a la izquierda del 1 está muy a mano. N no: se
-- reserva para lo que sea en la configuración de rukh.
hl.bind(mod .. " + `",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind(mod .. " + A",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
-- Limpiar notificaciones, en las teclas de siempre. (k4 no distingue activa
-- de historial: clearNotifications se lo lleva todo.)
hl.bind(mod .. " + BackSpace",   hl.dsp.exec_cmd(k4 .. "clearNotifications"))
hl.bind(mod .. " + SHIFT + BackSpace", hl.dsp.exec_cmd(k4 .. "clearNotifications"))
-- Ajustes en SHIFT+S, donde noctalia los tenía (Z es el zoom de cursor de
-- rukh y no se toca).
hl.bind(mod .. " + SHIFT + S",   hl.dsp.exec_cmd(k4 .. "settings"))
-- La atalaya no se ata: SUPER+Tab cicla ventanas en la configuración de
-- rukh. Se abre desde el centro de aplicaciones.
-- hl.bind(mod .. " + Tab",         hl.dsp.global("k4:atalaya"))
-- El tema (fondos, paleta, todo) en SUPER+W: donde noctalia tenía el
-- selector de fondo. Y grabar en SHIFT+W, que era «record toggle».
hl.bind(mod .. " + W",           hl.dsp.exec_cmd(k4 .. "theme"))
hl.bind(mod .. " + SHIFT + W",   hl.dsp.exec_cmd(captura .. "grabarAlternar"))
-- Portapapeles en ambas: la tecla de k4 y la de siempre.
hl.bind(mod .. " + V",           hl.dsp.exec_cmd(k4 .. "clipboard"))
hl.bind(mod .. " + SHIFT + V",   hl.dsp.exec_cmd(k4 .. "clipboard"))
-- B es el gestor de contraseñas (rbw) en la configuración de rukh: sin ata.
-- hl.bind(mod .. " + B",           hl.dsp.exec_cmd(k4 .. "files"))
-- La chuleta, solo en F1: la tecla de «ayuda» de toda la vida (antes del
-- fork, hyprland.conf del usuario la daba a un guion propio que leía la
-- sintaxis clásica — con configuración en Lua ya no valía). K no: la quiere
-- la configuración de rukh para moverse entre ventanas.
hl.bind(mod .. " + F1",          hl.dsp.exec_cmd(k4 .. "keys"))
hl.bind(mod .. " + L",           hl.dsp.exec_cmd(k4 .. "lock"))
-- Sesión por ambos caminos: el ALT+C de k4 y el CTRL+ALT+E de siempre.
hl.bind(mod .. " + ALT + C",     hl.dsp.exec_cmd(k4 .. "session"))
hl.bind("CTRL + ALT + E",        hl.dsp.exec_cmd(k4 .. "session"))
-- Modo dual: la barra se parte en dos, baja por los bordes y se hace dock.
-- Va por atajo global y no por IPC porque no hace falta levantar un proceso
-- para alternarla: la barra recibe la señal del compositor.
hl.bind(mod .. " + SHIFT + D",   hl.dsp.global("k4:dual"))

----------------------------------------------------------------------------
-- La terminal
----------------------------------------------------------------------------
-- Nada de SUPER+T a secas: esa abre tu terminal de siempre y no se toca. La
-- de la island va con SHIFT, como el editor con SHIFT+E: misma letra, y la
-- que lleva SHIFT es la de la casa.
--
-- Son la misma sesión vista de dos maneras, y por eso el par tiene sentido:
-- SHIFT la asoma en la island para lo rápido, ALT la MUDA a una ventana
-- grande cuando la cosa se alarga —con lo que esté corriendo dentro, que no
-- se entera de nada.
--
-- Y ALT vale en los dos sentidos: pulsado sobre una ventana de k4term, la
-- sesión se vuelve a la island. Un gesto, no dos.
hl.bind(mod .. " + SHIFT + T",   hl.dsp.exec_cmd(term .. "isla"))
hl.bind(mod .. " + ALT + T",     hl.dsp.exec_cmd(term .. "mudar"))

-- Y los servidores de uno, a dos golpes: se abre, se escriben tres letras y
-- se entra. Los hosts salen de ~/.ssh/config, así que lo que guardes aquí lo
-- aprovechan también ssh, scp y git.
--
-- SUPER+ALT+S es el selector de shaders de rukh: sin ata. Se abre desde el
-- centro de aplicaciones.
-- hl.bind(mod .. " + ALT + S",     hl.dsp.exec_cmd(ssh .. "abrir"))

----------------------------------------------------------------------------
-- El asistente
----------------------------------------------------------------------------
-- El texto seleccionado no se adjunta solo: se ofrece en la cabecera y se
-- adjunta con Tab, con un clic en el chip, o abriendo con la última de estas.
-- (SUPER+G fue wl-kbptr en su día; retirado — sus teclas en pantalla no
-- recibían clic con las capas de k4 encima — y la tecla vuelve a ask.)
hl.bind(mod .. " + G",           hl.dsp.exec_cmd(k4 .. "ask"))
hl.bind(mod .. " + SHIFT + G",   hl.dsp.exec_cmd(k4 .. "askScreen"))
hl.bind(mod .. " + ALT + G",     hl.dsp.exec_cmd(k4 .. "askRegion"))
hl.bind(mod .. " + CONTROL + G", hl.dsp.exec_cmd(k4 .. "askSelection"))

----------------------------------------------------------------------------
-- Multimedia
----------------------------------------------------------------------------
-- Las XF86 de multimedia ya las ata la configuración de rukh (playerctl y
-- wpctl): no se duplican aquí. `locked` es lo que hace que funcionen con la
-- pantalla bloqueada — lo mismo que hacen las de rukh.
-- hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
-- hl.bind("XF86AudioPause", hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
-- hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(k4 .. "nextTrack"),  { locked = true })
-- hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(k4 .. "prevTrack"),  { locked = true })

----------------------------------------------------------------------------
-- Capturas y grabación
----------------------------------------------------------------------------
-- SUPER+C es hyprpicker en la configuración de rukh, y SUPER+CTRL+C manda la
-- ventana al espacio vacío: captura va por el Print y por SHIFT+C.
hl.bind(mod .. " + Print",       hl.dsp.exec_cmd(captura .. "menu"))
hl.bind("Print",                 hl.dsp.exec_cmd(captura .. "region"))
hl.bind("SHIFT + Print",         hl.dsp.exec_cmd(captura .. "pantalla"))
hl.bind("CONTROL + Print",       hl.dsp.exec_cmd(captura .. "ventana"))
-- Nada de ALT + Print: con Alt pulsado el kernel convierte esa tecla en SysRq y
-- Hyprland ya no ve un "Print", así que la combinación no llega nunca. Probado.

-- La misma tecla arranca y para la grabación: no hay que acordarse de otra.
-- (SHIFT+W, la de siempre, también la alterna — está más arriba.)
hl.bind(mod .. " + SHIFT + C",   hl.dsp.exec_cmd(captura .. "grabarAlternar"))

----------------------------------------------------------------------------
-- El editor de vídeo
----------------------------------------------------------------------------
-- SUPER+SHIFT+E es wshowkeys en la configuración de rukh: el editor queda en
-- ALT+E (retomar, con lo que hubiera a medias) y en el menú de captura.
hl.bind(mod .. " + ALT + E",     hl.dsp.exec_cmd(editor .. "retomar"))

----------------------------------------------------------------------------
-- Los clics
----------------------------------------------------------------------------
-- Para que el zoom automático del editor sepa dónde estabas mirando.
-- `non_consuming` es lo que hace que el clic siga llegando a la aplicación: sin
-- eso el ratón dejaría de funcionar en cuanto se cargara esta configuración.
hl.bind("mouse:272", hl.dsp.global("k4:clic"),        { non_consuming = true })
hl.bind("mouse:273", hl.dsp.global("k4:clicDerecho"), { non_consuming = true })
