#!/bin/bash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
. /etc/create-missing-root.conf

NEWROOT=${NEWROOT:-'/sysroot'}

ROOT_GUID=${ROOT_GUID:-'4f68bce3-e8cd-4db1-96e7-fbcaf984b709'}
USR_GUID=${USR_GUID:-'8484680c-9521-48c6-9c11-b0720656f69e'}

if ! getargbool 0 create_root.enable; then
    exit 0
fi

create_root_encr_arg=$(getarg create_root.encrypt)
create_root_encr=${create_root_encr_arg:-$NEW_ROOT_ENCRYPT}
if [[ -z $create_root_encr ]]; then
    echo "Defaulting with create_root.encrypt=off"
    create_root_encr="off"
fi
# Only valid values are off and tpm2
if [[ $create_root_encr != "off" && $create_root_encr != "tpm2" ]]; then
    echo "Encrypt allowed options are create_root.encrypt={off/tpm2}"
    exit 1
fi
encrypt_option=$create_root_encr
echo "Using create_root.encrypt=${create_root_encr}"

create_root_pcrs_arg=$(getarg create_root.pcrs)
create_root_pcrs=${create_root_pcrs_arg:-$NEW_ROOT_PCRS}
tpm2_pcrs=""
if [[ $create_root_pcrs =~ ^[0-9]+(\+[0-9]+)*$ ]]; then
    echo "Using pcrs ${create_root_pcrs}"
    tpm2_pcrs="--tpm2-pcrs=${create_root_pcrs}"
elif [ -n "$create_root_pcrs" ]; then
    echo "PCR allowed format: PCR[+PCR]"
    echo "Not using pcrs."
fi
echo "Using create_root.pcrs=${create_root_pcrs}"
systemd_repart_options=""
if [[ $encrypt_option == "tpm2" && $tpm2_pcrs != "" ]]; then
    systemd_repart_options="--tpm2-device=auto $tpm2_pcrs"
fi
echo "Using systemd_repart_options=${systemd_repart_options}"

create_root_fs_arg=$(getarg create_root.fs)
create_root_fs=${create_root_fs_arg:-$NEW_ROOT_FS}
VALID_FS=("ext4" "xfs" "btrfs")
root_fs="ext4"
if [[ ${VALID_FS[*]} =~ ${create_root_fs} ]]; then
    root_fs=$create_root_fs
elif [ -n "$create_root_fs" ]; then
    echo "Allowed filesystems are" "${VALID_FS[@]}"
    echo "Using default fs ext4"
fi
echo "Using create_root.fs=${root_fs}"

create_root_sz_arg=$(getarg create_root.size)
create_root_sz=${create_root_sz_arg:-$NEW_ROOT_MIN_SIZE}
root_min_size=""
if [[ $create_root_sz =~ ^[0-9]+[KMGT]?$ ]]; then
    root_min_size="SizeMinBytes=${create_root_sz}"
    echo "Using ${root_min_size}"
elif [ -n "$create_root_sz" ]; then
    echo "Allowed minimal size is SIZE[K,M,G,T]"
    echo "Not enforcing any minimal size"
fi
echo "Using root_min_size=${root_min_size}"

ROOT=$(lsblk -o NAME,TYPE,PARTTYPE --json | jq -r --arg PARTUUID "$ROOT_GUID" '.blockdevices[] | select(.type == "disk") | .children[] | select(.parttype == $PARTUUID)')

DEVUUID=$(tr -cd '[:print:]' < /sys/firmware/efi/efivars/LoaderDevicePartUUID-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f)
DEVUUID="${DEVUUID,,}"
# Get the disk where the ESP is
DNAME=$(lsblk -o NAME,UUID,PARTUUID --json | jq -r --arg UUID "$DEVUUID" '
  .blockdevices[]? as $disk |
  ($disk.children[]? | select(.partuuid == $UUID) | $disk.name)')

if [ -n "${ROOT:-}" ]; then
    echo "Root already exists! Nothing to do"
    exit 0
fi

USR=$(lsblk -o NAME,TYPE,PARTTYPE --json | jq -r --arg PARTUUID "$USR_GUID" '.blockdevices[] | select(.type == "disk") | .children[] | select(.parttype == $PARTUUID) | .name')

if [ -z "${USR:-}" ]; then
    echo "/usr is not a separate partition! Nothing to do"
    exit 0
fi

# enable prepare-root.service
echo "" > /run/create_new_root

mkdir -p /etc/repart.d
echo -n "[Partition]
Type=root
Format=${root_fs}
Encrypt=${encrypt_option}
${root_min_size}" > /etc/repart.d/encr.conf

# For some reasons quoting systemd_repart_options make systemd-repart fail with
# "invalid argument given".
# shellcheck disable=SC2086
systemd-repart /dev/"$DNAME" --dry-run=no --no-pager --definitions=/etc/repart.d $systemd_repart_options

udevadm settle

ROOT=$(lsblk -o NAME,TYPE,PARTTYPE --json | jq -r --arg PARTUUID "$ROOT_GUID" '.blockdevices[] | select(.type == "disk") | .children[] | select(.parttype == $PARTUUID) | .name')
if [ -z "${ROOT:-}" ]; then
    echo "Root not created! Aborting"
    exit 1
fi

# TODO: should this be another unit?
root_dev="/dev/${ROOT}"
if [[ $encrypt_option == "tpm2" ]]; then
    /usr/lib/systemd/systemd-cryptsetup attach root /dev/gpt-auto-root-luks '' tpm2-measure-pcr=yes
    root_dev="/dev/mapper/root"
fi
mount "$root_dev" "$NEWROOT"

rm -rf "$NEWROOT"/lost+found

mkdir "$NEWROOT"/usr
chmod 755 "$NEWROOT"/usr

# This is to make dracut-mount happy
mkdir "$NEWROOT"/proc "$NEWROOT"/dev "$NEWROOT"/sys
chmod 555 "$NEWROOT"/proc
chmod 755 "$NEWROOT"/dev
chmod 555 "$NEWROOT"/sys

verity_enabled=$(getarg usrhash)
if [ -z "${verity_enabled:-}" ]; then
    mount /dev/"$USR" "$NEWROOT"/usr
fi

# keep /sysroot and /usr mounted
