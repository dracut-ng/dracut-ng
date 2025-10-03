#!/bin/sh
set -eu

# required binaries: grep

i=0
while read -r hook; do
    if ! grep -q "^${hook}$" /run/dracut_hooks_ran; then
        echo "Hook '${hook}' was not run in the initrd, but should have." >> /run/failed
    fi
    i=$((i + 1))
done < /expected_hooks_run
echo "Checked $i hooks that should have been run."

i=0
while read -r hook; do
    if grep -q "^${hook}$" /run/dracut_hooks_ran; then
        echo "Hook '${hook}' was run in the initrd, but should not." >> /run/failed
    fi
    i=$((i + 1))
done < /expected_hooks_not_run
echo "Checked $i hooks that should not have been run."
