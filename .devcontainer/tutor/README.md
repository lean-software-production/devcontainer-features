# Tutor course Codespace

`devcontainer.json` here is the Codespace entry point for the Tutor course. It
composes:

- the [bb Feature](../../src/bb) in standalone mode with `autoStart`, BB state in
  `/workspaces/.bb-state` (outside any checkout, so it survives rebuilds), and
  only the BB server port 38886 forwarded;
- the [tutor Feature](../../src/tutor), which clones the public
  [tutorial](https://github.com/lean-software-production/tutorial) into
  `/workspaces/tutorial`, and expects the student's factory at
  `/workspaces/my-factory` (coach-me's suggested `../my-factory`). On first
  start it selects the Tutor paper theme and switches off BB plugins a student
  does not need (Automations, Workflows, Connect and others; see its
  `disablePlugins` option); a student can turn any back on;
- the [Claude Code](../../src/claude-code), [Codex](../../src/codex) and
  [Pi](../../src/pi) Features, which put `claude`, `codex` and `pi` in
  `/usr/local/bin`, on BB's fixed `PATH`, so BB offers all three providers. No
  credentials are installed: a student signs in from BB or by running the CLI
  in a terminal. Each installs the latest release when the image is built;
- Node.js 24 from the `javascript-node` image;
- `tutor-keepalive` as the `postAttachCommand` (see below).

Create a Codespace from this repository and pick the **Tutor course**
configuration. Before opening BB, confirm in the **Ports** view that port 38886
is **Private**; `portsAttributes` cannot set visibility. Do not forward 38887.
Then open the forwarded URL and sign in to a provider in BB. See the
[bb notes](../../src/bb/NOTES.md) and [tutor notes](../../src/tutor/NOTES.md).

## Idle timeout

GitHub stops a Codespace that has been idle for its idle timeout (30 minutes
by default), and using BB in the browser does not count as activity; only
typing or using the mouse in the editor, and terminal input or output, do. The
repository cannot change the timeout. Two things help:

- **Set a longer idle timeout** (reliable): GitHub → Settings → Codespaces →
  Default idle timeout, up to 240 minutes, before creating the Codespace; or
  `gh codespace create --idle-timeout 240m`.
- **`tutor-keepalive`** (best effort): when VS Code attaches, the
  `postAttachCommand` terminal runs it. While BB is in use it prints one line
  every 30 s, which is terminal output; while the student is away it prints
  nothing. Leave that terminal open. It has to be confirmed in a real
  Codespace that GitHub counts this output; see the
  [tutor notes](../../src/tutor/NOTES.md#keeping-a-codespace-awake-tutor-keepalive-best-effort).

## Why `features/` holds copies

Dev Containers only accepts local Features beneath `.devcontainer/`, so
`../../src/bb` cannot be referenced. A symlinked Feature folder does not work
either: the devcontainer CLI, which Codespaces also uses, copies Feature
folders without following the link and fails with "Failed to fetch feature"
(checked with CLI 0.87.0). So `features/<id>` is a committed copy of
`src/<id>` for every `./features/<id>` that `devcontainer.json` uses (bb,
claude-code, codex, pi and tutor). The sync script reads that list from
`devcontainer.json`. The copies hold only files Git would commit, so no
`node_modules` or `dist`.

After changing anything under those `src/` folders, or adding a local Feature
to `devcontainer.json`, run:

```sh
.devcontainer/tutor/sync-features.sh          # rewrite the copies, then commit them
.devcontainer/tutor/sync-features.sh --check  # what CI runs; fails if they are stale
```

Once the Features are published, point `devcontainer.json` at their OCI
references and delete `features/` and the sync script.

`test/tutor/codespace-entry.sh` brings this configuration up with the
devcontainer CLI, changing only what a local Docker host cannot provide like
Codespaces does: ports 48886/48887 instead of 38886/38887, and home-directory
paths instead of `/workspaces`. It checks the Tutor plugin, the rail, the three
agent CLIs (on `PATH` and reported installed by `bb updates status`), the
switched-off plugins, the theme, and that `tutor-keepalive` returns at once
outside Codespaces.
