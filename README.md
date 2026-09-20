# Dev Container Features

Reusable [Dev Container Features](https://containers.dev/implementors/features/)
for coding-agent workflows.

## `fabro`

Installs the Fabro CLI and a setup wizard that connects a dev container to your
LLM account. Add it to any project:

```jsonc
// .devcontainer/devcontainer.json
{
  "image": "mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm",
  "features": {
    "ghcr.io/lean-software-production/devcontainer-features/fabro:1": {}
  }
}
```

Then copy `.vscode/tasks.json` from the [feature docs](src/fabro/NOTES.md) if
you want the wizard to open automatically when the project is opened.

See [src/fabro](src/fabro) for options and details.

## Coding agents

`pi`, `claude-code`, and `codex` are separate, composable Features. They do
not install, pin, or share a Node.js runtime: select a compatible Node.js base
image or add the official Node Feature in the consuming configuration. Each
Feature installs only its own CLI globally, offers an exact reproducible
`version` default plus `latest`, and leaves authentication to the remote user
after the container is created.

```jsonc
// .devcontainer/devcontainer.json
{
  "image": "mcr.microsoft.com/devcontainers/javascript-node:5-24-trixie",
  "features": {
    "ghcr.io/lean-software-production/devcontainer-features/pi:1": {
      "version": "0.86.0"
    },
    "ghcr.io/lean-software-production/devcontainer-features/claude-code:1": {
      "version": "2.1.278"
    },
    "ghcr.io/lean-software-production/devcontainer-features/codex:1": {
      "version": "0.155.1"
    }
  }
}
```

Use only the Features you need. Set any `version` option to `latest` when a
non-reproducible rolling install is intentional. No credentials are embedded,
installed, or shared between these Features.

| Feature | Post-create authentication | Documentation |
| --- | --- | --- |
| Pi | Run `pi`, then `/login` in the Pi prompt. | [Pi notes](src/pi/NOTES.md) |
| Claude Code | Run `claude` and follow its interactive sign-in. | [Claude Code notes](src/claude-code/NOTES.md) |
| OpenAI Codex CLI | Run `codex login --device-auth` in Codespaces or another browser-based remote container. | [Codex notes](src/codex/NOTES.md) |

## Publishing

Features are published to `ghcr.io` as OCI artifacts by the
**Release features** workflow (`workflow_dispatch`). The first publish creates
a private package; make it public once at
`https://github.com/orgs/lean-software-production/packages` so other repos can
pull it without authenticating.

Bump `version` in `src/<feature>/devcontainer-feature.json` before each release.
Consumers pinning `:1` pick up minor and patch releases automatically.

## Testing

```sh
npm install -g @devcontainers/cli
devcontainer features test --features fabro --skip-duplicated .
devcontainer features test --features pi claude-code codex \
  --base-image mcr.microsoft.com/devcontainers/javascript-node:5-24-trixie \
  --remote-user node --skip-duplicated .
```
