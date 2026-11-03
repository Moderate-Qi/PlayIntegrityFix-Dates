#!/system/bin/sh
# Keep the PIF profile date separate from ordinary-app/TSOSS defaults.
# Existing native PIF payloads and TSOSS package routing are used unchanged.
MODDIR="/data/adb/modules/playintegrityfix"
AUTO_FLAG="/data/adb/tricky_store/pif_auto_security_patch"

case "$1" in
    --enable) touch "$AUTO_FLAG" || exit 1 ;;
    --disable) rm -f "$AUTO_FLAG" "$MODDIR/system.prop"; exit ;;
esac

if [ -f /data/adb/pif.prop ]; then
    PIFPROP=/data/adb/pif.prop
elif [ -f "$MODDIR/pif.prop" ]; then
    PIFPROP="$MODDIR/pif.prop"
else
    echo '! No pif.prop found' >&2; exit 1
fi

TS_MODPROP=/data/adb/modules/tricky_store/module.prop
[ -f "$TS_MODPROP" ] || { echo '! Tricky Store not found' >&2; exit 1; }
STATE=$(sh "$MODDIR/patch_mode.sh" status) || exit 1
MODE=$(printf '%s\n' "$STATE" | sed -n 's/^mode=//p')
SPLIT_SUPPORTED=$(printf '%s\n' "$STATE" | sed -n 's/^split_supported=//p')
if [ "$MODE" = split ] && [ "$SPLIT_SUPPORTED" != true ]; then
    echo '! Split dates require TSOSS with package patch sections' >&2
    exit 1
fi

if grep -q 'James' "$TS_MODPROP" && ! grep -q 'beakthoven' "$TS_MODPROP"; then
    FILE_NAME=devconfig.toml
else
    FILE_NAME=security_patch.txt
fi
TARGET_FILE="/data/adb/tricky_store/$FILE_NAME"
PROFILE_PATCH=$(sed -n 's/^SECURITY_PATCH=//p' "$PIFPROP" | head -n 1)
LOCAL_PATCH=$(sh "$MODDIR/patch_mode.sh" sync-date "$PROFILE_PATCH") || exit 1
VENDOR_PATCH=$(sh "$MODDIR/patch_mode.sh" sync-vendor-date "$LOCAL_PATCH") || exit 1
SHORT_PATCH=$(printf '%s\n' "$LOCAL_PATCH" | tr -d '-' | cut -c 1-6)
GOOGLE_SHORT=$(printf '%s\n' "$PROFILE_PATCH" | tr -d '-' | cut -c 1-6)

