## Requirements

This Feature intentionally does not install Node.js. Use a Node.js base image or
add a Node Feature in the consuming `devcontainer.json`; `installsAfter: ["node"]`
ensures the Feature runs after a Node Feature when both are selected. The
installer requires `node`, `npm`, and Node.js 16 or later. The official npm
package currently provides Linux x64 and arm64 distributions.

The default is the exact `0.155.1` release of the official `@openai/codex` npm
package for reproducible builds. Set `"version": "latest"` only when tracking
the npm `latest` tag is intentional.

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

See the official [Codex CLI documentation](https://developers.openai.com/es-419/docs/codex/cli)
and [authentication guidance](https://developers.openai.com/es-419/docs/auth)
for current installation and login behavior.
