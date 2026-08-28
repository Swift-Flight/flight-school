# The runner (PLAN §4): a prebuilt-source Hangar-importing snippet
# workspace plus the supervisor that leases it out, writes learner code
# into it, and runs it with a wall-clock cap. Full toolchain persists into
# the runtime image on purpose — unlike a typical multi-stage build that
# slims to just a binary, this container's whole job is repeatedly
# invoking `swift build`, so the toolchain has to still be there after the
# "build" stage.

FROM swift:6.3.3 AS supervisor-build
WORKDIR /supervisor-src
COPY supervisor/Package.swift supervisor/Package.resolved ./
COPY supervisor/Sources ./Sources
RUN swift build -c release

FROM swift:6.3.3
# Explicit, fixed uid/gid — not whatever `useradd` happens to assign
# (turned out to be 1001 here, not the commonly-assumed 1000, caught only
# by actually checking rather than guessing when wiring up the tmpfs
# mount's `uid=`/`gid=` options, which take a number, not a username).
# Anything orchestrating this container needs a stable number to depend
# on, not an implementation detail of one base image's `useradd` defaults.
RUN groupadd --gid 10001 runner && \
    useradd --uid 10001 --gid runner --create-home --shell /usr/sbin/nologin runner

# The workspace *templates* — source and fetched dependencies, but never
# compiled here. One per execution tier (PLAN §4: "prebuilt workspaces,
# one per execution tier/template"), so the runner pool stays
# undifferentiated and any runner can serve any tier; which one a session
# gets is decided at `/lease` time, not by which container it lands on.
#
# PLAN §5 calls for `/workspace` to be a tmpfs mount at container runtime
# (read-only rootfs otherwise, and no network egress except Postgres),
# which starts empty on every container start, discarding anything baked
# into the image at that exact path. entrypoint.sh copies these templates
# into /workspace/<tier> the first time each is empty, and the
# supervisor's own warm-up build (Main.swift) does the real compile there,
# fresh, every time. Two things had to be true at once and were verified
# separately, not assumed:
# - `swift package resolve` (fetches dependency *source* into
#   .build/checkouts, compiles nothing) has to run here, at image-build
#   time, on real network access — without it, the runtime warm-up build
#   would need to `git clone` Hangar/PostgresNIO/SwiftNIO itself, which a
#   network-isolated runner can never do.
# - `swift build` must NOT also run here. A `.build` that's already
#   *compiled* fails outright once relocated to a different path —
#   Clang's module cache bakes in the absolute path it was built at —
#   verified directly by building this image the wrong way first.
#   Resolving-without-building sidesteps that: the checkouts carry no
#   path-sensitive compiled state, only source.
WORKDIR /opt/workspace-template-snippet
COPY workspace/Package.swift workspace/Package.resolved ./
COPY workspace/Sources ./Sources
RUN swift package resolve

# The app tier's workspace: the vendored flight-cli `skeleton` template —
# a real, whole Flight application rather than one file. See
# workspace-app/VENDORED.md for provenance and why Package.resolved is
# committed here when the upstream template doesn't carry one.
WORKDIR /opt/workspace-template-app
COPY workspace-app/Package.swift workspace-app/Package.resolved workspace-app/flight.yaml ./
COPY workspace-app/Sources ./Sources
COPY workspace-app/Tests ./Tests
RUN swift package resolve

# The pristine references /reset and /release restore from — never built
# or run themselves.
#
# The snippet tier's is one file, the only one that's ever allowed to
# change. The app tier's is the two editable subtrees, and deliberately
# *not* the whole project: restoring it must not touch `.build` (which
# sits at the project root), or every reset would throw away the warm
# build this tier exists to keep and make the next run a cold one.
RUN mkdir -p /workspace-pristine/snippet/Sources/exercise && \
    cp /opt/workspace-template-snippet/Sources/exercise/main.swift \
       /workspace-pristine/snippet/Sources/exercise/main.swift && \
    mkdir -p /workspace-pristine/app/Sources /workspace-pristine/app/Tests && \
    cp -r /opt/workspace-template-app/Sources/App /workspace-pristine/app/Sources/App && \
    cp -r /opt/workspace-template-app/Tests/AppTests /workspace-pristine/app/Tests/AppTests

COPY --from=supervisor-build /supervisor-src/.build/release/Supervisor /app/supervisor
COPY supervisor/flight.yaml /app/flight.yaml
COPY entrypoint.sh /app/entrypoint.sh

# /workspace itself is created empty here — either the tmpfs mount takes
# over this path at container start (production shape), or, absent that
# mount, this is what entrypoint.sh finds empty and populates from the
# template on first run, exactly the same code path either way.
RUN mkdir -p /workspace && \
    chown -R runner:runner /opt/workspace-template-snippet /opt/workspace-template-app \
        /workspace /workspace-pristine /app && \
    chmod +x /app/entrypoint.sh

# SwiftPM and Clang need a writable HOME for their own caches
# (~/.swiftpm, ~/.cache/org.swift.swiftpm, ~/.cache/clang/ModuleCache) —
# not just the workspace itself. /home/runner sits on the read-only
# rootfs, so without this the warm-up build fails outright ("Read-only
# file system") the moment it needs to write a module cache entry,
# caught only by actually running with --read-only rather than assuming
# the workspace tmpfs alone was enough. Redirecting HOME into the
# already-writable workspace tmpfs covers it without a second mount.
ENV HOME=/workspace/.home

USER runner
WORKDIR /app
EXPOSE 9000
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/supervisor"]