# Preserve an explicit global system=prop, including on mode changes.
SYSTEM=$SHORT_PATCH
if [ -s "$TARGET_FILE" ]; then
    if awk '
        /^# PIF_GOOGLE_PATCH_BEGIN$/ { managed=1; next }
        /^# PIF_GOOGLE_PATCH_END$/ { managed=0; next }
        managed { next }
        /^[[:space:]]*\[/ { section=1 }
        !section && /^[[:space:]]*system[[:space:]]*=[[:space:]]*prop[[:space:]]*(#.*)?$/ { found=1 }
        END { exit !found }
    ' "$TARGET_FILE"; then SYSTEM=prop; fi
fi

umask 077
STAGE="$TARGET_FILE.pif-new.$$"
if [ "$FILE_NAME" = security_patch.txt ]; then
    {
        if [ "$MODE" = split ]; then
            # Boot uses its own device component, as in TSOSS compat.9/10.
            printf 'system=prop\nboot=device_default\nvendor=prop\n'
        else
            printf 'system=%s\nboot=%s\nvendor=%s\n' "$SYSTEM" "$LOCAL_PATCH" "$LOCAL_PATCH"
        fi
        if [ -f "$TARGET_FILE" ]; then
            # Replace only the three global fields. Keep user package sections,
            # comments and unknown keys, and remove our previous managed block.
            awk '
                /^# PIF_GOOGLE_PATCH_BEGIN$/ { managed=1; next }
                /^# PIF_GOOGLE_PATCH_END$/ { managed=0; next }
                managed { next }
                /^[[:space:]]*\[/ { section=1 }
                !section && /^[[:space:]]*(system|boot|vendor|all)[[:space:]]*=/ { next }
                !section && /^[[:space:]]*[0-9][0-9][0-9][0-9]-?[0-9][0-9](-?[0-9][0-9])?[[:space:]]*$/ { next }
                { print }
            ' "$TARGET_FILE" || exit 1
        fi
        if [ "$MODE" = split ]; then
            printf '# PIF_GOOGLE_PATCH_BEGIN\n'
            for pkg in com.google.android.gms com.android.vending; do
                printf '[%s]\nsystem=%s\nboot=%s\nvendor=%s\n' "$pkg" "$GOOGLE_SHORT" "$PROFILE_PATCH" "$PROFILE_PATCH"
            done
            printf '# PIF_GOOGLE_PATCH_END\n'
        fi
    } > "$STAGE" || exit 1
else
    # Preserve the existing non-TSOSS TOML behavior for the three old modes.
    if [ -f "$TARGET_FILE" ]; then
        if grep -q '^securityPatch' "$TARGET_FILE"; then
            sed "s/^securityPatch .*/securityPatch = \"$LOCAL_PATCH\"/" "$TARGET_FILE" > "$STAGE" || exit 1
        else
            { printf 'securityPatch = "%s"\n' "$LOCAL_PATCH"; cat "$TARGET_FILE"; } > "$STAGE" || exit 1
        fi
    else
        printf 'securityPatch = "%s"\n' "$LOCAL_PATCH" > "$STAGE" || exit 1
    fi
fi

PROP_STAGE="$MODDIR/system.prop.pif-new.$$"
printf 'ro.build.version.security_patch=%s\nro.vendor.build.security_patch=%s\n' "$LOCAL_PATCH" "$VENDOR_PATCH" > "$PROP_STAGE" || exit 1
chmod 0644 "$PROP_STAGE" || exit 1

# Include a changed firmware date after OTA even when TSOSS still uses =prop.
# The keybox is never read or rewritten.
if ! cmp -s "$STAGE" "$TARGET_FILE" || ! cmp -s "$PROP_STAGE" "$MODDIR/system.prop"; then
    BACKUP="/data/adb/pif_patch_backups/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$BACKUP" || exit 1
    [ ! -f "$TARGET_FILE" ] || cp -p "$TARGET_FILE" "$BACKUP/$FILE_NAME" || exit 1
    [ ! -f "$MODDIR/system.prop" ] || cp -p "$MODDIR/system.prop" "$BACKUP/system.prop" || exit 1
    cp -p "$PIFPROP" "$BACKUP/pif.prop" || exit 1
    [ ! -f /data/adb/pif_patch_mode.conf ] || cp -p /data/adb/pif_patch_mode.conf "$BACKUP/pif_patch_mode.conf" || exit 1
    printf 'mode=%s\nprofile_date=%s\nlocal_date=%s\nvendor_date=%s\n' "$MODE" "$PROFILE_PATCH" "$LOCAL_PATCH" "$VENDOR_PATCH" > "$BACKUP/info.txt" || exit 1
    echo "- Previous configuration saved: $BACKUP"
fi
# Rename emits MOVED_TO, which the existing TSOSS config observer handles.
chmod 0600 "$STAGE" || exit 1
mv -f "$STAGE" "$TARGET_FILE" || exit 1

mv -f "$PROP_STAGE" "$MODDIR/system.prop" || exit 1

apply_patch_properties() {
    resetprop -n ro.build.version.security_patch "$LOCAL_PATCH" || return 1
    resetprop -n ro.vendor.build.security_patch "$VENDOR_PATCH" || return 1
}

if resetprop --help 2>&1 | grep -q compact; then
    apply_patch_properties || exit 1
    resetprop -c >/dev/null 2>&1 || true
elif resetprop --help 2>&1 | grep -q rebuild; then
    apply_patch_properties || exit 1
    for prop in ro.build.version.security_patch ro.vendor.build.security_patch; do
        resetprop -c "$(resetprop -Z "$prop")" >/dev/null 2>&1 || true
    done
else
    apply_patch_properties || exit 1
fi
echo "- PIF profile: $PROFILE_PATCH; system: $LOCAL_PATCH; vendor: $VENDOR_PATCH; mode: $MODE"
