## What this Feature runs

Mode A is deliberately self-contained: one learner-owned BB server, the BB UI,
the CLI, and local workers run inside one Codespace. The server always binds to
`127.0.0.1`. Only `serverPort` is forwarded; `hostDaemonPort` stays internal.
No Docker socket, privileged container, Electron, systemd, tmux, Connect
pairing, machine enrollment, or GitHub App is required.

The Feature installs `bb-app` under `/usr/local/share/bb/npm` instead of using
an ambient `bb`, `bb-app`, or `BB_*` setting. Its public helpers are
`bb-feature-bootstrap`, `bb-feature-autostart`, and `bb-feature-status`, so
they cannot shadow BB's own CLI commands. The package is fetched during image
build, SHA-512 SRI-checked against npm registry metadata, and installed with
addon scripts enabled only for that install. On npm 11.16 and later the
per-invocation allowlist names the reviewed `node-pty` and `@parcel/watcher`
native hooks; the Feature never writes a user or global npm script policy. It
never downloads `latest` at runtime.

npm 11.16 introduced the script-approval flag with advisory warnings for
unreviewed scripts; npm 12 blocks unapproved scripts. The scoped flag also
avoids npm 11's "not yet covered by allowScripts" warning for the reviewed
addons. npm before 11.16 uses its normal script behavior without this flag.

BB's upstream source is MIT licensed. Because the 0.43.4 npm manifest omits
its license field, the Feature installs the upstream notice at
`/usr/local/share/bb/NOTICE`; the source copy is [NOTICE](NOTICE).

## Create and use a private Codespace

1. Copy [the example](../../examples/bb-standalone) into a separate consumer
   repository's `.devcontainer/`, substituting a published OCI reference only
   after this Feature has actually been published. Rebuild the container.
2. In the Codespace **Ports** view, find port 38886 and confirm its visibility
   is **Private** (owner-private). Do not make it organization-visible or
   public: BB's direct API has powerful local command and file access and is
   not protected by an application login. Standard `portsAttributes` cannot
   set Codespaces visibility, so this must be confirmed in GitHub. If an
   organization enforces private ports, use that policy as an additional
   boundary.
3. Open the forwarded 38886 URL. With `appUrl: "auto"`, the Feature configures
   `https://${CODESPACE_NAME}-38886.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}`
   as `BB_APP_URL`, while the process remains loopback-only. GitHub's proxy
   terminates browser HTTPS; the container transport remains HTTP.
4. Sign in to a provider interactively in BB, then add/open a workspace and
   create a thread. No provider login or credential is performed by this
   Feature. Optional GitHub CLI use is separately authenticated with `gh auth`.

`BB_APP_URL` is an allowed browser origin and generated-link origin, not the
bind address. The server's browser guard recognizes GitHub's forwarded host and
protocol headers; browser WebSocket and terminal traffic use the same external
origin. Do not change the bind host to `0.0.0.0` to work around forwarding.
`BB_APP_URL` adds an allowed origin; it does not replace the server's loopback
origins. BB intentionally still accepts `http://127.0.0.1:<serverPort>` and
`http://localhost:<serverPort>`. Foreign and opaque (`Origin: null`) browser
origins remain rejected. This origin guard is not authentication; keep the
forwarded port owner-private.
Outside Codespaces, `auto` uses `http://127.0.0.1:<serverPort>`. An explicit
`appUrl` must be a pathless HTTP(S) origin and is used as supplied.

## Lifecycle and state

At image build, the Feature installs software only. `postCreateCommand` runs
`bb-feature-bootstrap` as the remote user. In standalone mode it creates or
uses the selected state directory with mode 0700 and writes only `BB_APP_URL`
through BB's supported config command; it does not overwrite provider or user
configuration. The selected path, every existing ancestor, and the
Feature-owned runtime directory must be non-symlinks, so choose a normal
user-owned path rather than a symlinked convenience location. With
`autoStart: true`, `postStartCommand` runs the autostart helper each container
start.

The helper serializes starts with a user-owned lock, records only the exact
launcher PID it created, verifies PID owner, executable and data directory
before recovery, and starts that launcher in a new session so Codespaces
lifecycle process-group cleanup does not terminate it. A PID handoff preserves
the real `bb-app` PID even when `setsid` needs an intermediate fork. The helper
waits up to 30 seconds (plus a bounded final probe) for
both server `/health` and a TCP connection to the configured loopback host-daemon
port. The same readiness rule applies to an existing launcher and to status;
a healthy HTTP server alone is not sufficient. After verifying its launcher is
owned and alive, status retries for 8 seconds (plus a bounded final probe) to
tolerate transient startup/plugin load. If no owned launcher is recorded yet
but an autostart holds the lifecycle lock, status first waits up to 45 seconds
for that start to finish; with no lock holder it fails at once. Status never
restarts or signals the launcher, and never creates the lock or the runtime
record; it fails if either service remains unavailable. Autostart refuses a healthy port
owned by anything else, never kills by port number, and never deletes BB's own
locks. Logs and Feature-owned runtime metadata live under
`<dataDir>/.bb-feature/`; use `bb-feature-status` for a concise health result.
There are no prompts or browser launches in lifecycle hooks.

