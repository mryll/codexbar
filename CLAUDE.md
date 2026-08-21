# CLAUDE.md

## Tooling

- Single bash script (`codexbar`) — no build step, no dependencies to install
- Install: `make install PREFIX=~/.local`

## Non-Obvious Rules

- The script must ALWAYS exit 0 and output valid Waybar JSON (`{text, tooltip, class}`), even on errors — use the `die()` helper for error paths
- Tooltip markup is Pango (not HTML) — Waybar renders it via GTK/Pango
- Bar text is also wrapped in Pango `<span>` for coloring
- `set -euo pipefail` is active — unset variables and failed pipes are fatal
- Cache lives at `~/.cache/codexbar/`; auth at `~/.codex/auth.json`
- Concurrent instances are serialized with `flock` (multi-monitor support)
- Color chain (first match wins): `--color-*` flags > Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`, legacy `~/.config/...`) > pywal (`${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json`) > One Dark built-ins. Every step degrades silently; the resolved anchors are published as `palette` in `--json` so the Quickshell panel draws the same gauge
- `IFS=$'\t' read` collapses runs of empty fields (TAB is IFS whitespace) — emit a sentinel from `jq`, never an empty TSV field
