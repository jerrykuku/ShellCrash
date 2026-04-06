#!/bin/sh
# Copyright (C) Juewuy

[ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$(dirname "$0")"; pwd)
. "$CRASHDIR"/libs/get_config.sh
. "$CRASHDIR"/libs/set_config.sh
[ -z "$TMPDIR" -o -z "$BINDIR" -o -z "$COMMAND" ] && . "$CRASHDIR"/init.sh >/dev/null 2>&1
[ -z "$TMPDIR" ] && TMPDIR=/tmp/ShellCrash
[ ! -d "$TMPDIR" ] && mkdir -p "$TMPDIR"

LOCKDIR="$TMPDIR/web_control.lock"
MAX_LOCK_ATTEMPTS=50
MAX_NAME_LENGTH=12
MAX_TABLE_VALUE=100000

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/\\r/g; s/\n/\\n/g'
}

json_ok() {
    msg=$(json_escape "$1")
    [ -n "$2" ] && {
        printf '{"ok":true,"message":"%s",%s}\n' "$msg" "$2"
        return
    }
    printf '{"ok":true,"message":"%s"}\n' "$msg"
}

json_err() {
    msg=$(json_escape "$1")
    printf '{"ok":false,"message":"%s"}\n' "$msg"
    exit 1
}

acquire_lock() {
    i=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        if [ -f "$LOCKDIR/pid" ]; then
            lock_pid=$(cat "$LOCKDIR/pid" 2>/dev/null)
            [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null && rm -rf "$LOCKDIR"
        fi
        i=$((i + 1))
        [ "$i" -ge "$MAX_LOCK_ATTEMPTS" ] && json_err "busy"
        sleep 0.1
    done
    echo "$$" >"$LOCKDIR/pid"
    trap 'rm -rf "$LOCKDIR" >/dev/null 2>&1' EXIT INT TERM
}

get_arg() {
    key="$1"
    shift
    for kv in "$@"; do
        case "$kv" in
        "$key"=*)
            printf '%s' "${kv#*=}"
            return 0
            ;;
        esac
    done
    return 1
}

require_auth() {
    token=$(get_arg token "$@")
    [ -z "$token" ] && token="$WEB_TOKEN"
    if [ -n "$secret" ] && [ "$token" != "$secret" ]; then
        json_err "unauthorized"
    fi
}

is_int() {
    echo "$1" | grep -Eq '^[0-9]+$'
}

valid_port() {
    is_int "$1" || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

valid_onoff() {
    [ "$1" = ON ] || [ "$1" = OFF ]
}

valid_name() {
    rest=$((MAX_NAME_LENGTH - 1))
    echo "$1" | grep -Eq "^[A-Za-z_][A-Za-z0-9_.-]{0,${rest}}$"
}

valid_ipv4() {
    ip="$1"
    echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    OLD_IFS="$IFS"
    IFS='.'
    set -- $ip
    IFS="$OLD_IFS"
    for o in "$@"; do
        is_int "$o" || return 1
        [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
    done
    return 0
}

valid_link() {
    echo "$1" | grep -Eq '^https?://[^ ]+$|^\./providers/[^ ]+$'
}

valid_uri() {
    echo "$1" | grep -Eq '^(ss|vmess|vless|trojan|tuic|anytls|shadowtls|hysteria|hysteria2)://[^ ]+$'
}

safe_noop_ui() {
    msg_alert() { :; }
    comp_box() { :; }
    btm_box() { :; }
    content_line() { :; }
    line_break() { :; }
    separator_line() { :; }
    list_box() { :; }
    common_success() { :; }
    common_failed() { :; }
    start_core() { :; }
    main_menu() { :; }
}

service_status_json() {
    if pidof CrashCore >/dev/null 2>&1; then
        printf '"service":{"running":true}'
    else
        printf '"service":{"running":false}'
    fi
}

print_kv_json() {
    key="$1"
    val="$2"
    printf '"%s":"%s"' "$key" "$(json_escape "$val")"
}

get_cfg_value() {
    case "$1" in
    firewall_area) printf '%s' "$firewall_area" ;;
    redir_mod) printf '%s' "$redir_mod" ;;
    dns_mod) printf '%s' "$dns_mod" ;;
    mix_port) printf '%s' "$mix_port" ;;
    redir_port) printf '%s' "$redir_port" ;;
    dns_port) printf '%s' "$dns_port" ;;
    db_port) printf '%s' "$db_port" ;;
    skip_cert) printf '%s' "$skip_cert" ;;
    sniffer) printf '%s' "$sniffer" ;;
    secret) printf '%s' "$secret" ;;
    host) printf '%s' "$host" ;;
    table) printf '%s' "$table" ;;
    authentication) printf '%s' "$authentication" ;;
    disoverride) printf '%s' "$disoverride" ;;
    proxies_bypass) printf '%s' "$proxies_bypass" ;;
    *) return 1 ;;
    esac
}

