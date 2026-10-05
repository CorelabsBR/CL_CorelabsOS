#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -u ]; then
    printf '%s\n' "${CPM_TEST_UID:-0}"
else
    exec /usr/bin/id "$@"
fi
