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
- Theme colors auto-load from Omarchy (`~/.config/omarchy/current/theme/colors.toml`) with One Dark fallback
