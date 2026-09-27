# BB standalone Codespaces (bb)

Installs the `bb-app` npm distribution in a private Feature-owned prefix. It
can either provide BB's CLI only, or run one loopback-only BB server and its
local workers for the remote user in a Codespace.

## Example Usage

```jsonc
{
  "features": {
    "ghcr.io/lean-software-production/devcontainer-features/bb:1": {
      "mode": "standalone",
      "autoStart": true,
      "dataDir": "${containerWorkspaceFolder}/.bb-state"
    }
  }
}
```

The OCI reference above is for a future published Feature. Until it is
published, use this repository's [copyable example](../../examples/bb-standalone),
which explains how to copy `src/bb` beneath a consumer's `.devcontainer`
directory for local validation. Add `/.bb-state/` to the consumer repository's
`.gitignore` when using the example state path.

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `version` | string | `0.43.4` | Exact bb-app semver, or explicit `latest`. `latest` is resolved at image build, never at startup. |
| `mode` | `cli` / `standalone` | `cli` | CLI only, or the user-owned standalone server lifecycle. |
| `autoStart` | boolean | `false` | Start standalone BB on each container start. Has no effect in CLI mode. |
| `serverPort` | string | `38886` | Server loopback port, 1024-65535. |
| `hostDaemonPort` | string | `38887` | Local host-daemon loopback port; never forward it. |
| `dataDir` | string | empty | Absolute user-owned state path. Empty uses the remote user's `~/.bb`. |
| `appUrl` | string | `auto` | Explicit HTTP(S) browser origin, or an origin derived from Codespaces variables. |

Node is intentionally composable: supply it through the base image or Node
Feature. BB 0.43.4 requires Node `^22.19.0`, `^24`, or `^26`. This Feature is
implemented and tested for Debian/Ubuntu Linux amd64. It does not claim arm64
validation.

See [NOTES.md](NOTES.md) for the security model, lifecycle, Codespaces setup,
and limitations.

---

_This file follows the repository's generated-doc layout; put narrative
guidance in `NOTES.md`._
