#!/bin/bash

check() {
    return 255
}

installkernel() {
    hostonly='' instmods \
        xen-blkfront \
        xen-evtchn \
        xen-gntalloc \
        xen-gntdev \
        xen-pciback \
        xen-privcmd \
        xen-scsifront \
        xenfs
}
