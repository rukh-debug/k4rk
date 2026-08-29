-- Generado por el instalador de k4. NO LO EDITES: se reescribe al actualizar.
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
-- En Nix no edites este fichero: `programs.k4.hyprland.template` acepta una
-- plantilla tuya y esta queda intacta para poder comparar.

local mod = "SUPER"
local raiz = "@RAIZ@"

-- Las tres llamadas de IPC. `k4` es el objetivo general, que se mantiene por
-- compatibilidad; los módulos nuevos publican el suyo propio.
local k4 = "quickshell ipc -p " .. raiz .. "/shell.qml call k4 "
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
hl.bind(mod .. " + Space",       hl.dsp.exec_cmd(k4 .. "toggleLauncher"))
-- El cajón de aplicaciones de la barra: lo que la propia k4 sabe abrir.
-- Justo al lado del lanzador y a propósito: Space lanza las aplicaciones del
-- escritorio, SHIFT+Space las de la barra. (SUPER+D, que era lo primero que
-- se me ocurrió, ya es «pantalla completa» en la configuración de CachyOS.)
hl.bind(mod .. " + SHIFT + Space", hl.dsp.exec_cmd(apps .. "toggle"))
hl.bind(mod .. " + I",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind(mod .. " + X",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind(mod .. " + N",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind(mod .. " + A",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind(mod .. " + Z",           hl.dsp.exec_cmd(k4 .. "settings"))
hl.bind(mod .. " + SHIFT + W",   hl.dsp.exec_cmd(k4 .. "theme"))
hl.bind(mod .. " + V",           hl.dsp.exec_cmd(k4 .. "clipboard"))
hl.bind(mod .. " + K",           hl.dsp.exec_cmd(k4 .. "keys"))
hl.bind(mod .. " + L",           hl.dsp.exec_cmd(k4 .. "lock"))
hl.bind(mod .. " + ALT + C",     hl.dsp.exec_cmd(k4 .. "session"))
----------------------------------------------------------------------------
-- La terminal
----------------------------------------------------------------------------
-- Nada de SUPER+T a secas: esa abre tu terminal de siempre y no se toca. La
-- de la island va con SHIFT: misma letra, y la
-- que lleva SHIFT es la de la casa.
--
-- Son la misma sesión vista de dos maneras, y por eso el par tiene sentido:
-- SHIFT la asoma en la island para lo rápido, ALT la MUDA a una ventana
-- grande cuando la cosa se alarga —con lo que esté corriendo dentro, que no
-- se entera de nada.
--
-- Y ALT vale en los dos sentidos: pulsado sobre una ventana de k4term, la
-- sesión se vuelve a la island. Un gesto, no dos.
hl.bind(mod .. " + SHIFT + T",   hl.dsp.exec_cmd(term .. "island"))
hl.bind(mod .. " + ALT + T",     hl.dsp.exec_cmd(term .. "move"))

-- Y los servidores de uno, a dos golpes: se abre, se escriben tres letras y
-- se entra. Los hosts salen de ~/.ssh/config, así que lo que guardes aquí lo
-- aprovechan también ssh, scp y git.
--
-- Va con ALT y no con SHIFT porque SUPER+SHIFT+S ya es tuyo de antes —mandar
-- la ventana al espacio especial—, y quitártelo por esto sería una faena.
hl.bind(mod .. " + ALT + S",     hl.dsp.exec_cmd(ssh .. "abrir"))

----------------------------------------------------------------------------
-- El asistente
----------------------------------------------------------------------------
-- El texto seleccionado no se adjunta solo: se ofrece en la cabecera y se
-- adjunta con Tab, con un clic en el chip, o abriendo con la última de estas.
hl.bind(mod .. " + G",           hl.dsp.exec_cmd(k4 .. "ask"))
hl.bind(mod .. " + SHIFT + G",   hl.dsp.exec_cmd(k4 .. "askScreen"))
hl.bind(mod .. " + ALT + G",     hl.dsp.exec_cmd(k4 .. "askRegion"))
hl.bind(mod .. " + CONTROL + G", hl.dsp.exec_cmd(k4 .. "askSelection"))

----------------------------------------------------------------------------
-- Multimedia
----------------------------------------------------------------------------
-- `locked` es lo que hace que funcionen con la pantalla bloqueada.
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(k4 .. "nextTrack"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(k4 .. "prevTrack"),  { locked = true })

----------------------------------------------------------------------------
-- Los clics
----------------------------------------------------------------------------
