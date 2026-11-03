#!/system/bin/sh

# Autopif date policy shared by the WebUI and the OTA-maintained script.
MODDIR=/data/adb/modules/playintegrityfix
CONFIG=/data/adb/pif_patch_mode.conf
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
export PATH

valid_date() {
    case "$1" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) return 1 ;;
    esac
    local y m d tail limit
    y=$((1${1%%-*} - 10000))
    tail=${1#*-}
    m=$((1${tail%%-*} - 100))
    d=$((1${1##*-} - 100))
    [ "$y" -ge 1 ] && [ "$m" -ge 1 ] && [ "$m" -le 12 ] && [ "$d" -ge 1 ] || return 1
    case "$m" in
        4|6|9|11) limit=30 ;;
        2)
            limit=28
            if [ $((y % 400)) -eq 0 ] || { [ $((y % 4)) -eq 0 ] && [ $((y % 100)) -ne 0 ]; }; then
                limit=29
            fi
            ;;
        *) limit=31 ;;
    esac
    [ "$d" -le "$limit" ]
}

# Read firmware files, rather than properties already changed by PIF.
# System and Vendor retain their own dates across OTA updates.
stock_patch() {
    local partition="$1" file candidate key
    case "$partition" in
        system) key=ro.build.version.security_patch; set -- /system/build.prop /system/system/build.prop ;;
        vendor) key=ro.vendor.build.security_patch; set -- /vendor/build.prop /system/vendor/build.prop ;;
        *) return 1 ;;
    esac
    for file in "$@"; do
        [ -r "$file" ] || continue
        candidate=$(awk -F= -v key="$key" '
            $1 == key { sub(/\r$/, "", $2); print $2; exit }
        ' "$file")
        if valid_date "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done
    echo "无法读取 $partition 镜像原始补丁日期；请保留现有配置并核对 build.prop。" >&2
    return 1
}

load_config() {
    MODE=day01
    CUSTOM_DATE=
    if [ -f "$CONFIG" ]; then
        while IFS='=' read -r key value; do
            case "$key" in
                mode) MODE=$value ;;
                custom_date) CUSTOM_DATE=$value ;;
            esac
        done < "$CONFIG"
    fi
    case "$MODE" in
        official|day01|split) ;;
        custom) valid_date "$CUSTOM_DATE" || { echo "自定义补丁日期无效。" >&2; return 1; } ;;
        *) echo "补丁日期模式配置无效。" >&2; return 1 ;;
    esac
}

supports_split() {
    # The installed TSOSS 199 parser supports named package sections.
    # Plain TrickyStore and the TOML fork have different configuration grammars.
    grep -qi 'beakthoven' /data/adb/modules/tricky_store/module.prop 2>/dev/null
}

load_config || exit 1

case "$1" in
    set)
        case "$2" in
            official|day01|split) MODE=$2 ;;
            custom)
                valid_date "$3" || { echo "请输入真实存在的日期，格式为 YYYY-MM-DD。" >&2; exit 1; }
                MODE=custom
                CUSTOM_DATE=$3
                ;;
            *) echo "未知补丁日期模式。" >&2; exit 1 ;;
        esac
        if [ "$MODE" = split ]; then
            supports_split || { echo "按应用区分日期需要当前的 TSOSS 199。" >&2; exit 1; }
            stock_patch system >/dev/null || exit 1
            stock_patch vendor >/dev/null || exit 1
            mkdir -p /data/adb/tricky_store || exit 1
            touch /data/adb/tricky_store/pif_auto_security_patch || exit 1
        fi
        umask 077
        printf 'mode=%s\ncustom_date=%s\n' "$MODE" "$CUSTOM_DATE" > "$CONFIG.tmp" || exit 1
        mv -f "$CONFIG.tmp" "$CONFIG" || exit 1
        echo "已保存，下次运行 Autopif 生效。"
        ;;
    resolve)
        SECURITY_PATCH=$2
        case "$MODE" in
            official) ;;
            day01)
                case "$SECURITY_PATCH" in
                    *-05) SECURITY_PATCH="${SECURITY_PATCH%-05}-01" ;;
                esac
                ;;
            custom) SECURITY_PATCH=$CUSTOM_DATE ;;
        esac
        printf '%s\n' "$SECURITY_PATCH"
        ;;
    sync-date)
        SECURITY_PATCH=$2
        valid_date "$SECURITY_PATCH" || { echo "PIF 补丁日期格式无效。" >&2; exit 1; }
        if [ "$MODE" = split ]; then
            stock_patch system || exit 1
        else
            printf '%s\n' "$SECURITY_PATCH"
        fi
        ;;
    sync-vendor-date)
        if [ "$MODE" = split ]; then
            stock_patch vendor || exit 1
        else
            valid_date "$2" || exit 1
            printf '%s\n' "$2"
        fi
        ;;
    status)
        PIFPROP=/data/adb/pif.prop
        [ -f "$PIFPROP" ] || PIFPROP="$MODDIR/pif.prop"
        CURRENT_DATE=$(sed -n 's/^SECURITY_PATCH=//p' "$PIFPROP" | head -n 1)
        printf 'mode=%s\ncustom_date=%s\ncurrent_date=%s\n' "$MODE" "$CUSTOM_DATE" "$CURRENT_DATE"
        printf 'sync_date=%s\n' "$(sh "$MODDIR/patch_mode.sh" sync-date "$CURRENT_DATE" 2>/dev/null)"
        supports_split && echo 'split_supported=true' || echo 'split_supported=false'
        if [ -f /data/adb/tricky_store/security_patch.txt ]; then
            awk '
                /^[[:space:]]*\[/ { section=$0 }
                section == "" && /^boot=/ { print "ts_default_boot=" substr($0,6) }
                section == "[com.google.android.gms]" && /^boot=/ { google=substr($0,6) }
                END { print "ts_google_boot=" google }
            ' /data/adb/tricky_store/security_patch.txt
        fi
        printf 'build_date=%s\nvendor_date=%s\n' "$(getprop ro.build.version.security_patch)" "$(getprop ro.vendor.build.security_patch)"
        if [ -e /data/adb/tricky_store/pif_auto_security_patch ]; then
            echo 'sync_enabled=true'
        else
            echo 'sync_enabled=false'
        fi
        ;;
    *) echo "Usage: sh patch_mode.sh {status|set official|set day01|set split|set custom YYYY-MM-DD|resolve YYYY-MM-DD|sync-date YYYY-MM-DD|sync-vendor-date YYYY-MM-DD}" >&2; exit 1 ;;
esac
