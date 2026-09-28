
# Tutor coached course for BB (tutor)

Adds the Tutor BB plugin (a checksummed bb-plugin-tutor release: the pinned one by default, or the newest with pluginVersion 'latest') to the bb Feature's standalone server: a course outline in the sidebar and a coach thread per lesson that works one Gherkin Rule at a time. Requires the bb Feature in standalone mode.

## Example Usage

```json
"features": {
    "ghcr.io/lean-software-production/devcontainer-features/tutor:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| course | Absolute path of the course checkout the plugin reads. | string | /workspaces/tutorial |
| courseRepo | HTTPS Git URL cloned into 'course' after the container is created, if 'course' does not exist yet. Empty never clones. | string | https://github.com/lean-software-production/tutorial.git |
| starter | Optional absolute path of the student's repo: a capstone-project-starter checkout or fork, such as /workspaces/capstone-project-starter, or ${containerWorkspaceFolder} when the starter is the workspace itself. When it exists it is registered as the BB project, named after its folder, and config.json names it as the plugin's repo. Must differ from 'course'. Empty means no starter. | string | - |
| starterRepo | HTTPS Git URL cloned into 'starter' after the container is created, if 'starter' does not exist yet. Needs 'starter'. Empty never clones. | string | - |
| factory | Legacy, optional: absolute path of the student's factory, the folder holding spec/ and ITERATION, such as <starter>/tetris/.factory. It is written to config.json as a hint for the plugin, and is registered as the BB project only when 'starter' is empty (the behaviour before 0.6.0). New configurations set 'starter' and leave this empty. | string | - |
| selectOutline | Select the Tutor course outline as BB's sidebar thread list once, unless another thread list was chosen already. | boolean | true |
| disablePlugins | Comma-separated BB plugin ids to switch off once per BB state directory, so a student can turn any back on. Plugins that are not installed are skipped; tutor, thread-list, provider-* and the workspace environments are never switched off. Empty switches off nothing. | string | automations,workflows,tasks,scheduled-send,github,browser-automation,agent-annotations,connect,plugin-api-docs,plugin-api-tester,theme-preview,keep-awake,account-pool,environment-modal-sandbox |
| theme | BB theme id to select once per BB state directory, only while BB's default theme is active. Empty leaves BB's theme alone. | string | plugin:tutor:sketchbook |
| lightTheme | Pin BB's Settings > Appearance > Theme to Light: every page load resets it, so Dark or System lasts only until a reload. false leaves BB's choice to the learner. | boolean | true |
| appIcons | Icons BB's web app shows in browser tabs, bookmarks and home screens: 'lsp' replaces every BB icon with the LSP one, 'bb' keeps BB's. | string | lsp |
| pluginVersion | bb-plugin-tutor release downloaded from GitHub at image build: a plain semantic version (no 'v' prefix or range), or 'latest'. The default is the release this Feature pins, verified against its pinned SHA-256; any other version needs pluginSha256. 'latest' resolves to the newest release when the image is built (a prebuilt image keeps it until rebuilt) and is checked only against that release's own .sha256, which catches corruption but not a compromised release. | string | 0.3.0 |
| pluginSha256 | SHA-256 (64 lower-case hex digits) of bb-plugin-tutor-<pluginVersion>.tgz. Required when pluginVersion is an explicit version other than the pinned default; with the default it must be empty or equal the pin; with 'latest' it must be empty. For an explicit version the release's own .sha256 file is never trusted. | string | - |

## What this Feature adds

Tutor is a BB plugin, developed in its own repository,
[lean-software-production/bb-plugin-tutor](https://github.com/lean-software-production/bb-plugin-tutor)
(design in its [`docs/DESIGN.md`](https://github.com/lean-software-production/bb-plugin-tutor/blob/main/docs/DESIGN.md),
local dev harness in
[`scripts/tutor-dev/`](https://github.com/lean-software-production/bb-plugin-tutor/tree/main/scripts/tutor-dev)).
This Feature is the lifecycle glue that puts a release of it (the pinned one by
default) into the
[bb Feature](../bb)'s standalone server. It inherits that
Feature's security model unchanged: one learner-owned BB bound to `127.0.0.1`,
only the server port forwarded (keep it **Private** in the Codespaces Ports
view), no credentials installed or copied, and no host-daemon forwarding. The
Tutor hooks run as the remote user, talk to BB only over its loopback API, and
start no processes of their own. The one long-running process, the optional
`tutor-keepalive` loop, only reads a timestamp file and prints to its own
terminal.

## Install order

The plugin is built with the bb Feature's packaged CLI, so bb must be
installed first. Since 0.6.0 the Feature declares
`"installsAfter": ["ghcr.io/lean-software-production/devcontainer-features/bb"]`,
which orders the published bb before it. The devcontainer CLI resolves every
`installsAfter` reference, so a build needs to reach `ghcr.io` for it even
when bb is local. It does not order a *local* bb, because `installsAfter` only
matches Features of the same kind, so local compositions (this repository's
scenarios and Codespace entry point) keep `overrideFeatureInstallOrder` (bb,
then tutor), and `install.sh` still fails with that advice if bb is missing.

## Where the plugin comes from

The Feature carries no plugin source. At image build it downloads one release
of [bb-plugin-tutor](https://github.com/lean-software-production/bb-plugin-tutor):

```
https://github.com/lean-software-production/bb-plugin-tutor/releases/download/v<pluginVersion>/bb-plugin-tutor-<pluginVersion>.tgz
```

a gzip tar with one top-level directory `bb-plugin-tutor-<pluginVersion>/`
holding `package.json`, `package-lock.json` and the sources (no `dist/`, no
`node_modules`).

**Choosing the release.** `pluginVersion` picks one of three ways, each
covered below: the default (the release this Feature version pins, with its
pinned SHA-256), an explicit version with the `pluginSha256` you computed, or
`latest`, the newest release, checked only against its own `.sha256`. The
installed version is printed at the end of the image build (`Installed the
Tutor plugin <version> ...`, read from the staged `package.json`, so `latest`
shows the version it resolved to).

**Pinning.** Each Feature version pins one plugin release and its SHA-256 in
[`plugin-pin.sh`](plugin-pin.sh), the only place either is recorded (the
`pluginVersion` default in `devcontainer-feature.json` must name the same
version; `test/tutor/plugin-fetch-hermetic.sh` checks that). With the default
`pluginVersion` the download is verified against that pinned SHA-256, and a
`pluginSha256` given as well must equal it: a build fails rather than guess
which of two checksums was meant. The release also publishes a `.sha256`
file; for a pinned or explicit version the Feature never reads it, since
anyone able to replace the tarball could replace that too.

**Using a newer plugin release** without waiting for a new Feature version:
compute the tarball's SHA-256 yourself and set both options.

```sh
v=0.3.0
curl -fsSLO "https://github.com/lean-software-production/bb-plugin-tutor/releases/download/v$v/bb-plugin-tutor-$v.tgz"
sha256sum "bb-plugin-tutor-$v.tgz"
```

```jsonc
"ghcr.io/lean-software-production/devcontainer-features/tutor:0": {
  "pluginVersion": "0.3.0",
  "pluginSha256": "<the 64 hex digits sha256sum printed>"
}
```

`pluginSha256` is required whenever `pluginVersion` is an explicit version
other than the pinned one. The plugin must still suit the bb version the bb
Feature installs and read `config.json` schema version 1.

**Tracking the newest release** (`"pluginVersion": "latest"`, which this
repository's course Codespace uses). At image build the Feature follows the
redirect of
`https://github.com/lean-software-production/bb-plugin-tutor/releases/latest`
(not the GitHub API, so no rate limit applies) and reads the version from the
tag it lands on, `.../releases/tag/v<version>`, which must be a plain semantic
version; with no release published, or an unexpected tag, the build fails. It
logs `tutor plugin fetch: latest is <version>`, downloads that release's
`bb-plugin-tutor-<version>.tgz.sha256`, requires exactly one line of 64
lower-case hex digits naming `bb-plugin-tutor-<version>.tgz`, and then
downloads and screens the tarball exactly as for a pinned version, against
that digest. Two caveats:

