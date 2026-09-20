# BB standalone Codespaces example

This is a copyable **local Feature validation** configuration, not a published
Feature reference. From a clone of this repository it resolves `../../src/bb`.
For a consumer repository, copy this file into `.devcontainer/devcontainer.json`
and either package the local Features for validation or replace the BB path
with the future `ghcr.io/lean-software-production/devcontainer-features/bb:1`
reference after publication. Replace the local Codex path with its published
reference too, or remove that optional worker Feature.

It uses Node 24, standalone BB with autostart, state outside the checkout, and
forwards only port 38886. It also composes this repository's Codex Feature as
an example local worker; it performs no sign-in, so run `codex login
--device-auth` interactively if you choose to use it. After creating a
Codespace, use the Ports view to confirm port 38886 is **Private** before
opening it. `portsAttributes` cannot declare visibility. The forwarded backend
protocol is HTTP; GitHub presents an HTTPS browser URL. Do not forward 38887.

Sign in to providers interactively after opening BB. No login happens during
the build or lifecycle hooks. See [the Feature notes](../../src/bb/NOTES.md)
for the security boundary, persistence, and deferred live acceptance tests.
