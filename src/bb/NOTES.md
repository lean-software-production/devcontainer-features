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
tolerate transient startup/plugin load. Status never restarts or signals the
launcher; it fails if either service remains unavailable. Autostart refuses a healthy port
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
