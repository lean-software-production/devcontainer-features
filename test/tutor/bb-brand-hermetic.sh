#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Tests src/tutor/bin/tutor-bb-brand.sh, the image-build patches to BB's web
# client (lightTheme and appIcons), against copies of real bb-app app/dist
# directories. Pass them as arguments:
#
#   bash test/tutor/bb-brand-hermetic.sh <bb-app>/app/dist ...
#
# or, with no arguments, it fetches the bb-app releases in BB_APP_VERSIONS
# (default: the one the scenarios pin and the next) with npm pack. The given
# directories are only ever read. Needs bash, node, od and cmp.
set -euo pipefail
shopt -s inherit_errexit

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
icons="$repo_root/src/tutor/icons"
# shellcheck source=../../src/tutor/bin/tutor-bb-brand.sh
. "$repo_root/src/tutor/bin/tutor-bb-brand.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
# A PATH with node but no bb or bb-app, so no call can find a real BB here.
mkdir -p "$tmp/nodebin"
ln -s "$(command -v node)" "$tmp/nodebin/node"
safe_path="$tmp/nodebin:/usr/bin:/bin"
for bin in bb bb-app; do PATH="$safe_path" command -v "$bin" >/dev/null && { echo "refusing to run: $bin is on /usr/bin or /bin" >&2; exit 1; }; done
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { passed=$((passed + 1)); echo "ok - $*"; }

dists=("$@")
if [ "${#dists[@]}" -eq 0 ]; then
    for version in ${BB_APP_VERSIONS:-0.43.4 0.44.0}; do
        mkdir -p "$tmp/npm/$version"
        tarball="$(cd "$tmp/npm/$version" && npm_config_cache="$tmp/npm-cache" npm pack --silent "bb-app@$version")"
        tar -C "$tmp/npm/$version" -xzf "$tmp/npm/$version/$tarball" package/package.json package/app/dist
        dists+=("$tmp/npm/$version/package/app/dist")
    done
fi

# A tree listing with every file's SHA-256, to prove a tree unchanged.
tree_digest() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum); }
# Runs the page's inline boot script(s) in node with a stored bb.theme and a
# prefers-color-scheme, then prints "<bb.theme after> <html has dark class>".
boot() {
    node - "$1" "$2" "$3" <<'JS'
const fs = require("fs"), vm = require("vm");
const [file, stored, scheme] = process.argv.slice(2);
const html = fs.readFileSync(file, "utf8");
const store = new Map(stored === "none" ? [] : [["bb.theme", stored]]);
const classes = new Set();
const el = () => ({ href: "", content: "" });
const nodes = {};
const ctx = {
  localStorage: { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)) },
  window: { matchMedia: () => ({ matches: scheme === "dark", addEventListener() {} }) },
  document: {
    getElementById: (id) => (nodes[id] ||= el()),
    documentElement: { classList: { add: (c) => classes.add(c) } },
    createElement: () => ({}), head: { appendChild() {} },
  },
};
// Only the head's boot script matters here; the body one needs a stored palette.
const script = /<script>([\s\S]*?)<\/script>/.exec(html)[1];
vm.runInNewContext(script, ctx);
process.stdout.write(`${store.get("bb.theme")} ${classes.has("dark")}`);
JS
}
# The icon targets tutor_bb_lsp_icons replaces, and the kind each maps to.
targets() { (cd "$1" && ls favicon-*.png apple-touch-icon*.png icon-*.png); }
kind_of() {
    case "$1" in *monochrome*) echo monochrome ;; *maskable*) echo maskable ;; apple-touch-icon*) echo touch ;; *) echo tile ;; esac
}

# The committed icons: one per kind and size, the size the file name says.
for icon in "$icons"/lsp-*.png; do
    want="${icon##*-}"; want="${want%.png}"
    [ "$(tutor_png_size "$icon")" = "$want $want" ] || fail "$icon is not ${want}x${want}"
done
ok "every committed LSP icon is the size its name says"
tutor_png_size "$repo_root/src/tutor/install.sh" >/dev/null 2>&1 && fail "tutor_png_size accepted a non-PNG"
ok "tutor_png_size rejects a non-PNG"

for source in "${dists[@]}"; do
    [ -f "$source/index.html" ] || fail "$source has no index.html"
    label="$(node -p 'require(process.argv[1]).version' "$source/../../package.json" 2>/dev/null || echo "$source")"
    before="$(tree_digest "$source")"
    work="$tmp/$label"
    rm -rf "$work" && mkdir -p "$work"

    # lightTheme: the patch, its effect, and idempotence.
    cp -a "$source" "$work/theme"
    d="$work/theme"
    [ -f "$d/index.html.br" ] && [ -f "$d/index.html.gz" ] || fail "$label: expected precompressed index.html siblings to start with"
    [ "$(boot "$d/index.html" dark dark)" = "dark true" ] || fail "$label: unpatched BB should boot dark from a stored dark"
    out="$(tutor_bb_pin_light_theme "$d" 2>&1)"
    grep -q "pinned BB's theme to Light" <<<"$out" || fail "$label: no confirmation: $out"
    [ "$(grep -cF "$TUTOR_BB_THEME_MARKER" "$d/index.html")" = 1 ] || fail "$label: marker not present once"
    first="$(node -e '
