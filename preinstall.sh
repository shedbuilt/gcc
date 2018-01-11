#!/bin/bash
if [ -L /usr/lib/gcc ]; then
   # Remove symlink created during bootstrap
   rm -vf /usr/lib/gcc
fi
