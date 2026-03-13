#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# Devicetree based platforms may need board / model specific firmwares in
# the initrd. E.g. Qualcomm Snapdragon Windows-on-Arm (WoA) laptops need model
# specific firmware files in the initrd for the ADSP/Type-C controller.
# The filenames for these firmware files are specified in "firmware-name"
# devicetree properties, this module copies any such files to the initrd.

# called by dracut
check() {
    local _arch=${DRACUT_ARCH:-$(uname -m)}
    # Restrict to aarch64 for now, may be used on other archs in the future
    [ "$_arch" = "aarch64" ] || return 1
    if [[ $hostonly ]]; then
        [ -d /sys/firmware/devicetree/base ] || return 1
    else
        # ATM install_generic only copies qcom model specific firmwares
        [ -d /lib/firmware/qcom ] || return 1
    fi
    return 0
}

# hostonly install (hostonly / generic use completely different approaches)
install_hostonly() {
    local _fw_names=""
    # contents of firmware-name file is 0 delimited
    while read -r -d $'\0' fw; do
        _fw_names="${_fw_names} $fw"
    done < <(find /sys/firmware/devicetree/base -name firmware-name -exec cat {} \;)

    local _fw_files=""
    for i in ${_fw_names}; do
        # add '*' after firmware-name for .gz, etc. compression
        _fw_files="${_fw_files} /lib/firmware/$i*"
    done

    # shellcheck disable=SC2086 # globbing is wanted here
    inst_multiple -o ${_fw_files}
}

# generic install (hostonly / generic use completely different approaches)
install_generic() {
    # ATM only qcom WoA laptops need this
    for soc in qcom/sc8280xp qcom/x1e80100; do
        # add '*' after mbn for .gz, etc. compression
        for fw in \
            "${dracutsysrootdir-}/lib/firmware/$soc"/*/*/*.mbn* \
            "${dracutsysrootdir-}/lib/firmware/$soc"/*/*/*.elf*; do
            [ -f "$fw" ] || continue
            fw=${fw#"${dracutsysrootdir-}"}
            inst_dir "${fw%/*}"
            $DRACUT_CP -L -t "${initdir}${fw%/*}" "$fw"
        done
    done
}

# called by dracut
install() {
    if [[ $hostonly ]]; then
        install_hostonly
    else
        install_generic
    fi
}
