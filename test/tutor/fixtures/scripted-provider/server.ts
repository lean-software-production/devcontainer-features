// Scripted provider, a Tutor test fixture. A credential-free agent provider
// whose bridge (host.ts) answers every prompt with a report of the dynamic
// tools and skills BB offered the thread, makes the tool calls the prompt
// scripts, and echoes `::directive{…}` lines verbatim as assistant markdown.
import type { BbPluginApi } from "@get-bb/plugin-sdk";

export default function plugin(bb: BbPluginApi) {
  bb.providers.register({
    id: "scripted",
    displayName: "Scripted (test fixture)",
    icon: "Zap",
    strings: {
      signInHint: "Nothing to sign in to: the scripted agent runs offline.",
      expiredHint: "Scripted sessions never expire.",
      installUrl: "https://example.invalid/scripted-provider",
    },
    maintenance: { health: true, usage: false, installation: false },
    capabilities: {
      supportsServiceTier: false,
      supportsNativeUserQuestion: false,
      fork: "none",
      supportsManualCompaction: false,
      supportsThreadArchive: false,
      supportsThreadRename: false,
      permissionModes: ["accept-edits", "auto", "full"],
      reasoningLevels: ["medium"],
    },
    models: {
      scope: "host",
      fallback: [
        {
          id: "scripted-1",
          displayName: "Scripted 1",
          description: "Reports what it was offered.",
          supportedReasoningEfforts: [{ reasoningEffort: "medium", description: "Default" }],
          defaultReasoningEffort: "medium",
          isDefault: true,
        },
      ],
    },
    composerActions: [],
    completedTurnDisplay: "flat",
  });
  bb.log.info("[scripted] provider registered");
}
