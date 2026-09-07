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
# Fabro bakes this into browser auth routes and generated links. Inside a
# Codespace the server is reachable through the forwarded host, not 127.0.0.1,
# so FABRO_WEB_URL has to reflect that or the UI links point somewhere the
# browser cannot follow. Anywhere else, loopback is correct.
fabro_web_url() {
    local port
    port="$(fabro_port)"
    if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
        printf 'http://%s-%s.%s' "${CODESPACE_NAME}" "${port}" "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    else
        printf 'http://127.0.0.1:%s' "${port}"
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

# Codespaces terminates HTTPS at its tunnel and forwards plain HTTP with the
# public Host header. Persist that upstream origin so Fabro does not redirect
# every tunneled request back through the same public URL.
fabro_sync_codespaces_urls() {
    [ -n "${CODESPACE_NAME:-}" ] || return 0
    [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ] || return 0

    local settings origin api_url tmp
    settings="${HOME}/.fabro/settings.toml"
    [ -f "${settings}" ] || return 0
    origin="http://${CODESPACE_NAME}-$(fabro_port).${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
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

# Start the server if it is not already up, with its persisted setup defaults.
fabro_start_server() {
    fabro_sync_codespaces_urls || return 1
    fabro server status >/dev/null 2>&1 && return 0
    fabro_server_args
    FABRO_WEB_URL="$(fabro_web_url)" fabro server start "${FABRO_SERVER_ARGS[@]}" >/dev/null 2>&1
}

fabro_restart_server() {
    fabro_sync_codespaces_urls || return 1
    fabro_server_args
    FABRO_WEB_URL="$(fabro_web_url)" fabro server restart "${FABRO_SERVER_ARGS[@]}"
}