set_cfg_value() {
    key="$1"
    val="$2"
    case "$key" in
    firewall_area)
        echo "$val" | grep -Eq '^[1-5]$' || return 1
        ;;
    redir_mod)
        echo "$val" | grep -Eq '^(Redir|Tproxy|Tun|Mix)$' || return 1
        ;;
    dns_mod)
        echo "$val" | grep -Eq '^(redir_host|fake-ip)$' || return 1
        ;;
    mix_port|redir_port|dns_port|db_port)
        valid_port "$val" || return 1
        ;;
    skip_cert|sniffer|proxies_bypass)
        valid_onoff "$val" || return 1
        ;;
    secret|host|authentication)
        :
        ;;
    table)
        is_int "$val" || return 1
        [ "$val" -ge 1 ] && [ "$val" -le "$MAX_TABLE_VALUE" ] || return 1
        ;;
    disoverride)
        echo "$val" | grep -Eq '^(0|1)$' || return 1
        ;;
    *)
        return 1
        ;;
    esac

    case "$key" in
    host)
        if [ -n "$val" ] && ! valid_ipv4 "$val"; then
            return 1
        fi
        ;;
    authentication)
        if [ -n "$val" ] && ! echo "$val" | grep -q ':'; then
            return 1
        fi
        [ -n "$val" ] && val="'$val'"
        ;;
    esac

    setconfig "$key" "$val"
}

list_subscriptions() {
    first=1
    printf '"subscriptions":['
    if [ -s "$CRASHDIR/configs/providers.cfg" ]; then
        while read -r name link interval interval2 ua ex in; do
            [ -z "$name" ] && continue
            [ "$first" -eq 0 ] && printf ','
            first=0
            printf '{"name":"%s","kind":"provider","link":"%s","interval":"%s","interval2":"%s","ua":"%s","exclude":"%s","include":"%s"}' \
                "$(json_escape "$name")" \
                "$(json_escape "$link")" \
                "$(json_escape "$interval")" \
                "$(json_escape "$interval2")" \
                "$(json_escape "$ua")" \
                "$(json_escape "${ex#\#}")" \
                "$(json_escape "${in#\#}")"
        done <"$CRASHDIR/configs/providers.cfg"
    fi
    if [ -s "$CRASHDIR/configs/providers_uri.cfg" ]; then
        while read -r name link_uri; do
            [ -z "$name" ] && continue
            [ "$first" -eq 0 ] && printf ','
            first=0
            printf '{"name":"%s","kind":"uri","link":"%s"}' \
                "$(json_escape "$name")" \
                "$(json_escape "$link_uri")"
        done <"$CRASHDIR/configs/providers_uri.cfg"
    fi
    printf ']'
}

upsert_provider() {
    name="$1"
    mode="$2"
    link="$3"
    interval="${4:-3}"
    interval2="${5:-12}"
    ua="${6:-clash.meta}"
    exclude="$7"
    include="$8"

    valid_name "$name" || json_err "invalid_name"
    [ -n "$exclude" ] || exclude=''
    [ -n "$include" ] || include=''

    mkdir -p "$CRASHDIR/configs"
    [ -f "$CRASHDIR/configs/providers.cfg" ] || : >"$CRASHDIR/configs/providers.cfg"
    [ -f "$CRASHDIR/configs/providers_uri.cfg" ] || : >"$CRASHDIR/configs/providers_uri.cfg"

    sed -i "/^$name /d" "$CRASHDIR/configs/providers.cfg" "$CRASHDIR/configs/providers_uri.cfg" 2>/dev/null

    case "$mode" in
    provider)
        valid_link "$link" || json_err "invalid_link"
        is_int "$interval" || json_err "invalid_interval"
        is_int "$interval2" || json_err "invalid_interval2"
        echo "$name $link $interval $interval2 $ua #$exclude #$include" >>"$CRASHDIR/configs/providers.cfg"
        ;;
    uri)
        valid_uri "$link" || json_err "invalid_uri"
        echo "$name $link" >>"$CRASHDIR/configs/providers_uri.cfg"
        ;;
    *)
        json_err "invalid_mode"
        ;;
    esac
}