const html = require("fs").readFileSync(process.argv[1], "utf8");
const m = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].find((s) => s[1].includes("localStorage.getItem(\"bb.theme\")"));
process.stdout.write(m[1].trimStart().split("\n")[0]);' "$d/index.html")"
    [ "$first" = "$TUTOR_BB_THEME_MARKER try { localStorage.setItem(\"bb.theme\", \"light\"); } catch {}" ] \
        || fail "$label: the boot script does not start with the pin: $first"
    [ ! -e "$d/index.html.br" ] && [ ! -e "$d/index.html.gz" ] || fail "$label: precompressed index.html siblings remain"
    diff <(sed "/$(printf '%s' "$TUTOR_BB_THEME_MARKER" | sed 's/[*/]/\\&/g')/d" "$d/index.html") "$source/index.html" >/dev/null \
        || fail "$label: the patch changed more than the one inserted line"
    ok "$label: lightTheme pins bb.theme as the boot script's first statement and removes index.html.br/.gz"
    for case in "dark dark" "dark light" "system dark" "none dark" "light light"; do
        # shellcheck disable=SC2086 # two words on purpose
        [ "$(boot "$d/index.html" $case)" = "light false" ] || fail "$label: stored/scheme $case does not boot light"
    done
    ok "$label: whatever was stored and whatever the OS scheme, the boot script stores light and adds no dark class"
    digest="$(sha256sum < "$d/index.html")"
    out="$(tutor_bb_pin_light_theme "$d" 2>&1)"
    grep -q "already pinned" <<<"$out" || fail "$label: second run did not report already pinned: $out"
    [ "$(sha256sum < "$d/index.html")" = "$digest" ] || fail "$label: second run changed index.html"
    ok "$label: lightTheme is idempotent"

    # A BB whose boot script no longer reads bb.theme: warn, touch nothing.
    cp -a "$source" "$work/anchorless"
    d="$work/anchorless"
    sed -i 's/getItem("bb\.theme")/getItem("bb.colorMode")/' "$d/index.html"
    digest="$(tree_digest "$d")"
    out="$(tutor_bb_pin_light_theme "$d" 2>&1)" || fail "$label: a missing anchor failed the call"
    grep -q "warning: .*no inline script reading localStorage bb.theme" <<<"$out" || fail "$label: no warning for a missing anchor: $out"
    [ "$(tree_digest "$d")" = "$digest" ] || fail "$label: a missing anchor still changed app/dist"
    ok "$label: without the anchor, lightTheme warns and leaves app/dist (index.html, .br, .gz) untouched"

    # appIcons=lsp: every icon replaced by the LSP icon of its kind and size.
    cp -a "$source" "$work/icons"
    d="$work/icons"
    mapfile -t names < <(targets "$source")
    [ "${#names[@]}" -ge 50 ] || fail "$label: only ${#names[@]} icon targets found"
    out="$(tutor_bb_lsp_icons "$d" "$icons" 2>&1)"
    grep -q "replaced all ${#names[@]} BB icons" <<<"$out" || fail "$label: unexpected summary: $out"
    for name in "${names[@]}"; do
        size="$(tutor_png_size "$source/$name")"
        [ "$(tutor_png_size "$d/$name")" = "$size" ] || fail "$label: $name changed size"
        cmp -s "$d/$name" "$icons/lsp-$(kind_of "$name")-${size%% *}.png" || fail "$label: $name is not the LSP $(kind_of "$name") icon"
        cmp -s "$d/$name" "$source/$name" && fail "$label: $name is still BB's"
    done
    [ "$(stat -c %a "$d/favicon-32x32.png")" = "$(stat -c %a "$source/favicon-32x32.png")" ] || fail "$label: replacing changed a file mode"
    diff <(cd "$source" && find . -type f ! -name 'favicon-*.png' ! -name 'apple-touch-icon*.png' ! -name 'icon-*.png' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) \
         <(cd "$d" && find . -type f ! -name 'favicon-*.png' ! -name 'apple-touch-icon*.png' ! -name 'icon-*.png' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) >/dev/null \
        || fail "$label: appIcons changed a file that is not a BB icon"
    ok "$label: appIcons=lsp replaces all ${#names[@]} icons with the LSP icon of the same kind and size, and nothing else"
    digest="$(tree_digest "$d")"
    tutor_bb_lsp_icons "$d" "$icons" >/dev/null 2>&1
    [ "$(tree_digest "$d")" = "$digest" ] || fail "$label: a second icon pass changed app/dist"
    ok "$label: appIcons is idempotent"

    # A size or file the Feature has no LSP icon for keeps BB's, with a warning.
    cp -a "$source" "$work/newsize"
    d="$work/newsize"
    node -e '
