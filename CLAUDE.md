# CLAUDE.md

## Tooling

- Single bash script (`codexbar`) — no build step, no dependencies to install
- Install: `make install PREFIX=~/.local`

## Non-Obvious Rules

- **Quickshell emits NEITHER `started` NOR `exited` when the command does not exist** — `running` just drops back to false. That is the only signal a failed start gives. Anything that waits on `onExited` to leave a loading state hangs for ever when the CLI is not installed, which is the first run of everyone who installs the plugin from the marketplace: the plugin is a git clone, the CLI is a package, and nothing installs the second for you. The `onRunningChanged` guard in the panel's `Process` is what makes the not-installed message reachable — verified against a running shell, not assumed.

- **A tooltip meter is PARKED, not rendered in place.** The bar has to reach the tooltip's right edge, and that edge is the widest TEXT line — which does not exist yet while the lines are being collected. So a meter pushes `METER:<i>` into `lines` plus one entry in the parallel `meter_*` arrays, and the width pass resolves it. The width pass MUST skip `METER:` lines, or the measurement is circular. Every meter in one tooltip gets the SAME bar length: they stack, so a reader compares them against each other.

- The script must ALWAYS exit 0 and output valid Waybar JSON (`{text, tooltip, class}`), even on errors — use the `die()` helper for error paths
- Tooltip markup is Pango (not HTML) — Waybar renders it via GTK/Pango
- Bar text is also wrapped in Pango `<span>` for coloring
- `set -euo pipefail` is active — unset variables and failed pipes are fatal
- Cache lives at `~/.cache/codexbar/`; auth at `~/.codex/auth.json`
- Concurrent instances are serialized with `flock` (multi-monitor support)
- Color chain (first match wins): `--color-*` flags > Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`, legacy `~/.config/...`) > pywal (`${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json`) > One Dark built-ins. Every step degrades silently; the resolved anchors are published as `palette` in `--json` so the Quickshell panel draws the same gauge
- `IFS=$'\t' read` collapses runs of empty fields (TAB is IFS whitespace) — emit a sentinel from `jq`, never an empty TSV field
