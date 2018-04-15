#!/bin/bash
if [ "$SHED_BUILD_MODE" == 'bootstrap' ]; then
    if [ -L /usr/lib/gcc ]; then
        # Remove symlink created earlier in bootstrap
        rm -vf /usr/lib/gcc
    fi
fi