const b = require("fs").readFileSync(process.argv[1]);
b.writeUInt32BE(48, 16); b.writeUInt32BE(48, 20);
require("fs").writeFileSync(process.argv[2], b);' "$source/icon-192.png" "$d/icon-48.png"
    printf 'not a png' > "$d/favicon-broken.png"
    cp "$d/icon-48.png" "$tmp/icon-48.png"
    out="$(tutor_bb_lsp_icons "$d" "$icons" 2>&1)" || fail "$label: an unknown icon size failed the call"
    grep -q "warning: no LSP tile icon of 48x48 for icon-48.png; kept BB's" <<<"$out" || fail "$label: no warning for an unknown size: $out"
    grep -q "warning: .*favicon-broken.png is not a PNG" <<<"$out" || fail "$label: no warning for a non-PNG: $out"
    grep -q "kept 2 of BB's" <<<"$out" || fail "$label: summary does not count the kept icons: $out"
    cmp -s "$d/icon-48.png" "$tmp/icon-48.png" || fail "$label: an icon with no LSP counterpart was changed"
    cmp -s "$d/favicon-32x32.png" "$icons/lsp-tile-32.png" || fail "$label: the known sizes were not replaced alongside"
    ok "$label: an icon with no LSP counterpart keeps BB's, with a warning"

    # tutor_bb_brand, as install.sh calls it, against a fake npm prefix whose
    # bin/bb-app links into the package, like npm's global install.
    for combo in "false bb" "true bb" "false lsp" "true lsp"; do
        read -r light appicons <<<"$combo"
        prefix="$work/prefix-$light-$appicons"
        mkdir -p "$prefix/lib/node_modules/bb-app/app" "$prefix/lib/node_modules/bb-app/dist" "$prefix/bin"
        cp -a "$source" "$prefix/lib/node_modules/bb-app/app/dist"
        printf '{"name":"bb-app","version":"%s"}\n' "$label" > "$prefix/lib/node_modules/bb-app/package.json"
        printf '#!/bin/sh\n' > "$prefix/lib/node_modules/bb-app/dist/bb-app.js"
        ln -s ../lib/node_modules/bb-app/dist/bb-app.js "$prefix/bin/bb-app"
        d="$prefix/lib/node_modules/bb-app/app/dist"
        out="$(BB_FEATURE_APP_BIN="$prefix/bin/bb-app" TUTOR_BB_NPM_PREFIX=/nonexistent PATH="$safe_path" tutor_bb_brand "$light" "$appicons" "$icons" 2>&1)" \
            || fail "$label: tutor_bb_brand $combo failed"
        if [ "$light" = true ]; then grep -qF "$TUTOR_BB_THEME_MARKER" "$d/index.html" || fail "$label: $combo did not pin the theme"
        else cmp -s "$d/index.html" "$source/index.html" && [ -f "$d/index.html.br" ] || fail "$label: $combo touched index.html"; fi
        if [ "$appicons" = lsp ]; then cmp -s "$d/favicon-16x16.png" "$icons/lsp-tile-16.png" || fail "$label: $combo did not replace the icons"
        else for name in "${names[@]}"; do cmp -s "$d/$name" "$source/$name" || fail "$label: $combo touched $name"; done; fi
        if [ "$combo" = "false bb" ]; then
            [ "$(tree_digest "$d")" = "$before" ] || fail "$label: lightTheme=false appIcons=bb changed app/dist"
            [ -z "$out" ] || fail "$label: lightTheme=false appIcons=bb printed: $out"
        fi
    done
    ok "$label: tutor_bb_brand finds bb-app through its launcher; lightTheme=false and appIcons=bb each leave their files untouched"
    out="$(TUTOR_BB_NPM_PREFIX="$work/prefix-true-lsp" BB_FEATURE_APP_BIN= PATH="$safe_path" tutor_bb_brand true lsp "$icons" 2>&1)" || fail "$label: fallback prefix failed"
    grep -q "already pinned" <<<"$out" || fail "$label: the default npm prefix was not used as a fallback: $out"
    ok "$label: tutor_bb_brand falls back to the bb Feature's npm prefix"

    [ "$(tree_digest "$source")" = "$before" ] || fail "$label: the source directory changed"
done

# No bb-app anywhere: a warning, never a failure.
out="$(BB_FEATURE_APP_BIN= TUTOR_BB_NPM_PREFIX="$tmp/none" PATH="$safe_path" tutor_bb_brand true lsp "$icons" 2>&1)" || fail "a missing bb-app failed the call"
grep -q "warning: could not find bb-app's web client" <<<"$out" || fail "no warning for a missing bb-app: $out"
out="$(tutor_bb_pin_light_theme "$tmp/none" 2>&1)" || fail "a missing app/dist failed the theme pin"
grep -q warning <<<"$out" || fail "no warning for a missing app/dist"
out="$(tutor_bb_lsp_icons "$tmp/none" "$icons" 2>&1)" || fail "a missing app/dist failed the icons"
grep -q warning <<<"$out" || fail "no warning for a missing app/dist"
ok "without bb-app or its app/dist, every step warns and succeeds"

echo "tutor bb-brand hermetic tests passed ($passed checks, ${#dists[@]} bb-app builds)"
