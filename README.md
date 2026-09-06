# Dev Container Features

Reusable [Dev Container Features](https://containers.dev/implementors/features/)
for projects that use [Fabro](https://fabro.sh).

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
```