- **Trust.** With no pin, the release's own `.sha256` is the only check. It
  catches a corrupted or truncated download, not a compromised release:
  whoever can publish a release can publish a matching `.sha256`. Use an
  explicit version and `pluginSha256` where that matters. `pluginSha256` must
  be empty with `latest`, since no checksum can apply to a version not yet
  known.
- **When it is resolved.** Only when the image is built. A Codespaces
  prebuild, or any cached image, keeps the release it resolved until the
  image is rebuilt; a new plugin release reaches students on the next
  prebuild or rebuild, not on restart. The same configuration built on two
  days can install two different releases.

**Network.** The image build needs HTTPS access to `github.com` (release
downloads redirect to `objects.githubusercontent.com`), as well as to the npm
registry for `npm ci` and bb's plugin build toolchain. Nothing is downloaded
when the container starts, apart from the optional course and starter clones.

## Image build (`install.sh`, root)

1. Validates the options: absolute paths without dot segments, quotes, control
   characters or shell metacharacters; `factory` and `starter` each different
   from `course`; a `starter` still holding `${...}` (a variable such as
   `${containerWorkspaceFolder}` that the tool building the image did not
   substitute) fails with a message saying so; `courseRepo` and `starterRepo` empty or an `https://` URL
   without credentials, query or fragment; `starterRepo` only with a
   `starter`; `pluginVersion` `latest` or a plain semantic version
   (`MAJOR.MINOR.PATCH` with an optional pre-release; no `v` prefix, range or
   build metadata); `pluginSha256` empty or 64 lower-case hex digits,
   required for any explicit `pluginVersion` but the pinned one, equal to the
   pin for that one, and empty for `latest`.
