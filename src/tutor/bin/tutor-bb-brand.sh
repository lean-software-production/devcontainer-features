# shellcheck shell=bash
# Sourced by install.sh (as root, at image build): patches the installed
# bb-app's web client, app/dist. Nothing here ever fails the build: a bb-app
# that is missing, or laid out differently from the one these patches were
# written against, gets a warning and is left as it is.
#
#   tutor_bb_brand LIGHT ICONS DIR  what install.sh runs: lightTheme (true |
#                                 false) and appIcons (lsp | bb), with the LSP
#                                 PNGs in DIR
#   tutor_bb_app_dir              the installed bb-app package directory
#   tutor_bb_pin_light_theme DIST pin Settings > Appearance > Theme to Light
#   tutor_bb_lsp_icons DIST ICONS replace BB's icon PNGs with the LSP ones
#   tutor_png_size FILE           "<width> <height>" from a PNG's IHDR

tutor_bb_warn() { echo "tutor Feature: warning: $*" >&2; }

# Finds the bb-app package directory: first by following the bb Feature's
# launcher (BB_FEATURE_APP_BIN) or bb-app/bb on PATH to its real file and
# walking up to the package.json named bb-app, then the bb Feature's default
# npm prefix. Prints it, or returns 1.
tutor_bb_app_dir() {
    local bin dir
    for bin in "${BB_FEATURE_APP_BIN:-}" "$(command -v bb-app 2>/dev/null || true)" "$(command -v bb 2>/dev/null || true)"; do
        [ -n "$bin" ] && [ -e "$bin" ] || continue
        dir="$(readlink -f -- "$bin")" || continue
        while dir="$(dirname -- "$dir")" && [ "$dir" != / ]; do
            if [ -f "$dir/package.json" ] && node -e 'process.exit(require(process.argv[1]).name === "bb-app" ? 0 : 1)' "$dir/package.json" 2>/dev/null; then
                printf '%s\n' "$dir"
                return 0
            fi
        done
    done
    dir="${TUTOR_BB_NPM_PREFIX:-/usr/local/share/bb/npm}/lib/node_modules/bb-app"
    [ -f "$dir/package.json" ] || return 1
    printf '%s\n' "$dir"
}

# BB keeps its Appearance theme (light | dark | system) only in the browser's
# localStorage, under bb.theme, so it is pinned where every page load starts:
# the first statement of index.html's inline boot script, the one that reads
# bb.theme to pre-apply the dark class before the app bundle (which reads the
# same key) loads. The precompressed index.html.br/.gz are removed so that
# BB's server serves the patched file.
TUTOR_BB_THEME_MARKER='/* tutor-feature: lightTheme */'
tutor_bb_pin_light_theme() {
    local dist="$1" index="$1/index.html" status=0
    [ -f "$index" ] || { tutor_bb_warn "BB's web client has no $index; Settings > Appearance > Theme is not pinned to Light."; return 0; }
    node - "$index" "$TUTOR_BB_THEME_MARKER" <<'JS' || status=$?
const fs = require("fs");
const [file, marker] = process.argv.slice(2);
const html = fs.readFileSync(file, "utf8");
if (html.includes(marker)) process.exit(3);
// Inline scripts only (no src attribute); the one that reads bb.theme.
const scripts = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
let m;
while ((m = scripts.exec(html))) {
  if (/\bsrc\s*=/i.test(m[1])) continue;
  if (!/localStorage\.getItem\(\s*["']bb\.theme["']\s*\)/.test(m[2])) continue;
  const at = m.index + m[0].indexOf(">") + 1;
  const pin = `\n      ${marker} try { localStorage.setItem("bb.theme", "light"); } catch {}`;
  fs.writeFileSync(file, html.slice(0, at) + pin + html.slice(at));
  process.exit(0);
}
process.exit(4);
JS
    case "$status" in
        0) echo "tutor Feature: pinned BB's theme to Light in $index." ;;
        3) echo "tutor Feature: BB's theme is already pinned to Light in $index." ;;
        4) tutor_bb_warn "$index has no inline script reading localStorage bb.theme (this BB changed its boot script), so Settings > Appearance > Theme is not pinned to Light; $index is unchanged."
           return 0 ;;
        *) tutor_bb_warn "could not patch $index (node exited $status); Settings > Appearance > Theme is not pinned to Light."
           return 0 ;;
    esac
    rm -f -- "$index.br" "$index.gz"
}

