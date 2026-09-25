## What this Feature adds

Tutor is a BB plugin (source in [`plugin/`](plugin), design in
[`docs/tutor/`](../../docs/tutor/DESIGN.md)) plus the lifecycle glue that puts
it into the [bb Feature](../bb)'s standalone server. It inherits that
Feature's security model unchanged: one learner-owned BB bound to `127.0.0.1`,
only the server port forwarded (keep it **Private** in the Codespaces Ports
view), no credentials installed or copied, and no host-daemon forwarding. The
Tutor hooks run as the remote user, talk to BB only over its loopback API, and
start no processes of their own.

## Install order

The plugin is built with the bb Feature's packaged CLI, so bb must be
installed first. This Feature deliberately has no `installsAfter` yet: the
devcontainer CLI resolves every `installsAfter` reference, and the bb Feature
is not published, so a reference to it fails every build. Each configuration
therefore pins the order with `overrideFeatureInstallOrder` (bb, then tutor),
and `install.sh` fails with that advice if bb is missing. Add
`"installsAfter": ["ghcr.io/lean-software-production/devcontainer-features/bb"]`
once bb is published. It will still not order a *local* bb, because
`installsAfter` only matches Features of the same kind, so local
compositions keep the override.

## Image build (`install.sh`, root)

1. Validates the options: absolute paths without dot segments, quotes, control
   characters or shell metacharacters; `courseRepo` empty or an `https://` URL
   without credentials, query or fragment.
2. Checks that the bb Feature is installed in `standalone` mode.
3. Stages the plugin at `/usr/local/share/tutor/plugin`, root-owned and not
   writable by the learner, runs `npm ci --omit=dev --ignore-scripts` (bb
   shims the SDK and UI packages for plugins, so only runtime dependencies
   are needed), and runs `bb plugin build` with the bb Feature's packaged CLI.
4. bb downloads its plugin build toolchain (esbuild, Tailwind) on first use
   into `<dataDir>/plugins/toolchain-<pins>`. The build runs against a
   throwaway state directory and the toolchain is kept at
   `/usr/local/share/tutor/toolchain`, so no start-up needs the network.
5. Writes `/usr/local/etc/tutor/config.json` (`{ "course", "factory" }`, the
   contract the plugin reads; `factory` is omitted when empty) and
   `/usr/local/share/tutor/options.tsv` (for the hooks), both root-owned 0644,
   plus `plugin.sha256`, a digest of the staged plugin without `node_modules`
   and `dist`.

## Lifecycle hooks (remote user)

`postCreateCommand` runs `tutor-feature-bootstrap`: if `course` does not exist
and `courseRepo` is set, it runs `git clone -- <courseRepo> <course>`. A clone
that cannot happen (no writable parent, no network) is reported with the
command to run, and never fails the hook, because a failing lifecycle command
would stop BB's own start-up hook. The plugin then shows the student that the
course is missing.

`postStartCommand` runs `tutor-feature-autostart`. Feature hooks run in install
order, so it follows `bb-feature-autostart`. It:

- validates both Features' root-owned option files (owner, mode, content)
  and derives `BB_SERVER_URL`, `BB_DATA_DIR` and `BB_HOST_DAEMON_PORT` from
  the bb Feature's options, because the bb Feature does not export them. Every
  bb CLI call gets exactly those in a clean environment, with the packaged
  CLI's absolute path;
- serialises runs with a lock in `<dataDir>/.tutor-feature/` and logs there
  (`autostart.log`);
- polls `bb plugin list` for up to 120 s (`TUTOR_FEATURE_WAIT_SECONDS`
  overrides this when the hook is run by hand). Without bb `autoStart` it probes
  once and, if BB is down, tells the student to start BB and re-run the hook;
- path-installs the plugin. A path install rebuilds the frontend bundle into
  the plugin's `dist/`, so BB gets a user-owned copy per build at
  `<dataDir>/.tutor-feature/plugin-<digest>`: the small source tree is
  copied and the root-owned `node_modules` is symlinked. The install is
  skipped when BB already has the plugin from that exact directory, so
  restarts do nothing and a rebuilt image (new digest) reinstalls once and
  deletes the old copy. Before installing, it seeds the kept toolchain into
  `<dataDir>/plugins/` if bb has none; bb verifies a toolchain's pins file
  before using it;
- registers `course` and `factory` as BB projects when the directory exists
  and no project has that local source path yet (the plugin itself never
  creates projects);
- selects the course rail with
  `bb settings ui set sidebar.threadListProvider tutor/course-rail`, once per
  state directory, only when the plugin is installed, `selectRail` is true,
  and the current value is bb's default (`thread-list/thread-list`). A marker
  file records the decision, so a student who switches back keeps their
  choice.

The hook fails (non-zero) when BB never answers or the plugin cannot be
installed or does not reach `running`; a project or rail step that fails is
reported and also makes the hook fail, after the other steps have run.

## Composing it locally

Dev Containers only accepts local Features beneath `.devcontainer/`, and the
devcontainer CLI (which Codespaces uses) fails with "Failed to fetch feature"
on a Feature folder that is a symlink. The Codespace entry point therefore
holds committed copies of `src/bb` and `src/tutor`, refreshed by
[`.devcontainer/tutor/sync-features.sh`](../../.devcontainer/tutor/sync-features.sh)
and checked in CI with `--check`. See
[`.devcontainer/tutor/README.md`](../../.devcontainer/tutor/README.md).

## Validation boundary

CI runs:

- the Feature scenarios in [`test/tutor`](../../test/tutor):
  - `standalone`: prebuilt, root-owned plugin with runtime dependencies only;
    course cloned; plugin running from its digest copy; toolchain seeded, not
    downloaded; projects and rail; idempotent restarts; the student's rail
    choice kept; and, with the credential-free
    [scripted provider](../../test/tutor/fixtures/scripted-provider), a thread
    Tutor did not spawn is neither offered Tutor's tools nor able to run one.
  - `no_clone_no_rail`: an empty `courseRepo` and `selectRail: false` in the
    default state directory;
- hermetic tests of the option validation and of every hook decision against
  a fake bb CLI;
- a bring-up of the Codespace entry point itself (`codespace-entry.sh`, on
  ports 48886/48887 and with `/workspaces` paths moved under the home
  directory);
- the check that the entry point's Feature copies match `src/`.

A real GitHub Codespace remains the owner's acceptance step: the private
forwarded port, `/workspaces` ownership and persistence of
`/workspaces/.bb-state`, the rail in a real browser, and provider sign-in.
