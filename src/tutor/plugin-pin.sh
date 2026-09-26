# shellcheck shell=bash
# ============================================================================
# THE PINNED TUTOR PLUGIN RELEASE. This is the one place that says which
# bb-plugin-tutor release the Feature installs by default, and its checksum.
#
# To adopt a new release <v>:
#   1. download https://github.com/lean-software-production/bb-plugin-tutor/releases/download/v<v>/bb-plugin-tutor-<v>.tgz
#      and compute its SHA-256 yourself (sha256sum); do not just copy the
#      release's .sha256 file;
#   2. set both values below;
#   3. set the pluginVersion default in devcontainer-feature.json to <v>
#      (test/tutor/plugin-fetch-hermetic.sh fails if the two differ), bump
#      the Feature version, and run .devcontainer/tutor/sync-features.sh.
#
# Until the SHA-256 is set, a build that uses the default pluginVersion fails
# with a message; pluginVersion plus pluginSha256 still work.
# ============================================================================
# shellcheck disable=SC2034 # read by install.sh and the tests
TUTOR_PLUGIN_PINNED_VERSION=0.1.0
# shellcheck disable=SC2034
TUTOR_PLUGIN_PINNED_SHA256=896be0694fbccec1f4487479713026de9d026a9716b748308ed02b87c0b635d4
