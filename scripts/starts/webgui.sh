#!/bin/sh
# Manage the busybox httpd process that serves the ShellCrash web GUI.
# Usage: webgui.sh {start|stop|status}

[ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$(dirname "$0")/.." && pwd)
. "$CRASHDIR/libs/get_config.sh"
[ -z "$TMPDIR" ] && TMPDIR=/tmp/ShellCrash

WEB_PORT=${web_port:-9000}
WEB_DIR="$CRASHDIR/webgui"
PID_FILE="$TMPDIR/webgui.pid"

webgui_running() {
    [ -f "$PID_FILE" ] || return 1
    pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

webgui_start() {
    webgui_running && return 0
    # Require busybox httpd
    if ! busybox httpd --help >/dev/null 2>&1; then
        echo "busybox httpd not available, skipping webgui" >&2
        return 1
    fi
    [ ! -d "$WEB_DIR" ] && { echo "webgui directory not found: $WEB_DIR" >&2; return 1; }
    chmod +x "$WEB_DIR/cgi-bin/api.sh" 2>/dev/null
    busybox httpd -f -p "$WEB_PORT" -h "$WEB_DIR" &
    httpd_pid=$!
    echo "$httpd_pid" >"$PID_FILE"
    sleep 1
    if ! kill -0 "$httpd_pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo "webgui httpd failed to start on port $WEB_PORT" >&2
        return 1
    fi
    return 0
}

webgui_stop() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
}

case "$1" in
start)
    webgui_start
    ;;
stop)
    webgui_stop
    ;;
status)
    if webgui_running; then
        echo "webgui running on port $WEB_PORT (pid $(cat "$PID_FILE"))"
    else
        echo "webgui not running"
    fi
    ;;
*)
    echo "Usage: $0 {start|stop|status}" >&2
    exit 1
    ;;
esac
