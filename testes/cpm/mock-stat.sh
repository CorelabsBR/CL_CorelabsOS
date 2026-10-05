#!/bin/sh
if [ "$#" -eq 3 ] && [ "$1" = -c ] && [ "$2" = %u ]; then
    printf '%s\n' "${CPM_TEST_UID:-0}"
else
    exec /usr/bin/stat "$@"
fi
