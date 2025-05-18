#!/bin/sh

export DRACUT_SYSTEMD=1
if [ -f /dracut-state.sh ]; then
    . /dracut-state.sh 2> /dev/null
fi
command -v getarg > /dev/null || . /lib/dracut-lib.sh

source_conf /etc/conf.d

type plymouth > /dev/null 2>&1 && plymouth quit

export _rdshell_name="dracut" action="Boot" hook="emergency"
_emergency_action=$(getarg rd.emergency)

if getargbool 1 rd.shell || getarg rd.break; then
    RDSOSREPORT="$(rdsosreport)"
    source_hook "$hook"
    while read -r _tty rest; do
        (
            echo
            echo "$RDSOSREPORT"
            echo
            echo
            echo 'Entering emergency mode. Exit the shell to continue.'
            echo 'Type "journalctl" to view system logs.'
            echo 'You might want to save "/run/initramfs/rdsosreport.txt" to a USB stick or /boot'
            echo 'after mounting them and attach it to a bug report.'
            echo
            echo
        ) > /dev/"$_tty"
    done < /proc/consoles
    [ -f /etc/profile ] && . /etc/profile
    [ -z "$PS1" ] && export PS1="$_name:\${PWD}# "

    if getargbool 0 SYSTEMD_SULOGIN_FORCE; then
        # allows passwordless logins if root account is locked.
        exec sulogin -e
    else
        exec sulogin
    fi
else
    export hook="shutdown-emergency"
    warn "$action has failed. To debug this issue add \"rd.shell rd.debug\" to the kernel command line."
    source_hook "$hook"
    [ -z "$_emergency_action" ] && _emergency_action=poweroff
fi

/bin/rm -f -- /.console_lock

case "$_emergency_action" in
    reboot)
        reboot -f || exit 1
        ;;
    poweroff)
        poweroff -f || exit 1
        ;;
    halt)
        halt -f || exit 1
        ;;
esac

exit 0
