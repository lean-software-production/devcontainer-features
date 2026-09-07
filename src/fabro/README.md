
# Fabro (fabro)

Installs the Fabro CLI and a guided setup wizard that connects Fabro to a ChatGPT/OpenAI account using OAuth device code, which works in Codespaces, local dev containers, and over SSH.

## Example Usage

```json
"features": {
    "ghcr.io/lean-software-production/devcontainer-features/fabro:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Fabro version to install. Use 'latest' to track the newest release, or pin an exact version for reproducible containers. | string | 0.254.0 |
| provider | Which LLM provider the setup wizard offers first. 'openai' uses a ChatGPT/Codex subscription over OAuth device code; the others prompt for an API key. | string | openai |
| model | Model passed to the Fabro server as its default once the wizard signs in. 'auto' uses the built-in preference for the chosen provider (gpt-5.6-luna for OpenAI) and the provider's own default elsewhere. 'none' pins the provider only. Any other value is used as the model slug. A model the installed Fabro's catalog does not serve is skipped rather than pinned. | string | auto |
| autoStartServer | Start the local Fabro server automatically when the container is created. | boolean | true |
| shellBanner | Print a one-line 'run fabro-setup' hint in new interactive shells until setup is complete. Covers clients that do not run VS Code tasks. | boolean | true |

## How setup works

The feature splits setup into the part that needs no human and the part that does.

| Stage | Runs | What it does |
| --- | --- | --- |
| `install.sh` | image build, as root | Downloads and checksum-verifies the Fabro binary, installs `fabro-setup` and `fabro-status`, records the resolved options |
| `fabro-bootstrap` | `postCreateCommand`, as the remote user | Generates `~/.fabro/settings.toml` and starts the local Fabro server |
| `fabro-autostart` | `postStartCommand`, as the remote user | Restarts the Fabro server on every container start |
| `fabro-setup` | a terminal, on demand | Asks which provider to use and runs the sign-in |

The split exists because dev container lifecycle hooks do not get a reliable
interactive terminal ([devcontainers/spec#83](https://github.com/devcontainers/spec/issues/83)),
so a hook cannot prompt. `fabro-setup` is a normal command you can run any time.

`postStartCommand` matters as much as `postCreateCommand` here: a stopped and
restarted Codespace keeps its filesystem but loses its processes, so without
the start hook the server would be down until someone ran the wizard again.

## Reaching the web UI

The server listens on loopback. In a Codespace the HTTPS tunnel forwards to the
server over HTTP with its public host header, so the feature sets
`FABRO_WEB_URL` to `http://$CODESPACE_NAME-<port>.app.github.dev` when it
starts the server, and leaves it as `http://127.0.0.1:<port>` everywhere else.
It also stores the corresponding API and web URLs in Fabro's settings. Fabro
uses those values for browser auth routes and generated links.

Declare the port in your `devcontainer.json` so it is forwarded with a label
rather than relying on auto-detection:

```jsonc
"forwardPorts": [32276],
"portsAttributes": { "32276": { "label": "Fabro", "onAutoForward": "silent" } }
```

Forwarded ports are private by default, which means the browser completes a
GitHub sign-in handshake before reaching the app. If that handshake stalls,
open the port from the editor's PORTS panel rather than pasting the URL, and
check you are signed in to the same GitHub account in that browser profile.

## Signing in from a Codespace

Fabro authenticates with OpenAI using an **OAuth device code**: it prints a URL
and a short code, and you enter the code in a browser on any machine.

There is no localhost callback, so nothing needs to be forwarded, no redirect
URI has to be registered, and the flow is identical in a browser-based
Codespace, VS Code Desktop, and a plain SSH session. This is what makes the
wizard portable; provider logins that use a PKCE callback to `localhost` do not
survive the browser-based Codespaces editor without extra port plumbing.

Anthropic and OpenRouter prompt for an API key instead.

Credentials go into the Fabro server's vault under `~/.fabro`. Nothing is
written to the repository.

## Launching the wizard automatically

The feature enables the `task.allowAutomaticTasks` VS Code setting, but the task
itself belongs to the project. Add `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Fabro: setup",
      "type": "shell",
      "command": "fabro-setup",
      "runOptions": { "runOn": "folderOpen" },
      "presentation": { "reveal": "always", "panel": "dedicated", "focus": true },
      "problemMatcher": []
    }
  ]
}
```

`fabro-setup` exits immediately and silently when a credential already exists,
so the task is a no-op on every launch after the first.

For clients that do not run VS Code tasks, the `shellBanner` option prints a
one-line hint in new interactive shells until setup completes.

## Commands

```sh
fabro-setup           # run the wizard, or exit quietly if already configured
fabro-setup --force   # switch providers, or retry after a failed sign-in
fabro-status          # report which credentials are configured
fabro doctor          # full health check
```

## Persistence

`~/.fabro` lives in the container filesystem. It survives stopping and starting
a Codespace, but a **rebuild discards it** and the wizard runs again. That is a
few seconds of work, so the feature does not try to cache credentials.

## Requirements

`fabro install` requires a GitHub credential, so this feature depends on
`ghcr.io/devcontainers/features/github-cli`. Codespaces provides an
authenticated `gh` automatically. Elsewhere the wizard runs `gh auth login`
first, which is also a device-code flow.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/lean-software-production/devcontainer-features/blob/main/src/fabro/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