2. Checks that the bb Feature is installed in `standalone` mode.
3. For `latest`, resolves the version and reads the expected SHA-256 from
   the release's `.sha256` (see above). Downloads the plugin release with
   `curl` (HTTPS and TLS 1.2 or later only, redirects included, with
   retries) and checks its SHA-256 before reading it. It then lists the archive and refuses any member that is absolute, has
   a `..` (or empty or `.`) segment, lies outside `bb-plugin-tutor-<version>/`,
   is a symlink whose target is absolute or contains `..`, is a hard link
   outside that directory, is not a plain file, directory or link, or has a
   name with control characters, quotes or backslashes. Only then does it
   extract, without the archive's owners or modes, and check that
   `package.json` names `bb-plugin-tutor` at `pluginVersion`, that
   `package-lock.json` exists, and that there is no `dist/` or
   `node_modules`. The logic is in `bin/tutor-plugin-fetch.sh`, used only at
   build time.
4. Stages the plugin at `/usr/local/share/tutor/plugin`, root-owned and not
   writable by the learner, runs `npm ci --omit=dev --ignore-scripts` (bb
   shims the SDK and UI packages for plugins, so only runtime dependencies
   are needed), and runs `bb plugin build` with the bb Feature's packaged CLI.
5. bb downloads its plugin build toolchain (esbuild, Tailwind) on first use
   into `<dataDir>/plugins/toolchain-<pins>`. The build runs against a
   throwaway state directory and the toolchain is kept at
   `/usr/local/share/tutor/toolchain`, so no start-up needs the network.
