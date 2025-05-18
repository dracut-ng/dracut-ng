#!/bin/bash

# called by dracut
install() {
    local _i

    # Fixme: would be nice if we didn't have to guess, which rules to grab....
    # ultimately, /lib/initramfs/rules.d or somesuch which includes links/copies
    # of the rules we want so that we just copy those in would be best
    inst_multiple udevadm cat uname blkid

    [[ -d ${initdir}/$systemdutildir ]] || mkdir -p "${initdir}/$systemdutildir"
    for _i in "${systemdutildir}"/systemd-udevd "${udevdir}"/udevd /sbin/udevd; do
        [[ -x $dracutsysrootdir$_i ]] || continue
        inst "$_i"

        if ! [[ -f ${initdir}${systemdutildir}/systemd-udevd ]]; then
            ln -fs "$_i" "${initdir}${systemdutildir}"/systemd-udevd
        fi
        break
    done
    if ! [[ -e ${initdir}${systemdutildir}/systemd-udevd ]]; then
        derror "Cannot find [systemd-]udevd binary!"
        exit 1
    fi

    inst_rules \
        50-udev-default.rules \
        55-scsi-sg3_id.rules \
        58-scsi-sg3_symlink.rules \
        59-scsi-sg3_utils.rules \
        60-autosuspend.rules \
        60-block.rules \
        60-cdrom_id.rules \
        60-drm.rules \
        60-evdev.rules \
        60-fido-id.rules \
        60-input-id.rules \
        60-persistent-alsa.rules \
        60-persistent-input.rules \
        60-persistent-storage-tape.rules \
        60-persistent-storage.rules \
        60-persistent-v4l.rules \
        60-sensor.rules \
        60-serial.rules \
        64-btrfs.rules \
        70-joystick.rules \
        70-memory.rules \
        70-mouse.rules \
        70-touchpad.rules \
        70-uaccess.rules \
        71-seat.rules \
        73-seat-late.rules \
        75-net-description.rules \
        75-probe_mtd.rules \
        78-sound-card.rules \
        80-drivers.rules \
        80-net-name-slot.rules \
        80-net-setup-link.rules \
        81-net-dhcp.rules \
        95-udev-late.rules

    {
        for i in cdrom tape dialout floppy; do
            if ! grep -q "^$i:" "$initdir"/etc/group 2> /dev/null; then
                if ! grep "^$i:" "$dracutsysrootdir"/etc/group 2> /dev/null; then
                    case $i in
                        cdrom) echo "$i:x:11:" ;;
                        dialout) echo "$i:x:18:" ;;
                        floppy) echo "$i:x:19:" ;;
                        tape) echo "$i:x:33:" ;;
                    esac
                fi
            fi
        done
    } >> "$initdir/etc/group"

    inst_multiple -o \
        "${udevdir}"/ata_id \
        "${udevdir}"/cdrom_id \
        "${udevdir}"/create_floppy_devices \
        "${udevdir}"/dmi_memory_id \
        "${udevdir}"/fido_id \
        "${udevdir}"/fw_unit_symlinks.sh \
        "${udevdir}"/hid2hci \
        "${udevdir}"/input_id \
        "${udevdir}"/mtd_probe \
        "${udevdir}"/mtp-probe \
        "${udevdir}"/path_id \
        "${udevdir}"/scsi_id \
        "${udevdir}"/usb_id \
        "${udevdir}"/v4l_id \
        "${udevdir}"/udev.conf \
        "${udevdir}"/udev.conf.d/*.conf

    # Install required libraries.
    _arch=${DRACUT_ARCH:-$(uname -m)}
    inst_libdir_file \
        {"tls/$_arch/",tls/,"$_arch/",}"libkmod.so*" \
        {"tls/$_arch/",tls/,"$_arch/",}"libnss_files*"

    # Install the hosts local user configurations if enabled.
    if [[ $hostonly ]]; then
        inst_dir "$udevconfdir"
        inst_multiple -H -o \
            "$udevconfdir"/udev.conf \
            "$udevconfdir/udev.conf.d/*.conf" \
            "$udevrulesconfdir/*.rules"
    fi
}
