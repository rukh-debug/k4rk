"""Canonical host defaults and validation, shared by migration and writers."""
import math
import re

SHELL_DEFAULTS = {
    "barPosition": "top", "barAlignment": 50, "islandSpace": "reserve",
    "notificationsOnHover": True, "notificationsOnFocus": True,
    "notificationPopupPosition": "bottom-right", "playerPeekOnChange": True,
    "uiSoundsEnabled": True, "uiSoundVolume": 35,
    "pillOrder": ["media", "clock-workspaces", "minimized", "plugin-indicators", "tray"],
    "pillHiddenItems": ["tray"],
    "pillTrayMax": 0, "pillMinimizedMax": 0, "pillIndicatorsMax": 0, "pillIndicatorIconSize": 14,
    "shellFont": "", "wallpaperPalette": True, "panelShowToggles": True,
    "panelTileWifi": True, "panelTileBluetooth": True, "panelTileSound": True,
    "panelTileBrightness": True, "panelShowMedia": True, "panelShowShortcuts": True,
    "panelShowWorkspaces": True, "panelWorkspaceStyle": "dots", "panelShowClock": True,
    "panelShowScratchpad": True, "panelOrder": ["toggles", "power-display", "media", "shortcuts"],
    "panelHiddenBlocks": [], "panelShowPowerDisplay": True, "nightLightEnabled": False,
    "nightLightTemperature": 4000, "nightLightMode": "manual",
    "islandPlacements": {}, "independentIslands": {}, "popupSizes": {},
    "edgeZoneEnabled": True, "edgeZoneSize": 1, "rimRadius": 6,
    "quickAccess": ["settings", "system", "clipboard"],
}

LOCAL_SHELL_DEFAULTS = {"nightLightLocation": {}, "nightLightOverride": {}}
OBSOLETE_PLUGINS = {"digivice", "dual", "hyprtheme", "game", "mini-isle", "displays", "atalaya",
                    "weather", "windows", "tienda", "files", "captura", "pantallas"}
NATIVE_IDS = {"idle", "volume", "sound", "clock", "player", "toast", "panel", "session", "tray"}
OPENWEBUI_SETTINGS = {"rememberHistory", "openAfterResponse"}
WALLPAPER_SETTINGS = {"transition", "scheme"}


def validate_sections(data):
    for key, value in data["shell"].items():
        if key not in SHELL_DEFAULTS:
            raise ValueError("Not a shareable shell setting: " + key)
        if key in SHELL_DEFAULTS and type(value) is not type(SHELL_DEFAULTS[key]):
            raise ValueError("Invalid setting type: shell." + key)
    for key, choices in {
        "barPosition": ("top", "bottom"), "islandSpace": ("reserve", "auto", "onTop", "hidden"),
        "panelWorkspaceStyle": ("dots", "numbers"), "nightLightMode": ("manual", "solar"),
    }.items():
        if key in data["shell"] and data["shell"][key] not in choices:
            raise ValueError("Invalid setting value: shell." + key)
    for key, lower, upper in (("barAlignment", 0, 100), ("uiSoundVolume", 0, 100),
                               ("edgeZoneSize", 1, 16), ("rimRadius", 0, 24),
                               ("nightLightTemperature", 1000, 6500)):
        if key in data["shell"] and not lower <= data["shell"][key] <= upper:
            raise ValueError("Setting out of range: shell." + key)
    for ident, plugin in data["plugins"].items():
        if ident in NATIVE_IDS:
            raise ValueError("Native features are not plugin settings: " + ident)
        if not isinstance(plugin, dict) or ("enabled" in plugin and type(plugin["enabled"]) is not bool):
            raise ValueError("Invalid plugin settings: " + ident)
        if set(plugin) - {"enabled", "settings"} or not isinstance(plugin.get("settings", {}), dict):
            raise ValueError("Only enablement and settings belong in plugin configuration: " + ident)
        if ident == "openwebui" and set(plugin.get("settings", {})) - OPENWEBUI_SETTINGS:
            raise ValueError("OpenWebUI connection profiles and history belong in local state")
    if set(data["features"]) - {"wallpaper"}:
        raise ValueError("Personal feature profiles belong in local state")
    wallpaper = data["features"].get("wallpaper", {})
    if not isinstance(wallpaper, dict) or set(wallpaper) - WALLPAPER_SETTINGS:
        raise ValueError("Wallpaper paths belong in local state")
    terminal = data["plugins"].get("terminal", {}).get("settings", {})
    if not isinstance(terminal, dict):
        raise ValueError("Invalid terminal settings")
    for key, lower, upper in (("size", 6, 72), ("opacity", 0, 1), ("scrollback", 100, 100000)):
        if key in terminal:
            try:
                value = float(terminal[key])
                if not math.isfinite(value) or not lower <= value <= upper:
                    raise ValueError()
            except (ValueError, TypeError):
                raise ValueError("Invalid terminal setting: " + key) from None
