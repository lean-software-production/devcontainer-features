# Shared helpers for the Fabro setup scripts. Sourced, not executed.

# Port the Fabro server listens on, read from the [server.listen] address.
fabro_port() {
    local settings="${HOME}/.fabro/settings.toml" port=""
    if [ -f "${settings}" ]; then
        port="$(awk '
            /^\[/ { in_listen = ($0 == "[server.listen]") }
            in_listen && /^address[[:space:]]*=/ {
                gsub(/.*:|"/, "", $0); print $0; exit
            }
        ' "${settings}")"
    fi
    printf '%s' "${port:-32276}"
}

# Canonical browser origin for the server.
#
# Fabro serves a single canonical origin and 308s any browser request arriving
# under a different Host, so this must match what browsers actually send -- not
# where the server happens to be reachable from.
#
# The Codespaces forwarder terminates the public HTTPS name itself and proxies
# to the container as `Host: localhost:<port>`. It reports the public name in
# X-Forwarded-Host, which Fabro does not consult for this check. A browser on
# the host of a dev container that publishes the port also sends
# `Host: localhost:<port>`. Plain localhost is therefore correct in both.
#
# The forwarded URL is not: setting the origin to it makes Fabro redirect every
# forwarded request back through the forwarder, which arrives as localhost
# again -- an infinite loop the browser reports as ERR_TOO_MANY_REDIRECTS. The
# generated default of 127.0.0.1 is wrong too; it does not match `localhost`,
# so every request is bounced to an address the browser may not reach.
#
# For the address to show a human, use fabro_browse_url.
fabro_web_url() {
    printf 'http://localhost:%s' "$(fabro_port)"
}

# The address a human opens: the forwarded HTTPS name in a Codespace, and the
# published port everywhere else. Display only -- never pass it as
# FABRO_WEB_URL.
fabro_browse_url() {
    local port
    port="$(fabro_port)"
    if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
        printf 'https://%s-%s.%s' "${CODESPACE_NAME}" "${port}" "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    else
        printf 'http://localhost:%s' "${port}"
    fi
}

# Setup owns these defaults because the Fabro server CLI accepts them only as
# startup flags. They deliberately do not live in [run.*], which is client-side
# configuration and is not submitted by `fabro run`.
fabro_server_defaults_file() {
    printf '%s/.fabro/fabro-server-defaults' "${HOME}"
}

fabro_server_default() {
    local key="$1" defaults
    defaults="$(fabro_server_defaults_file)"
    [ -r "${defaults}" ] || return 0
    awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "${defaults}"
}

fabro_server_args() {
    local provider model environment
    provider="$(fabro_server_default provider)"
    model="$(fabro_server_default model)"
    environment="$(fabro_server_default environment)"

    FABRO_SERVER_ARGS=()
    [ -n "${provider}" ] && FABRO_SERVER_ARGS+=(--provider "${provider}")
    [ -n "${model}" ] && FABRO_SERVER_ARGS+=(--model "${model}")
    [ -n "${environment}" ] && FABRO_SERVER_ARGS+=(--environment "${environment}")
}

# FABRO_WEB_URL is runtime-only: it sets the origin for the process it starts
# and is never written back. Persist the same value so that a later
# `fabro server restart` by hand does not silently fall back to the 127.0.0.1
# origin that `fabro install` generates.
fabro_sync_server_urls() {
    local settings origin api_url tmp
    settings="${HOME}/.fabro/settings.toml"
    [ -f "${settings}" ] || return 0
    origin="$(fabro_web_url)"
    api_url="${origin}/api/v1"
    tmp="$(mktemp "${settings}.tmp.XXXXXX")" || return 1

    awk -v api_url="${api_url}" -v web_url="${origin}" '
        BEGIN { in_api = 0; in_web = 0; saw_api = 0; saw_web = 0; wrote_api = 0; wrote_web = 0 }
        /^\[/ {
            if (in_api && !wrote_api) print "url = \"" api_url "\""
            if (in_web && !wrote_web) print "url = \"" web_url "\""
            in_api = ($0 == "[server.api]")
            in_web = ($0 == "[server.web]")
            if (in_api) saw_api = 1
            if (in_web) saw_web = 1
            print
            next
        }
        in_api && /^url[[:space:]]*=/ { print "url = \"" api_url "\""; wrote_api = 1; next }
        in_web && /^url[[:space:]]*=/ { print "url = \"" web_url "\""; wrote_web = 1; next }
        { print }
        END {
            if (in_api && !wrote_api) print "url = \"" api_url "\""
            if (in_web && !wrote_web) print "url = \"" web_url "\""
            if (!saw_api) print "\n[server.api]\nurl = \"" api_url "\""
            if (!saw_web) print "\n[server.web]\nenabled = true\nurl = \"" web_url "\""
        }
    ' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"
}

# The file fabro_toml_set and fabro_toml_unset_under edit. fabro_batch_settings
# points it at a copy.
fabro_settings_file() {
    printf '%s' "${FABRO_SETTINGS_FILE:-${HOME}/.fabro/settings.toml}"
}

# Run a command whose settings.toml edits go to a copy, then replace the file
# in one step. The server reloads the file whenever it changes, and rejects the
# half-written model table or doubled default an edit can pass through.
fabro_batch_settings() {
    local settings tmp
    settings="${HOME}/.fabro/settings.toml"
    tmp="$(mktemp "${settings}.tmp.XXXXXX")" || return 1
    if cp "${settings}" "${tmp}" && FABRO_SETTINGS_FILE="${tmp}" "$@"; then
        mv "${tmp}" "${settings}"
    else
        rm -f "${tmp}"
        return 1
    fi
}

# Set `<key> = <value>` in [<table>] of settings.toml, replacing the key if it
# is there and adding it, or the table, if not. The value is written verbatim,
# so quote TOML strings yourself. Table names compare with quotes removed, so
# [a."b"] finds an existing [a.b]. Values travel through ENVIRON rather than
# `awk -v`, which would expand the backslash escapes in a quoted string.
fabro_toml_set() {
    local settings tmp
    settings="$(fabro_settings_file)"
    [ -f "${settings}" ] || return 1
    tmp="$(mktemp "${settings}.tmp.XXXXXX")" || return 1

    TOML_TABLE="$1" TOML_KEY="$2" TOML_VALUE="$3" awk '
        function norm(s) { gsub(/[][" \t]/, "", s); return s }
        BEGIN {
            table = ENVIRON["TOML_TABLE"]; key = ENVIRON["TOML_KEY"]
            want = norm(table); line = key " = " ENVIRON["TOML_VALUE"]
        }
        # Blank lines are held back so a key added at the end of a table goes
        # before the gap that separates it from the next one.
        /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
        /^\[/ {
            if (in_table && !wrote) { print line; wrote = 1 }
            printf "%s", blanks; blanks = ""
            in_table = (norm($0) == want)
            if (in_table) saw_table = 1
            print
            next
        }
        { printf "%s", blanks; blanks = "" }
        in_table && $0 ~ ("^" key "[[:space:]]*=") { print line; wrote = 1; next }
        { print }
        END {
            if (in_table && !wrote) print line
            printf "%s", blanks
            if (!saw_table) print "\n[" table "]\n" line
        }
    ' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"
}

# Run a command that edits settings.toml, and put the file back as it was if
# the command fails -- such as when the installed Fabro rejects the new settings,
# which would otherwise stop the server from starting next time.
fabro_edit_settings_or_restore() {
    local settings backup
    settings="${HOME}/.fabro/settings.toml"
    backup="$(mktemp)" && cp "${settings}" "${backup}" || return 1
    if "$@"; then
        rm -f "${backup}"
        return 0
    fi
    cp "${backup}" "${settings}"
    rm -f "${backup}"
    return 1
}

# Remove `<key> = ...` from every table whose name starts with <prefix>.
fabro_toml_unset_under() {
    local settings tmp
    settings="$(fabro_settings_file)"
    [ -f "${settings}" ] || return 1
    tmp="$(mktemp "${settings}.tmp.XXXXXX")" || return 1

    TOML_PREFIX="$1" TOML_KEY="$2" awk '
        function norm(s) { gsub(/[][" \t]/, "", s); return s }
        BEGIN { prefix = norm(ENVIRON["TOML_PREFIX"]); key = ENVIRON["TOML_KEY"] }
        /^\[/ { in_scope = (index(norm($0), prefix) == 1); print; next }
        in_scope && $0 ~ ("^" key "[[:space:]]*=") { next }
        { print }
    ' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"
}

# Some providers, such as OpenRouter, ship in Fabro's catalog but disabled.
# Until settings.toml enables them the server rejects `fabro provider login`
# with "provider '<name>' is not configured in the server model catalog".
# Set `enabled = true` in [llm.providers.<name>], adding the table if needed.
fabro_enable_provider() {
    fabro_toml_set "llm.providers.$1" enabled true
}

# Model IDs in the provider's catalog, and the ones it marks as default.
fabro_catalog_models() {
    fabro model list --provider "$1" --json 2>/dev/null | jq -r '.[].id'
}

fabro_catalog_defaults() {
    fabro model list --provider "$1" --json 2>/dev/null \
        | jq -r '.[] | select(.default == true) | .id'
}

# `fabro provider login` checks an API key by sending one request to the
# catalog's probe model -- Claude Sonnet, for OpenRouter. A key limited to other
# models, such as by an OpenRouter guardrail, fails that check even though it
# works. Make <model> the probe, and the provider's default so the server
# reports when it has loaded the change, via fabro_wait_for_default_model.
fabro_use_catalog_model() {
    local defaults
    defaults="$(fabro_catalog_defaults "$1")"
    fabro_batch_settings fabro_write_catalog_model "$1" "$2" "${defaults}"
}

fabro_write_catalog_model() {
    local provider="$1" model="$2" defaults="$3" prefix other
    prefix="llm.providers.${provider}.models"
    while IFS= read -r other; do
        [ -n "${other}" ] && [ "${other}" != "${model}" ] || continue
        fabro_toml_set "${prefix}.\"${other}\"" default false || return 1
    done <<< "${defaults}"
    # Fabro does not reject two probes; it silently uses one of them.
    fabro_toml_unset_under "${prefix}." probe || return 1
    fabro_toml_set "${prefix}.\"${model}\"" probe true \
        && fabro_toml_set "${prefix}.\"${model}\"" default true
}

# Add an OpenRouter model that the installed Fabro's catalog does not ship,
# such as one released after it, under the ID <model>. The catalog needs its
# limits and features, so they come from OpenRouter's public model list.
fabro_add_openrouter_model() {
    local slug="$1" model="$2" fields
    fields="$(curl -fsSL https://openrouter.ai/api/v1/models | jq -r --arg slug "${slug}" '
        .data[] | select(.id == $slug)
        | (.pricing.prompt | tonumber) as $in
        | (.pricing.completion | tonumber) as $out
        | "api_id = \(.id | tojson)",
          "display_name = \("\(.name) (via OpenRouter)" | tojson)",
          "family = \(.id | split("/")[0] | tojson)",
          "limits = { context_window = \(.context_length // 131072), max_output = \(.top_provider.max_completion_tokens // 16384) }",
          "features = { tools = \(.supported_parameters | index("tools") != null), vision = \(.architecture.input_modalities | index("image") != null), reasoning = \(.supported_parameters | index("reasoning") != null) }",
          if $in >= 0 and $out >= 0 then
              "costs = { input_cost_per_mtok = \($in * 1e9 | round / 1000), output_cost_per_mtok = \($out * 1e9 | round / 1000) }"
          else empty end
    ')" || return 1
    [ -n "${fields}" ] || return 1
    fabro_batch_settings fabro_write_table "llm.providers.openrouter.models.\"${model}\"" "${fields}"
}

# Write each `key = value` line of $2 into table $1.
fabro_write_table() {
    local line
    while IFS= read -r line; do
        fabro_toml_set "$1" "${line%% = *}" "${line#* = }" || return 1
    done <<< "$2"
}

# The server live-reloads settings.toml a few seconds after it changes. Wait
# until the provider's models appear in the catalog, for up to $2 seconds.
fabro_wait_for_provider() {
    local provider="$1" timeout="${2:-15}" i
    for ((i = 0; i < timeout; i++)); do
        fabro model list --provider "${provider}" --json 2>/dev/null \
            | grep -q '"id"' && return 0
        sleep 1
    done
    return 1
}

# Same, until <model> is in the provider's catalog, or is its default. A
# settings.toml the server cannot load is rejected and the previous one kept, so
# these also tell whether the installed Fabro accepted the change.
fabro_wait_for_model() {
    local provider="$1" model="$2" timeout="${3:-15}" i
    for ((i = 0; i < timeout; i++)); do
        fabro_catalog_models "${provider}" | grep -qxF "${model}" && return 0
        sleep 1
    done
    return 1
}

fabro_wait_for_default_model() {
    local provider="$1" model="$2" timeout="${3:-15}" i
    for ((i = 0; i < timeout; i++)); do
        fabro_catalog_defaults "${provider}" | grep -qxF "${model}" && return 0
        sleep 1
    done
    return 1
}

# Start the server if it is not already up, with its persisted setup defaults.
fabro_start_server() {
    fabro_sync_server_urls || return 1
    fabro server status >/dev/null 2>&1 && return 0
    fabro_server_args
    FABRO_WEB_URL="$(fabro_web_url)" fabro server start "${FABRO_SERVER_ARGS[@]}" >/dev/null 2>&1
}

fabro_restart_server() {
    fabro_sync_server_urls || return 1
    fabro_server_args
    FABRO_WEB_URL="$(fabro_web_url)" fabro server restart "${FABRO_SERVER_ARGS[@]}"
}
