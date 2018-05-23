#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}
if [ -n "${SHED_PKG_LOCAL_OPTIONS[bootstrap]}" ]; then
    if [ -L /usr/lib/gcc ]; then
        # Remove symlink created earlier in bootstrap
        rm -vf /usr/lib/gcc
    fi
fi
