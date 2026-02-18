#!/bin/bash
# In POSIX sh, ulimit -c is undefined. [SC3045], so we use bash here

# crash inside the initramfs (before switch_root)

# unlimited coredump size
ulimit -c unlimited

# start a process, so that we can crash it
sleep 86400 &

# save the process PID
PID=$!

# send the SIGABRT (Abort) signal to crash the process
kill -6 "$PID"

# Loop waiting for that $PID to disappear
while [ -d "/proc/$PID" ]; do
    sleep 1
done
