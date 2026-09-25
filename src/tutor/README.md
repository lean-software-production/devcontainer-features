# Tutor coached course for BB (tutor)

Adds the Tutor BB plugin to the [bb Feature](../bb)'s standalone server: a
course outline in the sidebar and a coach thread per lesson that works one
Gherkin Rule at a time. The plugin is prebuilt while the image is
built and path-installed into BB each time the container starts; nothing is
fetched at start-up except the optional course clone. On first start it also
brands BB with the Tutor paper theme and switches off BB plugins a student
does not need; a student can undo either.

## Example Usage

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/javascript-node:5-24-trixie",
  "features": {
    "ghcr.io/lean-software-production/devcontainer-features/bb:1": {
      "mode": "standalone",
      "autoStart": true
    },
    "ghcr.io/lean-software-production/devcontainer-features/tutor:0": {
      "course": "/workspaces/tutorial",
      "factory": "/workspaces/my-factory"
    }
  },
  "overrideFeatureInstallOrder": [
    "ghcr.io/lean-software-production/devcontainer-features/bb",
    "ghcr.io/lean-software-production/devcontainer-features/tutor"
  ]
}
```

The OCI references above are for future published Features. Until then, use
this repository's Codespace entry point, [`.devcontainer/tutor`](../../.devcontainer/tutor),
which composes local copies of both Features.

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `course` | string | `/workspaces/tutorial` | Absolute path of the course checkout the plugin reads. |
| `courseRepo` | string | `https://github.com/lean-software-production/tutorial.git` | HTTPS Git URL cloned into `course` after the container is created, if `course` does not exist. Empty never clones. |
| `factory` | string | empty | Optional absolute path of the student's factory repository. Registered as a BB project once it exists, and pre-selected by the plugin. |
| `selectRail` | boolean | `true` | Select the course outline as BB's sidebar thread list once, unless another thread list was chosen already. |
| `disablePlugins` | string | `automations,workflows,tasks,scheduled-send,github,browser-automation,agent-annotations,connect,plugin-api-docs,plugin-api-tester,theme-preview,keep-awake,account-pool,environment-modal-sandbox` | Comma-separated BB plugin ids to switch off once per BB state directory; a student can turn any back on. Missing plugins are skipped. `tutor`, `thread-list`, `provider-*` and the workspace environments are never switched off. Empty switches off nothing. |
| `theme` | string | `plugin:tutor:paper` | BB theme to select once per BB state directory, only while BB's default theme is active. Empty leaves the theme alone. |

The Feature also installs `tutor-keepalive`, which keeps a GitHub Codespace
awake while the student uses BB. It is not a lifecycle command of the Feature,
because it runs until its terminal closes and would hold up any
`postAttachCommand` after it. Add it to your configuration's own
`postAttachCommand`, in the object form so that it runs beside other commands:

```jsonc
"postAttachCommand": { "tutor-keepalive": "tutor-keepalive" }
```

Requires the bb Feature in `standalone` mode, installed first, on the Linux
amd64 Debian/Ubuntu Node.js images the bb Feature supports.

See [NOTES.md](NOTES.md) for the lifecycle, security model, local composition
and limitations.

---

_This file follows the repository's generated-doc layout; put narrative
guidance in `NOTES.md`._
