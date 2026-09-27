
# Pi Coding Agent (pi)

Installs the Pi terminal coding agent. Requires Node.js 22.19.0 or newer and npm from the consuming image or Feature.

## Example Usage

```json
"features": {
    "ghcr.io/lean-software-production/devcontainer-features/pi:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Pi package version to install. 'latest' is the rolling default; use an exact version such as '0.86.0' for reproducible containers. | string | latest |

## Requirements

Pi is installed from its official npm package and requires **Node.js 22.19.0 or
newer** plus npm. This Feature deliberately does not install or select Node.js:
the consuming image owns the runtime version. It declares an install ordering
preference for the Dev Container Node Feature and stops with a clear error when
`node` or `npm` is absent or Node is too old.

## First run and authentication

Open an integrated terminal in the repository and start Pi:

```sh
pi
```

At the Pi prompt, run:

```text
/login
```

Choose a supported subscription provider (including ChatGPT Plus/Pro (Codex),
Claude Pro/Max, or GitHub Copilot), or choose an API-key provider. Complete the
browser authorization that Pi presents. This terminal-driven flow is suitable
for GitHub Codespaces and other remote Dev Containers: no credential is needed
or collected while the image is built.

Pi stores credentials and refreshed OAuth tokens for the remote user in
`~/.pi/agent/auth.json`. Protect that file as a credential. Tokens survive a
normal container stop/start when the container filesystem is retained, but a
rebuild typically creates a fresh filesystem and requires `/login` again. Do
not add that directory or an API key to the repository or image. For remote
OpenRouter login, Pi may ask you to paste the final browser redirect URL back
into the terminal.

For non-interactive install verification, run:

```sh
pi --version
```

The feature uses Pi's documented `npm install -g --ignore-scripts` installation
form. `version` defaults to `latest`, following npm's rolling latest release.
Set an exact version such as `0.86.0` when reproducible builds are required.

See the official [Pi quickstart](https://pi.dev/docs/latest/quickstart) and
[provider documentation](https://pi.dev/docs/latest/providers) for current
provider details.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/lean-software-production/devcontainer-features/blob/main/src/pi/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
