#!/bin/bash
# Build the SM-A720F iOS root on an exact-USERDATA-size HFSX sparse image.
# Run as root: iOS UID/GID values are part of the boot contract, and
# `hdiutil attach -owners on` needs root.
#   sudo tools/a720f-make-root.sh IPSW_DIR ROOT.sparseimage MOUNT_DIR
# IPSW_DIR holds the iPhone 8 Plus 16.7.16 (20H392) OS, SystemOS and AppOS
# images (087-86694-044, 087-86588-047, 087-86715-047). Only ROOT is written.
set -euo pipefail

if [[ $# != 3 || ${EUID} != 0 ]]; then
    echo "usage (as root): $0 IPSW_DIR ROOT.sparseimage MOUNT_DIR" >&2
    exit 2
fi
ipsw=$1 image=$2 mnt=$3
tools=$(cd "$(dirname "$0")" && pwd)
os_dmg=$ipsw/087-86694-044.dmg
sysos_dmg=$ipsw/087-86588-047.dmg
appos_dmg=$ipsw/087-86715-047.dmg
for f in "$os_dmg" "$sysos_dmg" "$appos_dmg" "$image"; do
    [[ -f $f ]] || { echo "missing $f" >&2; exit 1; }
done

mkdir -p "$mnt/os" "$mnt/sysos" "$mnt/appos" "$mnt/root"
attached=()
cleanup() {
    for dir in "${attached[@]}"; do
        hdiutil detach "$dir" >/dev/null 2>&1 || hdiutil detach -force "$dir" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT
attach() {
    hdiutil attach -nobrowse -owners on -mountpoint "$2" "${@:3}" "$1" >/dev/null
    attached+=("$2")
}
attach "$os_dmg" "$mnt/os" -readonly
attach "$sysos_dmg" "$mnt/sysos" -readonly
attach "$appos_dmg" "$mnt/appos" -readonly
attach "$image" "$mnt/root"

bash "$tools/a5xelte-stage-ios-root.sh" "$mnt/os" "$mnt/sysos" "$mnt/appos" "$mnt/root"
python3 "$tools/sweet-root-tweaks.py" "$mnt/root"
sync
df -h "$mnt/root"
echo "A720F root staged in $image"
