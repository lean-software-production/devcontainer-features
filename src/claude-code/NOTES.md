## Requirements and installation

This feature installs the official `@anthropic-ai/claude-code` npm package
globally. It intentionally does **not** install or select Node.js: the
consuming image owns its runtime. Claude Code's npm distribution currently
requires Node.js 22 or later, so use a Node 22+ base image or order the Node
Feature ahead of this one:

```jsonc
"features": {
  "ghcr.io/devcontainers/features/node:1": { "version": "24" },
  "ghcr.io/lean-software-production/devcontainer-features/claude-code:1": {}
}
```

The default is the exact npm release `2.1.278`, selected from the npm registry
when this feature was authored. This makes rebuilds reproducible. Set
`"version": "latest"` only when the container should follow the npm `latest`
tag. The feature installs the executable into npm's global prefix, normally
`/usr/local/bin`, with world-executable permissions so the non-root remote user
can run `claude`.

Verify a non-interactive installation without opening a session:

```sh
claude --version
```

## First run and authentication

After the container is created, open a terminal as the remote user and run:

```sh
claude
```

Follow Claude Code's browser prompts to sign in with an eligible Claude
subscription (Pro, Max, Team, or Enterprise) or an Anthropic Console account.
An `ANTHROPIC_API_KEY` supplied at runtime is also supported by Claude Code; it
will ask for one-time approval rather than opening a browser. Enterprise
deployments can instead configure their supported cloud provider according to
Anthropic's authentication documentation.

Do not put API keys, browser tokens, or credential files in `devcontainer.json`,
the image, or this repository. Interactive credentials and Claude settings are
stored under the remote user's home directory (for example `~/.claude` and
`~/.claude.json`). They survive ordinary stop/start cycles when the container
filesystem persists, but a rebuild normally replaces them and requires another
sign-in. If durable credentials are needed, use your platform's approved secret
injection or a deliberately managed user-home volume; never commit either.

See Anthropic's [installation and authentication guidance](https://code.claude.com/docs/en/getting-started)
for account eligibility, provider-specific authentication, and updates.
