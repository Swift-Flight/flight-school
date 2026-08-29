#!/bin/sh
# Populates /workspace the first time this container ever sees it empty —
# a fresh tmpfs mount (PLAN §5: read-only rootfs except a workspace tmpfs)
# starts with nothing, discarding anything baked into the image at that
# path. Copying the *source* (Package.swift/Package.resolved/Sources/)
# rather than a prebuilt `.build` is deliberate: a `.build` relocated
# across paths fails outright (Clang's module cache bakes in the absolute
# path it was compiled at — verified directly while building this image),
# while source files carry no such sensitivity. The supervisor's own
# warm-up build (Main.swift) does the actual compiling right after this
# runs, so the workspace becomes warm regardless of whether /workspace
# started fresh or already had a previous session's live `.build` in it.
set -e

if [ ! -f /workspace/Package.swift ]; then
    cp -r /opt/workspace-template/. /workspace/
fi

exec "$@"
