#!/bin/bash

check() {
    return 255
}

# due to the dependencies below, this dracut module needs to be ordered later than the squash-squashfs and squash-erofs dracut modules

depends() {
    local _module _handler
    local -a _modules=(squash-squashfs squash-erofs)

    for _module in "${_modules[@]}"; do
        if dracut_module_included "$_module"; then
            _handler="$_module"
            break
        fi
    done

    if [[ -z $_handler ]]; then
        if check_module "squash-squashfs"; then
            _handler="squash-squashfs"
        elif check_module "squash-erofs"; then
            _handler="squash-erofs"
        else
            dfatal "Cannot find valid handler for squash. It requires one of: ${_modules[*]}"
            return 1
        fi
    fi

    echo "$_handler"
}
