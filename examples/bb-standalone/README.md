# BB standalone Codespaces example

This is a copyable **local Feature validation** configuration, not a published
BB Feature reference. In a consumer repository, copy this file to
`.devcontainer/devcontainer.json`, then copy this repository's `src/bb`
directory to `.devcontainer/features/bb`. Dev Containers requires local
Features to be children of the consuming `.devcontainer` directory, so a path
such as `../src/bb` is rejected. After BB is published, replace
`./features/bb` with
`ghcr.io/lean-software-production/devcontainer-features/bb:1` and remove the
copied directory.

It uses Node 24, standalone BB with autostart, state in the persistent,
user-writable workspace checkout, and forwards only port 38886. Add
`/.bb-state/` to the consumer repository's `.gitignore`. It also composes the
published Codex Feature as an example local worker; it performs no sign-in, so
run `codex login
--device-auth` interactively if you choose to use it. After creating a
Codespace, use the Ports view to confirm port 38886 is **Private** before
opening it. `portsAttributes` cannot declare visibility. The forwarded backend
protocol is HTTP; GitHub presents an HTTPS browser URL. Do not forward 38887.

Sign in to providers interactively after opening BB. No login happens during
the build or lifecycle hooks. See [the Feature notes](../../src/bb/NOTES.md)
for the security boundary, persistence, and deferred live acceptance tests.
