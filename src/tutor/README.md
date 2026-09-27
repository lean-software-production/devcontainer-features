# Tutor coached course for BB (tutor)

Adds the Tutor BB plugin to the [bb Feature](../bb)'s standalone server: a
course outline in the sidebar and a coach thread per lesson that works one
Gherkin Rule at a time. The plugin, from
[bb-plugin-tutor](https://github.com/lean-software-production/bb-plugin-tutor),
is downloaded as a checksummed release (the pinned one by default, or the
newest with `pluginVersion: "latest"`) and prebuilt while the image is built, then path-installed into BB each time the container starts; nothing
is fetched at start-up except the optional course and starter clones. On first
start it also brands BB with the Tutor paper theme and switches off BB plugins
a student does not need; a student can undo either.

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
      "starter": "/workspaces/capstone-project-starter",
      "starterRepo": "https://github.com/lean-software-production/capstone-project-starter.git",
      "factory": "/workspaces/capstone-project-starter/tetris/.factory"
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
| `starter` | string | empty | Optional absolute path of the student's [capstone-project-starter](https://github.com/lean-software-production/capstone-project-starter) checkout, which holds the factory. Must differ from `course`. |
| `starterRepo` | string | empty | HTTPS Git URL cloned into `starter` after the container is created, if `starter` does not exist. Needs `starter`. Empty never clones. |
| `factory` | string | empty | Optional absolute path of the student's factory, the folder holding `spec/` and `ITERATION` (in the starter, `<starter>/tetris/.factory`). Registered as a BB project once it exists, and pre-selected by the plugin. A dot-folder is named with its parent, so the starter's factory is the project `tetris/.factory`. |
| `selectOutline` | boolean | `true` | Select the course outline as BB's sidebar thread list once, unless another thread list was chosen already. |
| `disablePlugins` | string | `automations,workflows,tasks,scheduled-send,github,browser-automation,agent-annotations,connect,plugin-api-docs,plugin-api-tester,theme-preview,keep-awake,account-pool,environment-modal-sandbox` | Comma-separated BB plugin ids to switch off once per BB state directory; a student can turn any back on. Missing plugins are skipped. `tutor`, `thread-list`, `provider-*` and the workspace environments are never switched off. Empty switches off nothing. |
| `theme` | string | `plugin:tutor:paper` | BB theme to select once per BB state directory, only while BB's default theme is active. Empty leaves the theme alone. |
| `pluginVersion` | string | `0.1.0` | [bb-plugin-tutor](https://github.com/lean-software-production/bb-plugin-tutor) release to download at image build: a plain semantic version (no `v` prefix or range), or `latest`. The default is the release this Feature version pins, verified against its pinned SHA-256; any other version needs `pluginSha256`. `latest` resolves to the newest release when the image is built (a prebuilt image keeps it until rebuilt) and is checked only against that release's own `.sha256`, which catches corruption but not a compromised release. |
| `pluginSha256` | string | empty | SHA-256 (64 lower-case hex digits) of `bb-plugin-tutor-<pluginVersion>.tgz`. Required when `pluginVersion` is an explicit version other than the pinned default; with the default it must be empty or equal the pin; with `latest` it must be empty. For an explicit version the release's own `.sha256` file is never trusted. |

The Feature also installs `tutor-keepalive`, which keeps a GitHub Codespace
awake while the student uses BB. It is not a lifecycle command of the Feature,
because it runs until its terminal closes and would hold up any
`postAttachCommand` after it. Add it to your configuration's own
`postAttachCommand`, in the object form so that it runs beside other commands:

```jsonc
"postAttachCommand": { "tutor-keepalive": "tutor-keepalive" }
```

Requires the bb Feature in `standalone` mode, installed first, on the Linux
amd64 Debian/Ubuntu Node.js images the bb Feature supports, with `curl`. The
image build needs HTTPS access to `github.com` for the plugin release, as
well as to the npm registry.

See [NOTES.md](NOTES.md) for the lifecycle, security model, local composition
and limitations.

---

_This file follows the repository's generated-doc layout; put narrative
guidance in `NOTES.md`._
