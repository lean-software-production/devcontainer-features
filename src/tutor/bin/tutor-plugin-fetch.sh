# shellcheck shell=bash
# Downloads a bb-plugin-tutor release, verifies it against a SHA-256 the caller
# pins (or, for the latest release, the release's own .sha256), and stages its
# sources. Sourced by install.sh, and by
# test/tutor/plugin-fetch-hermetic.sh, which serves local tarballs through a
# fake curl. Every function returns non-zero with a message on stderr; none of
# them exits, and none depends on the caller's set -e or pipefail.
#
# The release contract (lean-software-production/bb-plugin-tutor): for version
# <v>, releases/download/v<v>/bb-plugin-tutor-<v>.tgz is a gzip tar with one
# top-level directory bb-plugin-tutor-<v>/, holding package.json (name
# bb-plugin-tutor, version <v>), package-lock.json and the plugin sources, and
# no dist/ or node_modules. Beside it, bb-plugin-tutor-<v>.tgz.sha256 holds one
# sha256sum line: "<64 lower-case hex>  bb-plugin-tutor-<v>.tgz".
#
# That .sha256 file is never trusted for a pinned or explicit version: the
# caller's SHA-256 is the check. For the latest release there is no pin, so it
# is the only check available; it guards against a corrupted or truncated
# download, not against a compromised release, whose publisher could replace
# the tarball and its .sha256 together.

TUTOR_PLUGIN_RELEASES=https://github.com/lean-software-production/bb-plugin-tutor/releases/download
# GitHub redirects this to releases/tag/v<newest version>, without the rate
# limits of its API; with no release yet it redirects to releases/ instead.
TUTOR_PLUGIN_LATEST=https://github.com/lean-software-production/bb-plugin-tutor/releases/latest
TUTOR_PLUGIN_TAGS=https://github.com/lean-software-production/bb-plugin-tutor/releases/tag
TUTOR_PLUGIN_NAME=bb-plugin-tutor

tutor_plugin_error() { echo "ERROR: tutor plugin fetch: $*" >&2; }

# A plain semantic version: MAJOR.MINOR.PATCH plus an optional dot-separated
# pre-release, with no 'v' prefix, range, build metadata or other characters.
tutor_plugin_valid_version() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]
}
tutor_plugin_valid_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

# <top> <path>: a member path is <top> itself or lies beneath <top>/, and has
# no empty, "." or ".." segment (so it is never absolute).
tutor_plugin_member_path_ok() {
    local top="$1" path="$2" segment
    local -a segments
    [ "$path" = "$top" ] && return 0
    [[ "$path" == "$top"/?* ]] || return 1
    IFS=/ read -r -a segments <<<"$path"
    for segment in "${segments[@]}"; do
        case "$segment" in ''|.|..) return 1 ;; esac
    done
    # read drops one trailing empty field, so "a/b/" needs its own check.
    [[ "$path" != */ ]]
}

