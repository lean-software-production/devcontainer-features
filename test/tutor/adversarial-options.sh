#!/usr/bin/env bash
# Runs without an image build so CI can verify rejection paths that cannot be
# represented as successful Feature scenarios. Option validation happens before
# the installer touches the system, and the runner has no bb Feature, so even an
# accepted option set stops at the bb prerequisite without installing anything.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/src/tutor/install.sh"
[ ! -e /usr/local/share/bb ] || { echo "refusing to run: a bb Feature is installed here, so accepted options would really install" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_installer() { env -i PATH="$PATH" HOME="$tmp" "$@" bash "$installer" >"$tmp/out" 2>&1; }

expect_reject() {
    local label="$1" message="$2"; shift 2
    if run_installer "$@"; then
        echo "expected rejection: $label" >&2
        exit 1
    fi
    grep -qF -- "$message" "$tmp/out" || { echo "rejected for the wrong reason: $label" >&2; cat "$tmp/out" >&2; exit 1; }
}

expect_reject 'relative course' 'course must be' COURSE=tutorial
expect_reject 'course is the root' 'course must be' COURSE=/
expect_reject 'shell injection in course' 'course must be' COURSE='/tmp/a;touch pwned'
expect_reject 'quote in course' 'course must be' COURSE='/tmp/a"b'
expect_reject 'dot traversal in course' 'course must be' COURSE=/workspaces/../etc
# shellcheck disable=SC2016 # the literal text is the attack
expect_reject 'command substitution in factory' 'factory must be' FACTORY='/tmp/$(id)'
expect_reject 'relative factory' 'factory must be' FACTORY=my-factory
expect_reject 'factory equals course' 'must be different' COURSE=/workspaces/x FACTORY=/workspaces/x/
expect_reject 'relative starter' 'starter must be' STARTER=capstone-project-starter
# shellcheck disable=SC2016 # the literal text is the attack
expect_reject 'command substitution in starter' 'starter must be' STARTER='/tmp/$(id)'
expect_reject 'starter equals course' 'starter and course must be different' COURSE=/workspaces/x STARTER=/workspaces/x/
# A ${...} the tool building the container left unsubstituted (Codespaces and
# the devcontainer CLI substitute ${containerWorkspaceFolder} in Feature options).
# shellcheck disable=SC2016 # the literal text is the point
expect_reject 'unsubstituted workspace variable as starter' 'unsubstituted ${...} variable' STARTER='${containerWorkspaceFolder}'
# shellcheck disable=SC2016 # the literal text is the point
expect_reject 'unsubstituted variable inside an absolute starter' 'unsubstituted ${...} variable' STARTER='/workspaces/${localWorkspaceFolderBasename}'
expect_reject 'starterRepo without starter' 'starterRepo needs a starter' STARTERREPO=https://github.com/lean-software-production/capstone-project-starter.git
expect_reject 'plain http starterRepo' 'starterRepo must be' STARTER=/workspaces/s STARTERREPO=http://github.com/lean-software-production/capstone-project-starter.git
expect_reject 'option injection in starterRepo' 'starterRepo must be' STARTER=/workspaces/s STARTERREPO='--upload-pack=touch pwned'
expect_reject 'shell metacharacter in starterRepo' 'starterRepo must be' STARTER=/workspaces/s STARTERREPO='https://github.com/x/y.git;touch pwned'
expect_reject 'credentials in starterRepo' 'no credentials' STARTER=/workspaces/s STARTERREPO=https://user:secret@github.com/x/y.git
expect_reject 'bad selectOutline' 'selectOutline must be' SELECTOUTLINE=yes
expect_reject 'bad lightTheme' 'lightTheme must be' LIGHTTHEME=yes
expect_reject 'upper-case lightTheme' 'lightTheme must be' LIGHTTHEME=TRUE
expect_reject 'shell injection in lightTheme' 'lightTheme must be' LIGHTTHEME='true;touch pwned'
expect_reject 'unknown appIcons' 'appIcons must be' APPICONS=tutor
expect_reject 'upper-case appIcons' 'appIcons must be' APPICONS=LSP
expect_reject 'empty appIcons' 'appIcons must be' APPICONS=
expect_reject 'shell injection in appIcons' 'appIcons must be' APPICONS='lsp;touch pwned'
expect_reject 'ssh courseRepo' 'courseRepo must be' COURSEREPO=git@github.com:lean-software-production/tutorial.git
expect_reject 'plain http courseRepo' 'courseRepo must be' COURSEREPO=http://github.com/lean-software-production/tutorial.git
expect_reject 'option injection in courseRepo' 'courseRepo must be' COURSEREPO='--upload-pack=touch pwned'
expect_reject 'shell metacharacter in courseRepo' 'courseRepo must be' COURSEREPO='https://github.com/x/y.git;touch pwned'
expect_reject 'credentials in courseRepo' 'no credentials' COURSEREPO=https://user:secret@github.com/x/y.git
expect_reject 'shell injection in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations;touch pwned'
expect_reject 'upper case in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS=Automations
expect_reject 'empty item in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations,,workflows'
expect_reject 'space in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations, workflows'
expect_reject 'shell injection in theme' 'theme must be' THEME='plugin:tutor:sketchbook;touch pwned'
expect_reject 'space in theme' 'theme must be' THEME='my theme'
sha="$(printf '%064d' 7)"
# A release other than the one plugin-pin.sh pins, whatever that is.
# shellcheck source=../../src/tutor/plugin-pin.sh
. "$repo_root/src/tutor/plugin-pin.sh"
other="$((${TUTOR_PLUGIN_PINNED_VERSION%%.*} + 1)).0.0"
expect_reject "a 'v' prefix in pluginVersion" 'pluginVersion must be' PLUGINVERSION=v0.1.0 PLUGINSHA256="$sha"
expect_reject 'a range in pluginVersion' 'pluginVersion must be' PLUGINVERSION='^0.1.0' PLUGINSHA256="$sha"
expect_reject 'a partial pluginVersion' 'pluginVersion must be' PLUGINVERSION=0.1 PLUGINSHA256="$sha"
expect_reject 'a leading zero in pluginVersion' 'pluginVersion must be' PLUGINVERSION=0.01.0 PLUGINSHA256="$sha"
expect_reject 'build metadata in pluginVersion' 'pluginVersion must be' PLUGINVERSION=0.1.0+build.1 PLUGINSHA256="$sha"
expect_reject 'an empty pluginVersion' 'pluginVersion must be' PLUGINVERSION=
expect_reject 'shell injection in pluginVersion' 'pluginVersion must be' PLUGINVERSION='0.1.0;touch pwned' PLUGINSHA256="$sha"
# shellcheck disable=SC2016 # the literal text is the attack
expect_reject 'command substitution in pluginVersion' 'pluginVersion must be' PLUGINVERSION='0.1.0-$(id)' PLUGINSHA256="$sha"
expect_reject 'a path in pluginVersion' 'pluginVersion must be' PLUGINVERSION=../0.1.0 PLUGINSHA256="$sha"
expect_reject 'a newline in pluginVersion' 'pluginVersion must be' PLUGINVERSION=$'0.1.0\n0.2.0' PLUGINSHA256="$sha"
expect_reject 'an upper-case pluginSha256' 'pluginSha256 must be' PLUGINVERSION="$other" PLUGINSHA256="$(printf 'A%063d' 0)"
expect_reject 'a short pluginSha256' 'pluginSha256 must be' PLUGINVERSION="$other" PLUGINSHA256="${sha:1}"
expect_reject 'a non-hex pluginSha256' 'pluginSha256 must be' PLUGINVERSION="$other" PLUGINSHA256="g${sha:1}"
expect_reject 'shell injection in pluginSha256' 'pluginSha256 must be' PLUGINVERSION="$other" PLUGINSHA256="${sha:10};touch pwned"
expect_reject 'another pluginVersion without pluginSha256' 'pluginSha256 is required' PLUGINVERSION="$other"
expect_reject 'a pluginSha256 that differs from the pin' "differs from this Feature's pinned SHA-256" PLUGINSHA256="$sha"
expect_reject 'latest with a pluginSha256' "pluginSha256 must be empty when pluginVersion is 'latest'" PLUGINVERSION=latest PLUGINSHA256="$sha"
expect_reject 'latest with a malformed pluginSha256' "pluginSha256 must be empty when pluginVersion is 'latest'" PLUGINVERSION=latest PLUGINSHA256=nope
expect_reject 'an upper-case LATEST' 'pluginVersion must be' PLUGINVERSION=LATEST
expect_reject 'latest with a trailing space' 'pluginVersion must be' PLUGINVERSION='latest '
expect_reject "a 'v' prefix on latest" 'pluginVersion must be' PLUGINVERSION=vlatest
test ! -e "$tmp/pwned"
test ! -e pwned

# Valid options, including an empty courseRepo and a starter, pass validation and stop only
# at the missing bb Feature.
expect_reject 'defaults without the bb Feature' 'the bb Feature must be installed first'
expect_reject 'explicit options without the bb Feature' 'the bb Feature must be installed first' \
    COURSE=/workspaces/course/ COURSEREPO= FACTORY=/workspaces/my-factory SELECTOUTLINE=false DISABLEPLUGINS= THEME=
expect_reject 'the starter layout without the bb Feature' 'the bb Feature must be installed first' \
    STARTER=/workspaces/capstone-project-starter/ STARTERREPO=https://github.com/lean-software-production/capstone-project-starter.git \
    FACTORY=/workspaces/capstone-project-starter/tetris/.factory
expect_reject 'the starter as the project, with no factory, without the bb Feature' 'the bb Feature must be installed first' \
    STARTER=/workspaces/capstone-project-starter STARTERREPO= FACTORY=
expect_reject 'lightTheme off and BB icons without the bb Feature' 'the bb Feature must be installed first' \
    LIGHTTHEME=false APPICONS=bb
expect_reject 'lightTheme on and LSP icons without the bb Feature' 'the bb Feature must be installed first' \
    LIGHTTHEME=true APPICONS=lsp
expect_reject 'plugin list and theme without the bb Feature' 'the bb Feature must be installed first' \
    DISABLEPLUGINS=automations,tutor,provider-codex THEME=nord
expect_reject 'another plugin release without the bb Feature' 'the bb Feature must be installed first' \
    PLUGINVERSION=0.2.0-rc.1 PLUGINSHA256="$sha"
expect_reject 'the latest plugin release without the bb Feature' 'the bb Feature must be installed first' \
    PLUGINVERSION=latest PLUGINSHA256=
expect_reject 'the pinned plugin release, explicitly, without the bb Feature' 'the bb Feature must be installed first' \
    PLUGINVERSION="$(sed -n 's/^TUTOR_PLUGIN_PINNED_VERSION=//p' "$repo_root/src/tutor/plugin-pin.sh")" PLUGINSHA256=
echo 'tutor adversarial option validation passed'
