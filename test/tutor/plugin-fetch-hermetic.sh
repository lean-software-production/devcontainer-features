#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Hermetic test of src/tutor/bin/tutor-plugin-fetch.sh: no network. A fake curl
# on PATH serves tarballs built here, standing in for the bb-plugin-tutor
# GitHub releases. Needs bash, GNU tar, node and python3 (to craft the
# malicious archives GNU tar would refuse to create).
set -euo pipefail
shopt -s inherit_errexit

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/src/tutor/bin/tutor-plugin-fetch.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
serve="$tmp/serve"
mkdir -p "$tmp/bin" "$serve"
releases=https://github.com/lean-software-production/bb-plugin-tutor/releases/download

# The fake curl records its arguments and serves $serve/<tag>/<file> for a
# release URL; anything else, or a missing file, fails as curl -f does.
cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/curl.log"
out= url=
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o) out="\$2"; shift 2 ;;
        -*) case "\$1" in --proto|--proto-redir|--connect-timeout|--retry|--retry-delay) shift ;; esac; shift ;;
        *) url="\$1"; shift ;;
    esac
done
case "\$url" in
    $releases/*) file="$serve/\${url#"$releases/"}" ;;
    *) echo "fake curl: unexpected URL \$url" >&2; exit 1 ;;
esac
[ -f "\$file" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cp "\$file" "\$out"
EOF
chmod 755 "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

# craft <out.tgz> <entry>...: each entry is file:<name>[:<content>],
# dir:<name>, symlink:<name>:<target> or hardlink:<name>:<target>.
craft() {
    python3 - "$@" <<'PY'
import io, sys, tarfile
out, entries = sys.argv[1], sys.argv[2:]
with tarfile.open(out, "w:gz", format=tarfile.PAX_FORMAT) as tar:
    for entry in entries:
        kind, name, *rest = entry.split(":", 2)
        info = tarfile.TarInfo(name)
        info.mtime = 0
        if kind == "file":
            data = (rest[0] if rest else "x").encode()
            info.size, info.mode = len(data), 0o644
            tar.addfile(info, io.BytesIO(data))
            continue
        info.type = {"dir": tarfile.DIRTYPE, "symlink": tarfile.SYMTYPE, "hardlink": tarfile.LNKTYPE}[kind]
        info.mode = 0o755 if kind == "dir" else 0o777
        if rest:
            info.linkname = rest[0]
        tar.addfile(info)
PY
}
package_json() { printf '{"name":"%s","version":"%s","private":true}' "$1" "$2"; }
# A well-formed release of <version>, plus any extra entries.
good_entries() {
    local top="bb-plugin-tutor-$1"
    printf '%s\n' "dir:$top" "file:$top/package.json:$(package_json bb-plugin-tutor "$1")" \
        "file:$top/package-lock.json:{}" "file:$top/server.ts:export {}" "dir:$top/server" \
        "file:$top/server/coach.ts:export {}" "symlink:$top/server/index.ts:coach.ts"
}
# publish <version> <entry>...: serves a tarball as release v<version>; prints its SHA-256.
publish() {
    local version="$1"; shift
    mkdir -p "$serve/v$version"
    craft "$serve/v$version/bb-plugin-tutor-$version.tgz" "$@"
    sha256sum "$serve/v$version/bb-plugin-tutor-$version.tgz" | cut -d' ' -f1
}
# publish_bad <version> <extra entry>...: a good release of <version> plus the extras.
publish_bad() {
    local version="$1" entries
    shift
    mapfile -t entries < <(good_entries "$version")
    publish "$version" "${entries[@]}" "$@"
}

failures=0
case_dir=
# fetch <version> <sha256>: runs the helper in a fresh work and destination
# directory ($case_dir/work, $case_dir/dest); output in $case_dir/out.
fetch() {
    case_dir="$(mktemp -d "$tmp/case.XXXXXX")"
    mkdir "$case_dir/work" "$case_dir/dest"
    # A clean shell with install.sh's shell options, calling it as install.sh does.
    bash -c 'set -euo pipefail; . "$1"; tutor_plugin_fetch "$2" "$3" "$4/work" "$4/dest" || exit 1' \
        _ "$helper" "$1" "$2" "$case_dir" >"$case_dir/out" 2>&1
}
pass() { echo "ok   $1"; }
flunk() { echo "FAIL $1" >&2; sed 's/^/     | /' "$case_dir/out" >&2; failures=$((failures + 1)); }
# expect_reject <label> <message> <version> <sha256>: fails with <message> and
# installs nothing.
expect_reject() {
    local label="$1" message="$2"
    if fetch "$3" "$4"; then flunk "$label (was accepted)"; return; fi
    grep -qF -- "$message" "$case_dir/out" || { flunk "$label (rejected for the wrong reason)"; return; }
    [ -z "$(ls -A "$case_dir/dest")" ] || { flunk "$label (left files in the destination)"; return; }
    pass "$label"
}
# nothing_extracted: the work directory holds at most the downloaded tarball.
nothing_extracted() { [ -z "$(find "$case_dir/work" -mindepth 1 ! -name '*.tgz' -print -quit)" ]; }

# The pin and devcontainer-feature.json's pluginVersion default agree.
# shellcheck source=../../src/tutor/plugin-pin.sh
. "$repo_root/src/tutor/plugin-pin.sh"
json_default="$(node -e 'const o = require(process.argv[1]).options.pluginVersion; process.stdout.write(o ? String(o.default) : "(no pluginVersion option)")' "$repo_root/src/tutor/devcontainer-feature.json")"
case_dir="$tmp" && : > "$tmp/out"
if [ "$json_default" = "$TUTOR_PLUGIN_PINNED_VERSION" ]; then pass "the pluginVersion default is the pinned version ($json_default)"
else echo "pluginVersion default $json_default, pin $TUTOR_PLUGIN_PINNED_VERSION" > "$tmp/out"; flunk "the pluginVersion default is the pinned version"; fi
# shellcheck source=../../src/tutor/bin/tutor-plugin-fetch.sh
. "$helper"
if tutor_plugin_valid_sha256 "$TUTOR_PLUGIN_PINNED_SHA256"; then pass "the pinned SHA-256 is well-formed"
else echo "note: the pinned SHA-256 is still a placeholder ($TUTOR_PLUGIN_PINNED_SHA256); set it in src/tutor/plugin-pin.sh after the v$TUTOR_PLUGIN_PINNED_VERSION release"; fi

# A good release passes and stages the expected files.
mapfile -t good < <(good_entries 0.1.0)
good_sha="$(publish 0.1.0 "${good[@]}")"
if fetch 0.1.0 "$good_sha" \
    && [ -f "$case_dir/dest/package.json" ] && [ -f "$case_dir/dest/package-lock.json" ] \
    && [ "$(cat "$case_dir/dest/server/coach.ts")" = "export {}" ] \
    && [ "$(readlink "$case_dir/dest/server/index.ts")" = coach.ts ] \
    && [ "$(cd "$case_dir/dest" && find . | LC_ALL=C sort | tr '\n' ' ')" = ". ./package-lock.json ./package.json ./server ./server.ts ./server/coach.ts ./server/index.ts " ] \
    && [ "$(tail -n1 "$tmp/curl.log")" = "-fsSL --proto =https --proto-redir =https --tlsv1.2 --connect-timeout 30 --retry 5 --retry-delay 2 -o $case_dir/work/bb-plugin-tutor-0.1.0.tgz $releases/v0.1.0/bb-plugin-tutor-0.1.0.tgz" ]; then
    pass "a good release is verified and staged, over https only"
else
    flunk "a good release is verified and staged, over https only"
fi

# A wrong SHA-256 fails before anything reads the archive: the same good
# tarball, so only the checksum can stop it.
wrong_sha="$(printf '%064d' 0)"
expect_reject "a wrong SHA-256 is refused" "SHA-256 mismatch" 0.1.0 "$wrong_sha"
if nothing_extracted; then pass "a wrong SHA-256 extracts nothing"; else flunk "a wrong SHA-256 extracts nothing"; fi

# Each malicious release is published under its own version with its true
# SHA-256 pinned, so the member checks are what must refuse it.
mapfile -t moved < <(good_entries 0.2.0 | sed 's#^\([a-z]*\):bb-plugin-tutor-0.2.0#\1:package#')
sha="$(publish 0.2.0 "${moved[@]}")"
expect_reject "a wrong top-level directory is refused" "is outside bb-plugin-tutor-0.2.0/" 0.2.0 "$sha"
sha="$(publish_bad 0.3.0 "file:bb-plugin-tutor-0.3.0/../evil")"
expect_reject "a '..' member is refused" "or has an empty, '.' or '..' segment" 0.3.0 "$sha"
sha="$(publish_bad 0.4.0 "file:/tmp/evil")"
expect_reject "an absolute member is refused" "absolute member path" 0.4.0 "$sha"
sha="$(publish_bad 0.5.0 "symlink:bb-plugin-tutor-0.5.0/evil:../../../etc/passwd")"
expect_reject "a symlink escaping the tree is refused" "may point outside" 0.5.0 "$sha"
sha="$(publish_bad 0.5.1 "symlink:bb-plugin-tutor-0.5.1/evil:/etc/passwd")"
expect_reject "an absolute symlink is refused" "may point outside" 0.5.1 "$sha"
sha="$(publish_bad 0.5.2 "hardlink:bb-plugin-tutor-0.5.2/evil:etc/passwd")"
expect_reject "a hard link outside the tree is refused" "points outside" 0.5.2 "$sha"
sha="$(publish_bad 0.5.3 "file:bb-plugin-tutor-0.5.3/odd\"name")"
expect_reject "a member name tar must escape is refused" "unusual name" 0.5.3 "$sha"
top=bb-plugin-tutor-0.6.0
sha="$(publish 0.6.0 "dir:$top" "file:$top/package.json:$(package_json bb-plugin-tutor 0.6.1)" "file:$top/package-lock.json:{}")"
expect_reject "a package.json version mismatch is refused" 'package.json names "bb-plugin-tutor" "0.6.1", expected "bb-plugin-tutor" "0.6.0".' 0.6.0 "$sha"
top=bb-plugin-tutor-0.7.0
sha="$(publish 0.7.0 "dir:$top" "file:$top/package.json:$(package_json some-other-plugin 0.7.0)" "file:$top/package-lock.json:{}")"
expect_reject "a wrong package name is refused" 'package.json names "some-other-plugin"' 0.7.0 "$sha"
top=bb-plugin-tutor-0.8.0
sha="$(publish 0.8.0 "dir:$top" "file:$top/package.json:$(package_json bb-plugin-tutor 0.8.0)")"
expect_reject "a release without package-lock.json is refused" "has no package-lock.json" 0.8.0 "$sha"
top=bb-plugin-tutor-0.8.1
sha="$(publish 0.8.1 "dir:$top" "file:$top/package.json:$(package_json bb-plugin-tutor 0.8.1)" "file:$top/package-lock.json:{}" "file:$top/dist/app.js")"
expect_reject "a release carrying dist/ is refused" "carries node_modules or dist" 0.8.1 "$sha"
expect_reject "a download failure is reported" "could not download $releases/v0.9.0/bb-plugin-tutor-0.9.0.tgz (curl exit 22)" 0.9.0 "$good_sha"
if nothing_extracted; then pass "a download failure extracts nothing"; else flunk "a download failure extracts nothing"; fi
expect_reject "a version with a 'v' prefix is refused" "is not a plain semantic version" v0.1.0 "$good_sha"
expect_reject "an upper-case SHA-256 is refused" "64 lower-case hex digits" 0.1.0 "$(tr a-f A-F <<<"$good_sha")"

[ "$failures" = 0 ] || { echo "$failures tutor plugin fetch check(s) failed" >&2; exit 1; }
echo 'tutor plugin fetch hermetic checks passed'
