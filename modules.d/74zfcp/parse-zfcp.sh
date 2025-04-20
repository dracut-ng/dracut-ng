#!/bin/sh

getargbool 1 rd.zfcp.conf || rm /etc/zfcp.conf

zfcp_cio_free
