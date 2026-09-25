## Requirements

This Feature intentionally does not install Node.js. Use a Node.js base image or
add a Node Feature in the consuming `devcontainer.json`;
`installsAfter: ["ghcr.io/devcontainers/features/node"]` ensures the Feature
runs after a Node Feature when both are selected. The
installer requires `node`, `npm`, and Node.js 16 or later. The official npm
package currently provides Linux x64 and arm64 distributions.

The default tracks the rolling npm `latest` release of the official
`@openai/codex` package. Set `"version"` to an exact release such as `0.155.1`
when reproducible builds are required.

## Default model

Set `"model"` to make a model the default for every Codex session in the
container:

```json
"features": {
  "ghcr.io/lean-software-production/devcontainer-features/codex:1": {
    "model": "gpt-6-sol"
  }
}
```

The Feature writes it to the system config layer, `/etc/codex/config.toml`, so
the remote user's own `~/.codex/config.toml`, `/model`, or `--model` still take
precedence. Leave it empty to keep Codex's upstream default. `codex doctor`
shows the effective model.

## First run and authentication

After the container is created, open a terminal as the remote user and run:

```sh
codex
```

Choose ChatGPT sign-in in the interactive prompt, or run `codex login`.
In browser-based GitHub Codespaces, remote containers, and other headless
environments, use the device-code flow instead:

```sh
codex login --device-auth
```

Open the displayed URL in a browser, sign in, and enter the one-time code. The
device-code login must be enabled in the ChatGPT account security settings (or
by a workspace administrator). This avoids the localhost callback used by the
normal browser flow.

For pay-as-you-go API access, obtain an API key separately and pass it only at
runtime; never put it in `devcontainer.json`, a Dockerfile, or source control:

```sh
printenv OPENAI_API_KEY | codex login --with-api-key
```

Verify that installation, without authenticating or making a network request to
Codex, with:

```sh
codex --version
```

## Credential persistence

Codex caches login credentials for the remote user, normally in
`~/.codex/auth.json` (or an operating-system credential store). Treat that file
as a password: do not commit, copy into an image, or share it. Credentials
normally survive stopping and starting a Codespace or dev container when its
filesystem persists. A rebuild creates a new image/container filesystem, so
expect to authenticate again unless the user deliberately provides their own
secure persistent home-directory storage.

See the official [Codex CLI documentation](https://developers.openai.com/codex/cli)
and [authentication guidance](https://learn.chatgpt.com/docs/auth)
for current installation and login behavior.
