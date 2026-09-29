#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "fabro on PATH" bash -c "fabro --version | grep -q '^fabro '"
check "wizard on PATH" bash -c "command -v fabro-setup"
check "status helper on PATH" bash -c "command -v fabro-status"
check "bootstrap installed" bash -c "test -x /usr/local/share/fabro/bin/fabro-bootstrap"
check "autostart installed" bash -c "test -x /usr/local/share/fabro/bin/fabro-autostart"
check "shared helpers installed" bash -c "test -r /usr/local/share/fabro/bin/fabro-common.sh"

# Autostart runs on every container start, including before setup has ever run.
# With no settings.toml it must be a silent no-op, not an error.
check "autostart no-ops before setup" bash -c "/usr/local/share/fabro/bin/fabro-autostart"

# The canonical origin must match the Host browsers actually send, which is
# localhost in a Codespace (the forwarder proxies in as localhost) and on a
# published dev container port alike. Pointing it at the forwarded name sends
# the browser into a redirect loop, so this must not vary by environment.
check "web url is localhost outside codespaces" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && unset CODESPACE_NAME GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN && fabro_web_url | grep -q '^http://localhost:32276$'"
check "web url stays localhost inside a codespace" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && CODESPACE_NAME=demo GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev fabro_web_url | grep -q '^http://localhost:32276$'"

# The address shown to a human is the forwarded name, and is display-only.
check "browse url is localhost outside codespaces" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && unset CODESPACE_NAME GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN && fabro_browse_url | grep -q '^http://localhost:32276$'"
check "browse url uses the forwarded host in a codespace" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && CODESPACE_NAME=demo GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev fabro_browse_url | grep -q '^https://demo-32276.app.github.dev$'"
# OpenRouter ships disabled, and the server rejects a login to it until
# settings.toml enables it. The helper must add the table, flip an existing
# `enabled = false`, and leave an already-enabled file with a single entry.
check "enable provider adds a missing table" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "_version = 1\n\n[server.web]\nenabled = true\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh && fabro_enable_provider openrouter
  awk "/^\\[/{t=\$0} t==\"[llm.providers.openrouter]\" && /^enabled = true\$/{n++} END{exit n!=1}" "$HOME/.fabro/settings.toml"
  grep -q "^\[server.web\]" "$HOME/.fabro/settings.toml"'
check "enable provider flips enabled = false" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "[llm.providers.openrouter]\nenabled = false\n\n[server.web]\nenabled = true\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh && fabro_enable_provider openrouter
  if grep -q "enabled = false" "$HOME/.fabro/settings.toml"; then exit 1; fi
  test "$(grep -c "^\[llm.providers.openrouter\]" "$HOME/.fabro/settings.toml")" = 1'
check "enable provider is idempotent" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "_version = 1\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh
  fabro_enable_provider openrouter && fabro_enable_provider openrouter
  test "$(grep -c "^\[llm.providers.openrouter\]" "$HOME/.fabro/settings.toml")" = 1
  test "$(grep -c "^enabled = true\$" "$HOME/.fabro/settings.toml")" = 1'
check "toml set matches a table written without quotes" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "[llm.providers.openrouter.models.claude-sonnet-5]\ndefault = true\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh
  fabro_toml_set "llm.providers.openrouter.models.\"claude-sonnet-5\"" default false
  test "$(grep -c "^\[" "$HOME/.fabro/settings.toml")" = 1
  grep -qx "default = false" "$HOME/.fabro/settings.toml"'
check "jq installed for the setup scripts" bash -c "command -v jq"

# Sign-in checks an API key against the catalog probe model, so the chosen
# model must become the only probe and the only default. `fabro` is stubbed
# with a catalog whose default is Sonnet.
check "use catalog model moves the probe and the default" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "[llm.providers.openrouter.models.\"glm-5.2\"]\nprobe = true\ndefault = true\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh
  fabro() { printf "%s" "[{\"id\":\"claude-sonnet-5\",\"default\":true},{\"id\":\"glm-5.2\",\"default\":true},{\"id\":\"glm-5.3-flash\",\"default\":false}]"; }
  fabro_use_catalog_model openrouter glm-5.3-flash
  s="$HOME/.fabro/settings.toml"
  test "$(grep -c "^probe = true\$" "$s")" = 1
  test "$(grep -c "^default = true\$" "$s")" = 1
  test "$(grep -c "^default = false\$" "$s")" = 2
  awk "/^\\[/{t=\$0} /^probe = true\$/{print t}" "$s" | grep -qxF "[llm.providers.openrouter.models.\"glm-5.3-flash\"]"'

# A newer OpenRouter model is added from OpenRouter's model list, stubbed here.
check "add openrouter model writes a catalog entry" bash -c '
  set -e
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "_version = 1\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh
  curl() { printf "%s" "{\"data\":[{\"id\":\"z-ai/glm-5.3-flash\",\"name\":\"Z.ai: GLM 5.3 Flash\",\"context_length\":1310720,\"top_provider\":{\"max_completion_tokens\":131072},\"supported_parameters\":[\"tools\",\"reasoning\"],\"architecture\":{\"input_modalities\":[\"text\"]},\"pricing\":{\"prompt\":\"0.00000015\",\"completion\":\"0.0000005\"}}]}"; }
  fabro_add_openrouter_model z-ai/glm-5.3-flash glm-5.3-flash
  s="$HOME/.fabro/settings.toml"
  grep -qxF "[llm.providers.openrouter.models.\"glm-5.3-flash\"]" "$s"
  grep -qxF "api_id = \"z-ai/glm-5.3-flash\"" "$s"
  grep -qxF "limits = { context_window = 1310720, max_output = 131072 }" "$s"
  grep -qxF "features = { tools = true, vision = false, reasoning = true }" "$s"
  grep -qxF "costs = { input_cost_per_mtok = 0.15, output_cost_per_mtok = 0.5 }" "$s"'
check "add openrouter model fails for an unknown slug" bash -c '
  export HOME="$(mktemp -d)" && mkdir -p "$HOME/.fabro"
  printf "_version = 1\n" > "$HOME/.fabro/settings.toml"
  source /usr/local/share/fabro/bin/fabro-common.sh
  curl() { printf "%s" "{\"data\":[]}"; }
  ! fabro_add_openrouter_model z-ai/nope nope && ! grep -q nope "$HOME/.fabro/settings.toml"'
check "options recorded for runtime" bash -c "grep -q '^FABRO_SETUP_PROVIDER=' /usr/local/share/fabro/setup.env"
check "model option defaults to auto" bash -c "grep -q '^FABRO_SETUP_MODEL=auto$' /usr/local/share/fabro/setup.env"
check "shell banner wired into bashrc" bash -c "grep -q 'fabro/banner.sh' /etc/bash.bashrc"

# The wizard is launched from a folderOpen task, which may or may not give it a
# terminal. Without one it must explain itself and exit 0, never hang or fail.
check "wizard exits cleanly without a tty" bash -c "fabro-setup </dev/null | grep -q 'fabro-setup'"

# No provider is configured in a fresh container, so status must say so.
check "status reports unconfigured" bash -c "! fabro-status --quiet"

reportResults
