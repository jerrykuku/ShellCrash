#!/bin/sh
# CGI bridge: translates HTTP query-string requests into web_control.sh calls.
# Served by busybox httpd; the web UI at index.html calls this endpoint.

# ---- HTTP response headers ----
printf "Content-Type: application/json\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
printf "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
printf "\r\n"

[ "$REQUEST_METHOD" = "OPTIONS" ] && exit 0

# ---- URL-decode a single percent-encoded string ----
urldecode() {
    printf '%s' "$1" | awk '
    BEGIN {
        for (i = 0; i < 256; i++) {
            h = sprintf("%02X", i)
            ord[h] = sprintf("%c", i)
            h = sprintf("%02x", i)
            ord[h] = sprintf("%c", i)
        }
    }
    {
        result = ""
        n = length($0)
        i = 1
        while (i <= n) {
            c = substr($0, i, 1)
            if (c == "%" && i + 2 <= n) {
                hex = toupper(substr($0, i + 1, 2))
                if (hex in ord) {
                    result = result ord[hex]
                    i += 3
                    continue
                }
            }
            if (c == "+") c = " "
            result = result c
            i++
        }
        printf "%s", result
    }'
}

# ---- Resolve CRASHDIR from this script's path ----
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)
export CRASHDIR

# ---- Read query string (GET or POST) ----
if [ "$REQUEST_METHOD" = "POST" ] && [ -n "$CONTENT_LENGTH" ]; then
    qs=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
    qs="$QUERY_STRING"
fi

[ -z "$qs" ] && {
    printf '{"ok":false,"message":"missing_action"}\n'
    exit 1
}

# ---- Extract action / subaction (still URL-encoded at this point) ----
raw_action=$(printf '%s' "$qs" | tr '&' '\n' | grep '^action=' | head -1 | cut -d= -f2-)
raw_sub=$(printf '%s' "$qs" | tr '&' '\n' | grep '^subaction=' | head -1 | cut -d= -f2-)
action=$(urldecode "$raw_action")
subaction=$(urldecode "$raw_sub")

[ -z "$action" ] && {
    printf '{"ok":false,"message":"missing_action"}\n'
    exit 1
}

# ---- Build extra key=value positional args ----
# We use "set --" so each pair is one shell word (handles spaces inside values).
set --
while IFS= read -r raw_pair; do
    [ -z "$raw_pair" ] && continue
    raw_key="${raw_pair%%=*}"
    raw_val="${raw_pair#*=}"
    key=$(urldecode "$raw_key")
    val=$(urldecode "$raw_val")
    case "$key" in
    action | subaction) continue ;;
    esac
    set -- "$@" "${key}=${val}"
done << EOF
$(printf '%s' "$qs" | tr '&' '\n')
EOF

# ---- Delegate to web_control.sh ----
exec "$CRASHDIR/web_control.sh" "$action" "$subaction" "$@"
