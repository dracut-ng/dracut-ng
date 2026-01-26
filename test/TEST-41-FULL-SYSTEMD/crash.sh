#!/bin/bash

# crash inside the initramfs (before switch_root)

# unlimited coredump size
ulimit -c unlimited

# start a process, so that we can crash it
bash -c 'while true; do echo "Looping forever..."; sleep 5; done' > /dev/null 2>&1 &

# save the process PID
PID=$!

# send the SIGABRT (Abort) signal to crash the process
kill -6 "$PID"

# give a bit time to create the coredump
sleep 10