delete_provider() {
    name="$1"
    valid_name "$name" || json_err "invalid_name"
    [ -f "$CRASHDIR/configs/providers.cfg" ] && sed -i "/^$name /d" "$CRASHDIR/configs/providers.cfg"
    [ -f "$CRASHDIR/configs/providers_uri.cfg" ] && sed -i "/^$name /d" "$CRASHDIR/configs/providers_uri.cfg"
}

generate_providers() {
    safe_noop_ui
    if echo "$crashcore" | grep -q 'singbox'; then
        CORE_TYPE=singbox
    else
        CORE_TYPE=clash
    fi
    . "$CRASHDIR/menus/providers_${CORE_TYPE}.sh" || json_err "load_provider_module_failed"
    gen_providers </dev/null >/dev/null 2>&1 || json_err "generate_failed"
}

action="$1"
subaction="$2"
shift 2 2>/dev/null

[ -n "$action" ] || json_err "missing_action"
require_auth "$@"
acquire_lock

case "$action:$subaction" in
service:start)
    "$CRASHDIR/start.sh" start >/dev/null 2>&1 || json_err "start_failed"
    extra=$(service_status_json)
    json_ok "started" "$extra"
    ;;
service:stop)
    "$CRASHDIR/start.sh" stop >/dev/null 2>&1 || json_err "stop_failed"
    extra=$(service_status_json)
    json_ok "stopped" "$extra"
    ;;
service:restart)
    "$CRASHDIR/start.sh" restart >/dev/null 2>&1 || json_err "restart_failed"
    extra=$(service_status_json)
    json_ok "restarted" "$extra"
    ;;
service:status)
    extra=$(service_status_json)
    json_ok "status" "$extra"
    ;;

subscription:list)
    extra=$(list_subscriptions)
    json_ok "ok" "$extra"
    ;;
subscription:add|subscription:update)
    name=$(get_arg name "$@")
    mode=$(get_arg mode "$@")
    link=$(get_arg link "$@")
    interval=$(get_arg interval "$@")
    interval2=$(get_arg interval2 "$@")
    ua=$(get_arg ua "$@")
    exclude=$(get_arg exclude "$@")
    include=$(get_arg include "$@")
    [ -n "$name" ] || json_err "missing_name"
    [ -n "$mode" ] || json_err "missing_mode"
    [ -n "$link" ] || json_err "missing_link"
    upsert_provider "$name" "$mode" "$link" "$interval" "$interval2" "$ua" "$exclude" "$include"
    json_ok "saved"
    ;;
subscription:delete)
    name=$(get_arg name "$@")
    [ -n "$name" ] || json_err "missing_name"
    delete_provider "$name"
    json_ok "deleted"
    ;;
subscription:generate)
    generate_providers
    json_ok "generated"
    ;;

settings:get|advanced:get)
    keys=$(get_arg keys "$@")
    [ -n "$keys" ] || keys='firewall_area,redir_mod,dns_mod,mix_port,redir_port,dns_port,db_port,skip_cert,sniffer,secret,host,table,authentication,disoverride,proxies_bypass'
    first=1
    out=''
    OLD_IFS="$IFS"
    IFS=','
    for k in $keys; do
        IFS="$OLD_IFS"
        v=$(get_cfg_value "$k") || { IFS=','; continue; }
        pair=$(print_kv_json "$k" "$v")
        if [ "$first" -eq 1 ]; then
            out="$pair"
            first=0
        else
            out="$out,$pair"
        fi
        IFS=','
    done
    IFS="$OLD_IFS"
    json_ok "ok" "\"config\":{$out}"
    ;;
settings:set|advanced:set)
    key=$(get_arg key "$@")
    value=$(get_arg value "$@")
    [ -n "$key" ] || json_err "missing_key"
    set_cfg_value "$key" "$value" || json_err "invalid_value_or_key"
    json_ok "saved"
    ;;

*)
    json_err "unsupported_action"
    ;;
esac