# <target>: a symlink target that can only point downwards from the link's own
# directory: relative, with no ".." segment. Every link in the tree then points
# into the tree, however links chain, so nothing extracted can point outside.
tutor_plugin_symlink_target_ok() {
    local target="$1" segment
    local -a segments
    [ -n "$target" ] && [[ "$target" != /* ]] || return 1
    IFS=/ read -r -a segments <<<"$target"
    for segment in "${segments[@]}"; do
        [ "$segment" != .. ] || return 1
    done
}

# <tarball> <top>: lists the archive without extracting it and rejects any
# member that is absolute, has a ".." segment, lies outside <top>/, is a
# symlink pointing anywhere but down the tree, is a hard link to a path outside
# <top>/, is not a plain file, directory or link, or has a name that GNU tar has
# to escape (control characters, quotes or backslashes).
tutor_plugin_check_members() {
    local tarball="$1" top="$2" listing line type quoted name target count=0
    local re_plain='^"([^"\\]*)"$' re_symlink='^"([^"\\]*)" -> "([^"\\]*)"$' re_hardlink='^"([^"\\]*)" link to "([^"\\]*)"$'
    tar --version 2>/dev/null | grep -q 'GNU tar' || { tutor_plugin_error "GNU tar is required to inspect the release tarball."; return 1; }
    # -P lists names exactly as stored; C quoting makes every odd character a
    # backslash escape, and the patterns above refuse any backslash.
    listing="$(LC_ALL=C tar -P --list --verbose --numeric-owner --quoting-style=c -zf "$tarball")" \
        || { tutor_plugin_error "cannot list $tarball; it is not a gzip tar archive."; return 1; }
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        count=$((count + 1))
        type="${line:0:1}"
        [[ "$line" == *\"* ]] || { tutor_plugin_error "cannot read the tar listing line: $line"; return 1; }
        quoted="\"${line#*\"}"
        target=
        case "$type" in
            -|d) [[ "$quoted" =~ $re_plain ]] || { tutor_plugin_error "member with an unusual name: $quoted"; return 1; }
                 name="${BASH_REMATCH[1]}" ;;
            l)   [[ "$quoted" =~ $re_symlink ]] || { tutor_plugin_error "symlink with an unusual name or target: $quoted"; return 1; }
                 name="${BASH_REMATCH[1]}" target="${BASH_REMATCH[2]}" ;;
            h)   [[ "$quoted" =~ $re_hardlink ]] || { tutor_plugin_error "hard link with an unusual name or target: $quoted"; return 1; }
                 name="${BASH_REMATCH[1]}" target="${BASH_REMATCH[2]}" ;;
            *)   tutor_plugin_error "member is not a plain file, directory or link: $quoted"; return 1 ;;
        esac
        [ "$type" != d ] || name="${name%/}"
        [[ "$name" != /* ]] || { tutor_plugin_error "absolute member path: $name"; return 1; }
        tutor_plugin_member_path_ok "$top" "$name" \
            || { tutor_plugin_error "member '$name' is outside $top/ or has an empty, '.' or '..' segment."; return 1; }
        case "$type" in
            l) tutor_plugin_symlink_target_ok "$target" \
                   || { tutor_plugin_error "symlink '$name' -> '$target' may point outside $top/; only relative links without '..' are accepted."; return 1; } ;;
            h) if [ "$target" = "$top" ] || ! tutor_plugin_member_path_ok "$top" "$target"; then
                   tutor_plugin_error "hard link '$name' -> '$target' points outside $top/."; return 1
               fi ;;
        esac
    done <<<"$listing"
    [ "$count" -gt 0 ] || { tutor_plugin_error "$tarball is empty."; return 1; }
}

# <version> <sha256> <workdir> <dest>: downloads bb-plugin-tutor-<version>.tgz
# into <workdir>, verifies its SHA-256 before anything reads the archive,
# checks every member, extracts it, checks package.json and package-lock.json,
# and copies the sources into <dest>, which must be an empty directory.
tutor_plugin_fetch() {
    local version="$1" sha="$2" work="$3" dest="$4"
    tutor_plugin_valid_version "$version" || { tutor_plugin_error "'$version' is not a plain semantic version."; return 1; }
    tutor_plugin_valid_sha256 "$sha" || { tutor_plugin_error "the expected SHA-256 must be 64 lower-case hex digits."; return 1; }
    [ -d "$work" ] || { tutor_plugin_error "the work directory $work does not exist."; return 1; }
    [ -d "$dest" ] && [ -z "$(ls -A "$dest")" ] || { tutor_plugin_error "the destination $dest must be an empty directory."; return 1; }
    local top="$TUTOR_PLUGIN_NAME-$version"
    local url="$TUTOR_PLUGIN_RELEASES/v$version/$top.tgz" tarball="$work/$top.tgz" extract="$work/plugin-extract"
    local actual rc
    [ ! -e "$tarball" ] && [ ! -e "$extract" ] || { tutor_plugin_error "$work already holds a download or an extraction."; return 1; }

    command -v curl >/dev/null 2>&1 \
        || { tutor_plugin_error "curl is required to download the Tutor plugin; add it to the base image (the javascript-node images include it)."; return 1; }
    echo "tutor plugin fetch: downloading $url"
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --retry 5 --retry-delay 2 \
        -o "$tarball" "$url" \
        || { rc=$?; tutor_plugin_error "could not download $url (curl exit $rc). The image build needs network access to github.com."; return 1; }

    actual="$(sha256sum "$tarball")" || { tutor_plugin_error "cannot hash $tarball."; return 1; }
    actual="${actual%% *}"
    [ "$actual" = "$sha" ] \
        || { tutor_plugin_error "SHA-256 mismatch for $top.tgz: expected $sha, downloaded $actual. Nothing was extracted."; return 1; }

    tutor_plugin_check_members "$tarball" "$top" || { tutor_plugin_error "refusing to extract $top.tgz."; return 1; }
    mkdir "$extract" || return 1
    tar -xzf "$tarball" -C "$extract" --no-same-owner --no-same-permissions \
        || { tutor_plugin_error "cannot extract $top.tgz."; return 1; }
    local src="$extract/$top"
    [ -d "$src" ] && [ ! -L "$src" ] || { tutor_plugin_error "$top.tgz has no $top/ directory."; return 1; }
    [ ! -e "$src/node_modules" ] && [ ! -e "$src/dist" ] \
        || { tutor_plugin_error "$top.tgz carries node_modules or dist; a release holds only sources."; return 1; }
    [ -f "$src/package-lock.json" ] || { tutor_plugin_error "$top.tgz has no package-lock.json."; return 1; }
    [ -f "$src/package.json" ] || { tutor_plugin_error "$top.tgz has no package.json."; return 1; }
    # shellcheck disable=SC2016 # JavaScript template literals
    node -e '
const [file, name, version] = process.argv.slice(1);
let p;
try { p = JSON.parse(require("fs").readFileSync(file, "utf8")); } catch (e) { console.error(`package.json is not valid JSON: ${e.message}`); process.exit(1); }
if (!p || p.name !== name || p.version !== version) {
  console.error(`package.json names ${JSON.stringify(p && p.name)} ${JSON.stringify(p && p.version)}, expected ${JSON.stringify(name)} ${JSON.stringify(version)}.`);
  process.exit(1);
}' "$src/package.json" "$TUTOR_PLUGIN_NAME" "$version" \
        || { tutor_plugin_error "$top.tgz is not $TUTOR_PLUGIN_NAME $version."; return 1; }

    cp -a "$src/." "$dest/" || { tutor_plugin_error "cannot copy the plugin into $dest."; return 1; }
    echo "tutor plugin fetch: verified $top.tgz (sha256 $sha)"
}

# Sets TUTOR_PLUGIN_LATEST_VERSION to the newest release's version, read from
# the URL that TUTOR_PLUGIN_LATEST redirects to (https only, like every other
# request here), which must be TUTOR_PLUGIN_TAGS/v<plain semantic version>.
tutor_plugin_resolve_latest() {
    local landed version rc
    TUTOR_PLUGIN_LATEST_VERSION=
    command -v curl >/dev/null 2>&1 \
        || { tutor_plugin_error "curl is required to download the Tutor plugin; add it to the base image (the javascript-node images include it)."; return 1; }
    landed="$(curl -fsSIL --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --retry 5 --retry-delay 2 \
        -o /dev/null -w '%{url_effective}' "$TUTOR_PLUGIN_LATEST")" \
        || { rc=$?; tutor_plugin_error "could not resolve the latest release from $TUTOR_PLUGIN_LATEST (curl exit $rc). The image build needs network access to github.com."; return 1; }
    version="${landed#"$TUTOR_PLUGIN_TAGS/v"}"
    if [ "$version" = "$landed" ] || ! tutor_plugin_valid_version "$version"; then
        tutor_plugin_error "$TUTOR_PLUGIN_LATEST led to '$landed', which is not a bb-plugin-tutor release tag ($TUTOR_PLUGIN_TAGS/v<MAJOR.MINOR.PATCH>). Has a release been published?"
        return 1
    fi
    TUTOR_PLUGIN_LATEST_VERSION="$version"
    echo "tutor plugin fetch: latest is $version"
}

# <version> <workdir>: sets TUTOR_PLUGIN_RELEASE_SHA256 from the release's own
# bb-plugin-tutor-<version>.tgz.sha256, downloaded into <workdir>. The file must
# hold exactly one sha256sum line for that tarball (text or binary mode).
tutor_plugin_release_sha256() {
    local version="$1" work="$2" line rc
    local top="$TUTOR_PLUGIN_NAME-$version"
    local url="$TUTOR_PLUGIN_RELEASES/v$version/$top.tgz.sha256" file="$work/$top.tgz.sha256"
    local -a lines
    TUTOR_PLUGIN_RELEASE_SHA256=
    tutor_plugin_valid_version "$version" || { tutor_plugin_error "'$version' is not a plain semantic version."; return 1; }
    [ -d "$work" ] || { tutor_plugin_error "the work directory $work does not exist."; return 1; }
    [ ! -e "$file" ] || { tutor_plugin_error "$work already holds $top.tgz.sha256."; return 1; }
    echo "tutor plugin fetch: downloading $url"
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --retry 5 --retry-delay 2 \
        --max-filesize 4096 -o "$file" "$url" \
        || { rc=$?; tutor_plugin_error "could not download $url (curl exit $rc)."; return 1; }
    mapfile -t lines <"$file" || { tutor_plugin_error "cannot read $file."; return 1; }
    line="${lines[0]-}"
    if [ "${#lines[@]}" -ne 1 ] || ! tutor_plugin_valid_sha256 "${line:0:64}" \
        || { [ "${line:64}" != "  $top.tgz" ] && [ "${line:64}" != " *$top.tgz" ]; }; then
        tutor_plugin_error "$top.tgz.sha256 must hold exactly one line: 64 lower-case hex digits, two spaces and $top.tgz. The tarball was not downloaded."
        return 1
    fi
    TUTOR_PLUGIN_RELEASE_SHA256="${line:0:64}"
}

# <workdir> <dest>: resolves the newest release and installs it as
# tutor_plugin_fetch does, verified against that release's own .sha256 (see
# the top of this file for what that does and does not protect against). Sets
# TUTOR_PLUGIN_LATEST_VERSION and TUTOR_PLUGIN_LATEST_SHA256 for the caller.
tutor_plugin_fetch_latest() {
    local work="$1" dest="$2"
    TUTOR_PLUGIN_LATEST_SHA256=
    tutor_plugin_resolve_latest || return 1
    tutor_plugin_release_sha256 "$TUTOR_PLUGIN_LATEST_VERSION" "$work" || return 1
    tutor_plugin_fetch "$TUTOR_PLUGIN_LATEST_VERSION" "$TUTOR_PLUGIN_RELEASE_SHA256" "$work" "$dest" || return 1
    # shellcheck disable=SC2034 # read by install.sh
    TUTOR_PLUGIN_LATEST_SHA256="$TUTOR_PLUGIN_RELEASE_SHA256"
}
