#!/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/playintegrityfix

REPOSITORY="KOWX712/PlayIntegrityFix"
BRANCH="inject_s"
AUTOPIF_PATH="$BRANCH/module/autopif.sh"
GITHUB_CDN="https://fastly.jsdelivr.net/gh/$REPOSITORY"
GITHUB_RAW="https://raw.githubusercontent.com/$REPOSITORY"
GITHUB_MIRROR="https://gh.sevencdn.com/$GITHUB_RAW"

# lets try to use tmpfs for processing
TEMPDIR="$MODDIR/temp" #fallback
[ -w /sbin ] && TEMPDIR="/sbin/playintegrityfix"
[ -w /debug_ramdisk ] && TEMPDIR="/debug_ramdisk/playintegrityfix"
[ -w /dev ] && TEMPDIR="/dev/playintegrityfix"
mkdir -p "$TEMPDIR"

download() { busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2"; }
if command -v curl > /dev/null 2>&1; then
    download() { curl --connect-timeout 10 -Ls "$1" > "$2"; }
fi

# Keep the selected date policy when installing an upstream Autopif update.
patch_autopif_mode() {
    local INPUT_FILE="$1"
    local PATCHED_FILE="$TEMPDIR/temp_autopif_modes.sh"

    if grep -q '^# PIF_LOCAL_PATCH_MODE$' "$INPUT_FILE"; then
        return 0
    fi

    busybox awk '
        BEGIN { anchors = 0 }
        $0 == "# Preserve previous setting" {
            anchors++
            print "# PIF_LOCAL_PATCH_MODE"
            print "SECURITY_PATCH=\"$(sh \"$MODDIR/patch_mode.sh\" resolve \"$SECURITY_PATCH\")\" || {"
            print "    echo \"! Failed to apply the selected security patch mode\""
            print "    exit 1"
            print "}"
            print ""
        }
        { print }
        END { if (anchors != 1) exit 1 }
    ' "$INPUT_FILE" > "$PATCHED_FILE" || return 1

    sh -n "$PATCHED_FILE" || return 1
    cat "$PATCHED_FILE" > "$INPUT_FILE" || return 1
}

# fetch script
fetch_autopif() {
    if download "$1" "$TEMPDIR/temp_autopif.sh"; then
        if ! grep -q "^#!/bin/sh" $TEMPDIR/temp_autopif.sh; then
            return 1
        fi

        if ! patch_autopif_mode "$TEMPDIR/temp_autopif.sh"; then
            echo "[!] Could not apply the date mode hook; keeping the current autopif.sh"
            return 1
        fi

        # hash
        curhash="$(cat $MODDIR/autopif.sh | busybox crc32)"
        newhash="$(cat $TEMPDIR/temp_autopif.sh | busybox crc32)"

        if [ ! "$newhash" = "$curhash" ]; then
            cat "$TEMPDIR/temp_autopif.sh" > "$MODDIR/autopif.sh" || return 1
            echo "[+] autopif has been updated with selectable date modes"
        fi

        return 0
    else
        return 1
    fi
}

if fetch_autopif "$GITHUB_CDN@$AUTOPIF_PATH"; then
    true
elif fetch_autopif "$GITHUB_RAW/$AUTOPIF_PATH"; then
    true
elif fetch_autopif "$GITHUB_MIRROR/$AUTOPIF_PATH"; then
    true
else
    echo "[!] OTA failed, skipping autopif update."
fi

rm -rf "$TEMPDIR"

# EOF
