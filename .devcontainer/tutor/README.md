# Tutor course Codespace

`devcontainer.json` here is the Codespace entry point for the Tutor course. It
composes:

- the [bb Feature](../../src/bb) in standalone mode with `autoStart`, BB state in
  `/workspaces/.bb-state` (outside any checkout, so it survives rebuilds), and
  only the BB server port 38886 forwarded;
- the [tutor Feature](../../src/tutor), which clones the public
  [tutorial](https://github.com/lean-software-production/tutorial) into
  `/workspaces/tutorial`, and expects the student's factory at
  `/workspaces/my-factory` (coach-me's suggested `../my-factory`);
- Node.js 24 from the `javascript-node` image.

Create a Codespace from this repository and pick the **Tutor course**
configuration. Before opening BB, confirm in the **Ports** view that port 38886
is **Private**; `portsAttributes` cannot set visibility. Do not forward 38887.
Then open the forwarded URL and sign in to a provider in BB. See the
[bb notes](../../src/bb/NOTES.md) and [tutor notes](../../src/tutor/NOTES.md).

## Why `features/` holds copies

Dev Containers only accepts local Features beneath `.devcontainer/`, so
`../../src/bb` cannot be referenced. A symlinked Feature folder does not work
either: the devcontainer CLI, which Codespaces also uses, copies Feature
folders without following the link and fails with "Failed to fetch feature"
(checked with CLI 0.87.0). So `features/bb` and `features/tutor` are committed
copies of `src/bb` and `src/tutor`. They hold only files Git would commit, so
no `node_modules` or `dist`.

After changing anything under `src/bb` or `src/tutor`, run:

```sh
.devcontainer/tutor/sync-features.sh          # rewrite the copies, then commit them
.devcontainer/tutor/sync-features.sh --check  # what CI runs; fails if they are stale
```

Once both Features are published, point `devcontainer.json` at their OCI
references and delete `features/` and the sync script.

`test/tutor/codespace-entry.sh` brings this configuration up with the
devcontainer CLI, changing only what a local Docker host cannot provide like
Codespaces does: ports 48886/48887 instead of 38886/38887, and home-directory
paths instead of `/workspaces`.
