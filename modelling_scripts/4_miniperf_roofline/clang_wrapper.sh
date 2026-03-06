#!/bin/bash
# Wrapper around clang++-19 that appends -Wno-error flags AFTER all other flags.
# This ensures they override -Werror from Autoware's CMakeLists.txt.
exec /usr/bin/clang++-19 --gcc-install-dir=/usr/lib/gcc/aarch64-linux-gnu/11 "$@" \
    -Wno-error \
    -Wno-enum-constexpr-conversion \
    -Wno-deprecated-copy \
    -Wno-c11-extensions \
    -Wno-unused-lambda-capture \
    -Wno-deprecated-declarations \
    -Wno-deprecated \
    -Wno-dtor-name \
    -Wno-extra-semi
