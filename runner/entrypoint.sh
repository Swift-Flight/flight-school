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
#
# One subdirectory per execution tier, each populated independently: a
# runner serves whichever tier a session leases, so both have to be there
# before it accepts any lease.
set -e

for tier in snippet app; do
    if [ ! -f "/workspace/$tier/Package.swift" ]; then
        mkdir -p "/workspace/$tier"
        cp -r "/opt/workspace-template-$tier/." "/workspace/$tier/"
    fi
done

exec "$@"