6. Writes `/usr/local/etc/tutor/config.json` (`{ "schemaVersion": 1,
   "course", "repo", "factory", "dataDir" }`, the contract the plugin reads;
   the plugin treats a missing `schemaVersion` as 1, refuses any other and
   ignores keys it does not know, so 0.6.0's `repo` needed no new version.
   `repo` is the `starter` option, the student's repo, and `factory` the
   legacy `factory` option; each is omitted when empty) and `/usr/local/share/tutor/options.tsv` (for
   the hooks), both root-owned 0644, plus `plugin.sha256`, a digest of the
   staged plugin, including the built `dist/` but not `node_modules`. `dataDir` is the BB state
   directory the hooks use: the bb Feature's `dataDir`, or `<remote user's
   home>/.bb` when that is empty (from `_REMOTE_USER_HOME`; omitted if the
   home is unknown). The plugin writes the keep-alive's activity file beneath
   it.
7. Validates `disablePlugins` (comma-separated ids of lower-case letters,
   digits and `-`) and `theme` (a theme id such as `plugin:tutor:sketchbook`), and
   warns about any listed plugin Tutor needs. `lightTheme` must be `true` or
   `false` and `appIcons` `lsp` or `bb`.
8. Patches BB's web client for `lightTheme` and `appIcons` (next section).
   This step only ever warns: it never fails the build.

## Light theme and LSP icons (`lightTheme`, `appIcons`)

The course Codespace supports BB's light mode only, and shows the LSP icon
rather than BB's. Both are patches to the installed bb-app's web client,
`<bb-app>/app/dist`, made once at image build by `bin/tutor-bb-brand.sh`
(used only at build time). It finds bb-app by following the bb Feature's
launcher (or `bb-app`/`bb` on `PATH`) to its real file and walking up to the
`package.json` named `bb-app`, falling back to the bb Feature's npm prefix
(`/usr/local/share/bb/npm/lib/node_modules/bb-app`).

**`lightTheme` (default `true`).** BB keeps Settings → Appearance → Theme
(`light`, `dark` or `system`, default `system`) only in the browser's
`localStorage`, under `bb.theme`: there is no server setting, CLI or plugin
API for it. `app/dist/index.html` has an inline boot script that reads
`bb.theme` to add the `dark` class before the app loads, and the app bundle
reads the same key when it starts. The Feature makes the first statement of
that script

```js
/* tutor-feature: lightTheme */ try { localStorage.setItem("bb.theme", "light"); } catch {}
```

so every page load starts light, whatever was stored and whatever the
operating system prefers. A learner who picks Dark or System in Settings gets
it only until the next reload. The marker comment makes the patch
idempotent. The precompressed `index.html.br` and `index.html.gz` are
deleted, because BB's server prefers them to `index.html`; it then serves the
patched file uncompressed, with an ETag computed from its content. This is
independent of `theme` (which BB palette, such as Tutor's Sketchbook, is
selected): `lightTheme` picks that palette's light variant. `false` leaves
`index.html` untouched.

**`appIcons` (default `lsp`).** Every `favicon-*.png` (including `-dark` and
`-dev`), `apple-touch-icon*.png` and `icon-*.png` (including `-maskable`,
`-monochrome` and BB's colour variants such as `-blue`) in `app/dist` is
replaced by the LSP icon of the same pixel size (read from the PNG's `IHDR`
with `od`; no image tools are needed) and kind, from `icons/`:
`lsp-tile-<size>.png` for favicons and `purpose: any` icons (the coral tile),
`lsp-touch-180.png` for Apple touch icons (opaque, full-bleed),
`lsp-maskable-<size>.png` (full-bleed coral, letters inside the central 80%
safe zone) and `lsp-monochrome-<size>.png` (white letters on transparency,
like BB's own). BB's favicon colour setting therefore has no visible effect.
bb-app 0.43.4 and 0.44.0 ship 53 such files at 16, 32, 180, 192 and 512 px.
`bb` leaves them untouched. The icons are rendered, each at its own size, from
[`scripts/tutor-icons/`](../../scripts/tutor-icons) (see its
`render.mjs`), which is not part of the published Feature. The letters are
set in Luckiest Guy, Copyright (c) 2010 by Brian J. Bonislawsky DBA
Astigmatic (AOETI), under the Apache License 2.0.

**When BB changes.** Both patches are written against bb-app 0.43.4 and
0.44.0. If a later bb-app's `index.html` has no inline script reading
`localStorage.getItem("bb.theme")`, the build prints a warning and leaves the
file (and its `.br`/`.gz`) as they are, so BB's own theme choice comes back.
An icon of a size or kind the Feature has no LSP icon for keeps BB's, with a
warning, and a bb-app that cannot be found at all is skipped with a warning.
The patches live in the image: updating bb-app in a running container
replaces them with BB's originals until the image is rebuilt. BB serves the
icons with a one-day cache lifetime, so a browser that visited before may
show BB's icon for up to a day.


## Lifecycle hooks (remote user)

`postCreateCommand` runs `tutor-feature-bootstrap`: if `course` does not exist
and `courseRepo` is set, it runs `git clone -- <courseRepo> <course>`, and then
the same for `starter` and `starterRepo`. Each clone is independent: a failed
course clone still clones the starter. A clone that cannot happen (no writable
parent, no network) is reported with the command to run, and never fails the
hook, because a failing lifecycle command would stop BB's own start-up hook.
The plugin then shows the student that the course is missing. The Codespace
entry point clones the upstream starter, not the student's fork.

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
- registers `course` and the student's repo as BB projects when the
  directory exists and no project has that local source path yet (the plugin
  itself never creates projects). The student's repo is `starter` when it is
  set: coach threads start there, so a folder that moves inside it (the
  starter's factory moves from `tetris/.factory` to `factory/` at lesson 004)
  never strands a thread. The starter is named by its basename, so a fork
  cloned as `my-fork` is the project `my-fork`, and it is skipped when a
  project's local source already is the starter or sits anywhere inside it,
  such as the `tetris/.factory` a 0.5.0 Codespace registered, whose threads
  live there. The `factory` option is registered instead only when `starter`
  is empty, as before 0.6.0; there a project is named after its folder,
  except that a dot-folder is named with its parent, so
  `<starter>/tetris/.factory` is the project `tetris/.factory` rather than
  `.factory`;
- selects the course outline with
  `bb settings ui set sidebar.threadListProvider tutor/course-outline`, once per
  state directory, only when the plugin is installed, `selectOutline` is true,
  and the current value is bb's default (`thread-list/thread-list`). A marker
  file records the decision, so a student who switches back keeps their
  choice;
- switches off the plugins in `disablePlugins` with `bb plugin disable`,
  once per plugin per state directory. `<dataDir>/.tutor-feature/plugins-disabled`
  lists every id already handled (disabled, found disabled, or not installed),
  so a student who turns one back on under Settings → Plugins keeps it, and an
  id added to the option by a later image is still switched off once. A
  disable that fails is not recorded and is retried on the next start. It
  refuses `tutor`, `thread-list`, `provider-*`,
  `environment-project-checkout`, `environment-personal-workspace` and
  `environment-git-worktree` with a log line. Some default ids (`tasks`,
  `github`, `browser-automation`, `theme-preview`,
  `environment-modal-sandbox`) are not installed in a fresh BB 0.43.4, and
  `workflows`, `account-pool`, `agent-annotations` and `plugin-api-*` start
  disabled; they are listed so that they stay off if BB installs or enables
  them by default later;
- switches Tutor's old Paper theme (`plugin:tutor:paper`) to Sketchbook
  (`plugin:tutor:sketchbook`), once per state directory (`theme-migrated`
  marker). Plugin 0.3.0 renamed Paper and keeps it as an alias for one
  release. Only an active Paper is switched: any other theme is left alone,
  and so is a Paper a student picks again later. Like the theme choice below
  it waits for the running plugin and for Sketchbook to be offered, and does
  nothing when `theme` is empty;
- selects `theme` with `bb theme set`, once per state directory
  (`theme-selected` marker), only when the Tutor plugin is running (it
  contributes `plugin:tutor:sketchbook`) and the active theme is BB's `default`,
  so a student's own theme is never replaced. If BB does not offer the theme
  yet, the hook logs that and tries again on the next start.

The hook fails (non-zero) when BB never answers or the plugin cannot be
installed or does not reach `running`; a project, outline, plugin or theme step
that fails is reported and also makes the hook fail, after the other steps
have run.

## Keeping a Codespace awake (`tutor-keepalive`, best effort)

GitHub stops a Codespace after its idle timeout (30 minutes by default). Per
GitHub's documentation the timer is reset by personal interaction with the
Codespace (typing or using the mouse in the editor) and by terminal input or
output. Browser traffic through a forwarded port, which is all a student using
BB produces, does not count. So a student can work in BB for half an hour and
lose the Codespace mid-lesson. A repository cannot change the timeout: it is
not a `devcontainer.json` setting.

The mitigation has two halves:

- the Tutor plugin writes `<dataDir>/.tutor-feature/activity`, one line with
  the ISO-8601 UTC time the student was last active in BB, atomically, while
  the page is in use;
- `tutor-keepalive`, run by the Codespace entry point's `postAttachCommand` in
  the terminal VS Code opens when it attaches, checks that file every 30 s
  and, when the time is less than 120 s old, prints one line (`tutor: you're
  active in BB — keeping this Codespace awake (13:05)`). While the student is
  away it prints nothing, so the idle timeout still stops an unused Codespace.

It runs only when `CODESPACES=true` and its output is a terminal; otherwise it
says why and exits at once, so `devcontainer up` (which also runs
`postAttachCommand` and waits for it) is never held up. A `flock` on
`<dataDir>/.tutor-feature/keepalive.lock` (which holds the pid) keeps it to one
copy however many clients attach; a second copy says so and exits. Closing its
terminal ends it and frees the lock. Each start is logged, with where its
output goes, in `<dataDir>/.tutor-feature/keepalive.log`.

**This is best effort and must be confirmed in a real Codespace**: that the
attach terminal appears, and that GitHub counts its output as activity (leave
BB in use, with no editor or terminal input, past the idle timeout). The
reliable fix is the student's own idle timeout, up to 240 minutes: GitHub →
Settings → Codespaces → Default idle timeout, or
`gh codespace create --idle-timeout 240m`. Organisations can cap it lower.

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
  - `standalone`: the pinned plugin release downloaded and verified (so the
    scenarios need that release published and its SHA-256 pinned), prebuilt,
    root-owned, with runtime dependencies only; `config.json`'s schema version;
    course cloned; plugin running from its digest copy; toolchain seeded, not
    downloaded; projects and outline, with a factory-only configuration
    (no `starter`, so no `repo` in `config.json`); idempotent restarts; the student's outline
    choice kept; `config.json`'s `dataDir`; the unneeded plugins switched off
    once and a re-enabled one kept on; the Tutor theme selected once and a
    student's own theme kept; BB's boot script pinned to Light (and served
    that way) and its icons replaced by the LSP ones; `tutor-keepalive` returning at once outside
    Codespaces; and, with the credential-free
    [scripted provider](../../test/tutor/fixtures/scripted-provider), a thread
    Tutor did not spawn is neither offered Tutor's tools nor able to run one.
  - `no_clone_no_outline`: an empty `courseRepo` and `starterRepo`,
    `selectOutline: false`, an empty `disablePlugins`, an empty `theme`,
    `lightTheme: false` and `appIcons: bb` (BB's web client untouched) in
    the default state directory;
  - `starter_workspace`: `starter` is `${containerWorkspaceFolder}` with an
    empty `starterRepo`, as in a starter's own Codespace: the variable is
    substituted, `config.json` names the workspace as `repo`, nothing is
    cloned, and the workspace is the BB project, named after its folder;
- hermetic tests of the option validation and of every hook decision against
  a fake bb CLI, including the keep-alive's freshness window and single
  instance, and the one-time switch from Paper to Sketchbook;
- a hermetic test of the plugin download (`plugin-fetch-hermetic.sh`): a fake
  `curl` serves crafted tarballs, and a wrong checksum (which must extract
  nothing), a wrong top-level directory, `..`, absolute and escaping-link
  members, a mismatched `package.json`, a missing lockfile, a bundled `dist/`
  and a failed download are each refused; for `latest`, the resolved release
  installs, and a redirect without a release tag, an odd tag, another
  repository's tag, a malformed, multi-line or wrong-file `.sha256` (which
  must download nothing) and a `.sha256` that does not match the tarball are
  each refused;
- a test of the web-client patches (`bb-brand-hermetic.sh`) against copies
  of the real bb-app 0.43.4 and 0.44.0 `app/dist` (fetched with `npm pack`):
  the theme pin is the boot script's first statement, running that script
  stores `light` and adds no `dark` class whatever was stored and whatever
  the OS prefers, the `.br`/`.gz` are removed, a second run changes nothing,
  and a boot script without the anchor is warned about and left untouched;
  every icon is replaced by the LSP icon of its kind and size and nothing
  else changes, an unknown size keeps BB's with a warning; `lightTheme:
  false` and `appIcons: bb` each leave their files untouched; and a missing
  bb-app only warns;
- a bring-up of the Codespace entry point itself (`codespace-entry.sh`, on
  ports 48886/48887 and with `/workspaces` paths moved under the home
  directory), including the starter clone registered as the BB project
  `capstone-project-starter`, the Claude Code, Codex and Pi CLIs on BB's `PATH` and
  reported installed by `bb updates status`, the switched-off plugins and the
  theme;
- the check that the entry point's Feature copies match `src/`.

A real GitHub Codespace remains the owner's acceptance step: the private
forwarded port, `/workspaces` ownership and persistence of
`/workspaces/.bb-state`, the outline, theme and LSP icons in a real browser, provider
sign-in, and whether `tutor-keepalive`'s output keeps the Codespace awake.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/lean-software-production/devcontainer-features/blob/main/src/tutor/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
