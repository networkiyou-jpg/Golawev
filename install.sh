#!/bin/sh
# ---------------------------------------------------------------------------
# GoalWave E2 - installer / updater / remover for Enigma2 receivers
# BusyBox-compatible (no bash needed).  Developer: mouad  (Telegram @Kingsharing1)
#
#   sh install.sh            install or update (default)
#   sh install.sh remove     remove the plugin (your settings are kept)
#   sh install.sh purge      remove the plugin AND delete its settings
#   sh install.sh status     show install state + support info
#   sh install.sh log        show the last 40 log lines (send them for support)
#
# Integrity: the package is verified against the SHA-256 pinned below before it
# is installed. A wrong / modified file is refused.
# ---------------------------------------------------------------------------
PKG="enigma2-plugin-extensions-goalwave"
GW_VER="1.4.1"
GW_SHA256="ecf0066b1539639d145dfc2ab71cf88ba1c66cc162cc1ab08df34ab9e24b4cba"
GW_REPO_RAW="${GW_REPO_RAW:-https://raw.githubusercontent.com/networkiyou-jpg/Golawev/main}"
IPK="${PKG}_${GW_VER}_all.ipk"
GW_URL="${GW_URL:-$GW_REPO_RAW/$IPK}"
TMPD="${GW_TMP:-/tmp}"
SETTINGS_DIR="${GW_SETTINGS_DIR:-/etc/enigma2/goalwave}"
PLUGIN_DIR="${GW_PLUGIN_DIR:-/usr/lib/enigma2/python/Plugins/Extensions/GoalWave}"
LOG_FILE="${GW_LOG:-/tmp/goalwave/goalwave.log}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
    [ "${GW_ALLOW_NONROOT:-0}" = "1" ] && return 0
    [ "$(id -u 2>/dev/null)" = "0" ] || die "run as root (telnet/ssh root login)"
}

need_opkg() { have opkg || die "opkg not found - this is not an Enigma2 image (or PATH is broken)"; }

fetch() {   # fetch URL DEST
    rm -f "$2"
    if have wget && wget -q -O "$2" "$1" 2>/dev/null && [ -s "$2" ]; then return 0; fi
    if have curl && curl -fsSL -o "$2" "$1" 2>/dev/null && [ -s "$2" ]; then return 0; fi
    if [ "${GW_INSECURE:-0}" = "1" ]; then
        say "WARNING: certificate checks disabled (GW_INSECURE=1); the SHA-256 check still protects the package"
        if have wget && wget -q --no-check-certificate -O "$2" "$1" 2>/dev/null && [ -s "$2" ]; then return 0; fi
        if have curl && curl -fsSLk -o "$2" "$1" 2>/dev/null && [ -s "$2" ]; then return 0; fi
    fi
    rm -f "$2"
    return 1
}

sha_of() {
    if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; return 0; fi
    if have openssl; then openssl dgst -sha256 "$1" 2>/dev/null | sed 's/^.*= *//'; return 0; fi
    return 1
}

restart_gui() {
    if [ "${GW_NORESTART:-0}" = "1" ]; then
        say "Restart skipped. Restart the GUI yourself to activate the plugin."
        return 0
    fi
    say "Restarting the GUI in 3 seconds ..."
    sleep 3
    if have systemctl && systemctl restart enigma2 >/dev/null 2>&1; then return 0; fi
    if have killall; then killall -9 enigma2 >/dev/null 2>&1 && return 0; fi
    say "Could not restart automatically. Please restart the GUI / reboot."
}

is_installed() { opkg list-installed 2>/dev/null | grep -q "^$PKG "; }

do_install() {
    need_root; need_opkg
    say "GoalWave E2 v$GW_VER - installing"
    F="$TMPD/$IPK"
    say "Downloading: $GW_URL"
    if ! fetch "$GW_URL" "$F"; then
        say "Download failed. Check: internet connection, the URL above, and that the file exists in the repository."
        say "If your image cannot verify HTTPS certificates, retry with:  GW_INSECURE=1 sh install.sh"
        die "could not download the package"
    fi
    GOT="$(sha_of "$F")"
    if [ -z "$GOT" ]; then
        say "WARNING: no sha256 tool found - integrity could not be verified"
    elif [ "$GOT" != "$GW_SHA256" ]; then
        rm -f "$F"
        say "expected: $GW_SHA256"
        say "got     : $GOT"
        die "checksum mismatch - the downloaded file is not the official package (is the URL a raw file link, not a web page?)"
    else
        say "Checksum OK"
    fi
    if is_installed; then
        say "Previous version found - removing it first (settings are kept)"
        opkg remove "$PKG" >/dev/null 2>&1 || say "WARNING: could not remove the old version cleanly"
    fi
    if ! opkg install "$F"; then
        say "Retrying with --force-overwrite ..."
        opkg install --force-overwrite "$F" || { rm -f "$F"; die "opkg install failed"; }
    fi
    rm -f "$F"
    [ -f "$PLUGIN_DIR/plugin.py" ] || die "install finished but plugin files were not found in $PLUGIN_DIR"
    say "GoalWave E2 v$GW_VER installed."
    say "Open it from: Plugins menu -> GoalWave E2   (blue button -> GoalWave: Toggle Ticker)"
    restart_gui
}

do_remove() {
    need_root; need_opkg
    if is_installed; then
        opkg remove "$PKG" || die "opkg remove failed"
        say "GoalWave E2 removed (settings kept in $SETTINGS_DIR)."
    else
        say "GoalWave E2 is not installed."
    fi
}

do_purge() {
    do_remove
    rm -rf "$SETTINGS_DIR" /tmp/goalwave
    say "Settings and caches deleted."
    restart_gui
}

do_status() {
    say "== GoalWave E2 status =="
    if have opkg && is_installed; then opkg list-installed 2>/dev/null | grep "^$PKG "; else say "not installed"; fi
    [ -f "$PLUGIN_DIR/plugin.py" ] && say "plugin files : present" || say "plugin files : missing"
    [ -d "$SETTINGS_DIR" ] && say "settings dir : $SETTINGS_DIR" || say "settings dir : (none yet)"
    say "== support info =="
    [ -r /proc/stb/info/model ] && say "model        : $(cat /proc/stb/info/model)"
    [ -r /etc/image-version ] && say "image        : $(grep -E '^(distro|imageversion|version)=' /etc/image-version | tr '\n' ' ')"
    have python3 && say "python       : $(python3 --version 2>&1)" || { have python && say "python       : $(python --version 2>&1)"; }
    say "log file    : $LOG_FILE  (run: sh install.sh log)"
}

do_log() {
    [ -f "$LOG_FILE" ] || { say "No log yet ($LOG_FILE)."; return 0; }
    tail -n 40 "$LOG_FILE"
}

case "${1:-install}" in
    install|update) do_install ;;
    remove|uninstall) do_remove; restart_gui ;;
    purge) do_purge ;;
    status) do_status ;;
    log) do_log ;;
    *) say "usage: sh install.sh [install|remove|purge|status|log]"; exit 2 ;;
esac
