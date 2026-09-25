# Scripted provider (test fixture)

A credential-free BB agent provider (id `scripted`) used by the Tutor tests
instead of a real coding agent. It targets bb-app 0.43.4 and plugin SDK 0.5.9,
and is modelled on upstream `examples/plugins/echo-provider`.

**Never install this into a BB you care about.** Use a disposable container,
such as the Feature scenarios in `test/tutor/` or `scripts/tutor-dev/`.

Every turn replies with one assistant message that reports:

- the `dynamicTools` BB offered at `thread/start` or `thread/resume` (tool
  scoping by `bb.agents.configure`, as the provider sees it),
- the skills BB offered through `skills/configure`, and
- every prompt line that starts with `::`, echoed verbatim, so message
  directives render as real assistant markdown.

Two prompt lines make the bridge call a tool:

- `CALL <tool> {json}` calls the tool over `item/tool/call`, but only if the
  tool was offered.
- `FORCECALL <tool> {json}` calls it even if it was not offered. BB 0.43.4 runs
  such a call, so this checks that the plugin's own `execute()` refuses it.

Every event is also appended to
`<BB dataDir>/plugins/scripted-provider/bridge-data/turns.ndjson`.

```sh
npm ci --omit=dev
bb plugin install "$PWD" --yes
bb thread spawn --project <id> --provider scripted --prompt-file <file>
```

BB runs one bridge process per thread session. `bb plugin reload` does not
restart the bridge of a live thread; run `bb thread stop <id>` first.