# Prints "<width> <height>" of a PNG, read from its IHDR chunk with od; returns
# 1 for anything that is not a PNG.
tutor_png_size() {
    local -a b
    # shellcheck disable=SC2207 # od prints plain numbers
    b=($(od -An -v -tu1 -N24 -- "$1" 2>/dev/null)) || return 1
    [ "${#b[@]}" -eq 24 ] || return 1
    [ "${b[*]:0:8}" = "137 80 78 71 13 10 26 10" ] && [ "${b[*]:12:4}" = "73 72 68 82" ] || return 1
    printf '%d %d\n' $(( (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19] )) \
        $(( (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23] ))
}

# Replaces every favicon-*.png, apple-touch-icon*.png and icon-*.png in DIST
# with ICONS/lsp-<kind>-<size>.png of the same size, where kind is monochrome,
# maskable, touch (apple-touch-icon) or tile (the rest). A file with no LSP
# icon of its kind and size keeps BB's, with a warning.
tutor_bb_lsp_icons() {
    local dist="$1" icons="$2" file name size width height kind source replaced=0 kept=0
    [ -d "$dist" ] || { tutor_bb_warn "BB's web client has no $dist; its icons are unchanged."; return 0; }
    for file in "$dist"/favicon-*.png "$dist"/apple-touch-icon*.png "$dist"/icon-*.png; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        name="${file##*/}"
        if ! size="$(tutor_png_size "$file")"; then
            tutor_bb_warn "$file is not a PNG; kept BB's."
            kept=$((kept + 1)); continue
        fi
        read -r width height <<< "$size"
        case "$name" in
            *monochrome*) kind=monochrome ;;
            *maskable*) kind=maskable ;;
            apple-touch-icon*) kind=touch ;;
            *) kind=tile ;;
        esac
        source="$icons/lsp-$kind-$width.png"
        if [ "$width" != "$height" ] || [ ! -f "$source" ]; then
            tutor_bb_warn "no LSP $kind icon of ${width}x${height} for $name; kept BB's."
            kept=$((kept + 1)); continue
        fi
        # cp onto the existing file keeps its owner and mode.
        cp -- "$source" "$file"
        replaced=$((replaced + 1))
    done
    if [ "$replaced" -eq 0 ] && [ "$kept" -eq 0 ]; then
        tutor_bb_warn "found no BB icons in $dist; nothing replaced."
        return 0
    fi
    if [ "$kept" -eq 0 ]; then
        echo "tutor Feature: replaced all $replaced BB icons in $dist with LSP ones."
    else
        echo "tutor Feature: replaced $replaced BB icons in $dist with LSP ones; kept $kept of BB's (see the warnings above)."
    fi
}

# install.sh's entry point: <lightTheme> <appIcons> <directory of LSP PNGs>.
tutor_bb_brand() {
    local light="$1" icons="$2" dir app
    [ "$light" = true ] || [ "$icons" = lsp ] || return 0
    if ! app="$(tutor_bb_app_dir)" || [ ! -d "$app/app/dist" ]; then
        tutor_bb_warn "could not find bb-app's web client (<bb-app>/app/dist), so BB keeps its own theme choice and icons."
        return 0
    fi
    dir="$app/app/dist"
    [ "$light" != true ] || tutor_bb_pin_light_theme "$dir"
    [ "$icons" != lsp ] || tutor_bb_lsp_icons "$dir" "$3"
}
