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
        printf 'https://%s-%s.%s' "${CODESPACE_NAME}" "${port}" "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    else
        printf 'http://127.0.0.1:%s' "${port}"
    fi
}

# Start the server if it is not already up, with the right web origin.
fabro_start_server() {
    fabro server status >/dev/null 2>&1 && return 0
    FABRO_WEB_URL="$(fabro_web_url)" fabro server start >/dev/null 2>&1
}