For a Codespace, set `dataDir` to `/workspaces/.bb-state` (outside the Git
checkout) if you want BB identity and worktree state to survive rebuilds.
That location normally survives a rebuild, but not Codespace deletion. It is
not a credential-export mechanism: provider credentials remain in their normal
user locations and typically need interactive reauthentication after a
rebuild. Never copy initialized BB state between learners. BB server exports
can contain secrets and omit host-owned workspaces; make backups only through a
reviewed, user-controlled process.

To upgrade, pin a new exact Feature `version`, rebuild, and keep the existing
user-owned state only after taking a user-controlled backup. Inspect BB's
release notes first. Browser-only activity may not keep a Codespace awake;
shutdown/idle behavior is controlled by Codespaces policy.

## Machine mode

`mode: "machine"` makes the container a BB **machine** of a hosted BB server,
for example a learner's own Tutor server. The server, its plugins and the
browser UI run elsewhere; the learner's workspace, coding agents and BB's
host entry run here. Nothing listens on a public or forwarded port: the
daemon dials out to the server over https, and its `hostDaemonPort` stays on
loopback.

Per-learner values come from the environment, so one `devcontainer.json`
serves a whole cohort. In Codespaces, set them as Codespaces secrets for the
repository:

| Variable | What |
| --- | --- |
| `BB_MACHINE_SERVER_URL` | The server's https origin, e.g. `https://student-001-tutor.leansoftware.ai` (or set the `serverUrl` option instead). |
| `BB_MACHINE_ACCESS_CLIENT_ID`, `BB_MACHINE_ACCESS_CLIENT_SECRET` | Optional: a Cloudflare Access service token, when Access fronts the server. A Service Auth policy on the server's Access application must allow it. |

```jsonc
"features": {
    "ghcr.io/lean-software-production/devcontainer-features/bb:1": {
        "version": "0.45.0",      // the server's bb-app version: a daemon speaks its server's protocol
        "mode": "machine",
        "autoStart": true
    }
}
```

`postCreateCommand` prepares `~/.bb-machine` (mode 0700; `dataDir` overrides
it). On every container start, `postStartCommand`:

1. Without `BB_MACHINE_SERVER_URL`, prints what to set and exits 0, so the
   container still starts.
2. Writes the token, if any, to two 0600 files in the 0700 runtime directory:
   the daemon's `BB_SERVER_HEADERS` (`CF-Access-Client-Id` and
   `CF-Access-Client-Secret`), and a curl config. The token never reaches an
   argv, a log or stdout.
3. On first start only, asks the server for an enroll key
   (`POST /internal/hosts/enroll-key`) with those headers. bb-app 0.45.0's own
   `host-daemon join` makes this request without `BB_SERVER_HEADERS`, so
   behind Access it gets the login page. The server hands enroll keys to
   loopback callers only. A server behind cloudflared on its own box sees
   cloudflared's loopback connection.
4. Starts `bb-app host-daemon --server-url <url> --supervise` in a new session,
   as standalone mode does, so Codespaces' lifecycle cleanup does not stop
   it. `--supervise` restarts it after a crash. It waits up to 60 seconds for
   the daemon to report `Connected to server`, then drops the spent enroll key
   from its environment file.

`bb-feature-status` says whether the daemon runs and its newest session is
connected. A stopped Codespace drops off the server; on resume the start
hook brings the daemon back, and BB's daemon reconnects on its own after
network drops.

BB finds the learner's coding agents (Claude Code, Codex, pi) from the login
shell's PATH, so install them with their Features in the same container and
sign in to them once inside it.

The `machine` CI scenario covers what needs no server: install, no-secret
start, refusal of http URLs and half a token, and that the token files are
0600. A connected machine was checked by hand on 2026-10-04 against a hosted
bb-app 0.45.0 server behind Cloudflare Access, with `devcontainer up
--secrets-file` standing in for Codespaces secrets. It connected in about 3
seconds, survived a container restart, and kept the token out of every argv
and log.

## Validation boundary

The repository CI scenarios exercise installation, CLI/no-start behavior,
standalone health/static/API responses, same-origin WebSocket upgrade,
foreign realtime and terminal-origin rejection, custom ports/origins, state
paths containing spaces, ancestor-symlink rejection, and lifecycle idempotence
in disposable containers. Successful WebSocket checks are bounded because a
101 connection correctly remains open. They use no credentials, published
Docker ports, or ambient BB configuration.

The following require a real learner-owned Codespace and remain deliberately
unexecuted here: GitHub's private-port forwarding/authentication UI, a browser
end-to-end session over the forwarded HTTPS origin, provider/device login and
paid-provider work, stop/rebuild persistence in GitHub, and organization port
policy enforcement. Perform those acceptance steps manually before relying on
this Feature for a course or production workflow.
