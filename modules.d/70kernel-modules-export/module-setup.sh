#!/bin/bash

check() {
    return 255
}

depends() {
    echo base
}

install() {
    inst_hook pre-pivot 90 "$moddir/modules-export.sh"
}
