# CLAUDE.md

## Tooling

- Single bash script (`codexbar`) — no build step, no dependencies to install
- Install: `make install PREFIX=~/.local`

## Non-Obvious Rules

- **The CLI always runs through `/bin/sh -c 'exec "$0" "$@"'`, never direct.** Handing Quickshell 0.3.1 a nonexistent binary can ABORT the whole shell inside the failed start (claudebar#6) — before any QML signal fires, so no handler can catch it. sh always starts; a failed exec is sh exiting 127 (not found) or 126 (not executable). The failed-start discriminator is therefore `!sawExit || exitCode === 126 || exitCode === 127` on empty output: `!sawExit` stays as the belt for a Quickshell that emits neither `started` nor `exited`, and 126/127 is a deliberate approximation — a foreign broken `codexbar` exiting 126/127 empty lands there too, and the bundled fallback is the right move for it as well (the script itself always exits 0). An `exited` run with empty output and any other code is an operational failure, never "not installed".
- **The bundled-script fallback fires ONLY on a failed start.** The plugin clone carries the script, so the panel switches `resolvedBin` to the clone's copy when PATH cannot start it. PATH first, always: the AUR release wins when it exists. Never fall back on operational errors. A later `yay -S` applies on the next shell restart.
- **URL→path decodes each segment** (mirror of `Util.fileUrl`). The naive scheme strip is banned; `test_bundled_fallback.sh` pins it. A bad `%` degrades to PATH-only.
- **`schema_version` is pinned to 2 on both sides.** A schema bump must change script, panel and tests in one commit.
- **`installCmd` is the one constant** — the message shows it and the button copies it (`Util.execArgv(["wl-copy", ...])`, no shell line, no trailing newline). The button gates on `notInstalled`, never on error text.

- **A tooltip meter is PARKED, not rendered in place.** The bar has to reach the tooltip's right edge, and that edge is the widest TEXT line — which does not exist yet while the lines are being collected. So a meter pushes `METER:<i>` into `lines` plus one entry in the parallel `meter_*` arrays, and the width pass resolves it. The width pass MUST skip `METER:` lines, or the measurement is circular. Every meter in one tooltip gets the SAME bar length: they stack, so a reader compares them against each other.

- The script must ALWAYS exit 0 and output valid Waybar JSON (`{text, tooltip, class}`), even on errors — use the `die()` helper for error paths
- Tooltip markup is Pango (not HTML) — Waybar renders it via GTK/Pango
- Bar text is also wrapped in Pango `<span>` for coloring
- `set -euo pipefail` is active — unset variables and failed pipes are fatal
- Cache lives at `~/.cache/codexbar/`; auth at `~/.codex/auth.json`
- Concurrent instances are serialized with `flock` (multi-monitor support)
- Color chain (first match wins): `--color-*` flags > Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`, legacy `~/.config/...`) > pywal (`${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json`) > One Dark built-ins. Every step degrades silently; the resolved anchors are published as `palette` in `--json` so the Quickshell panel draws the same gauge
- `IFS=$'\t' read` collapses runs of empty fields (TAB is IFS whitespace) — emit a sentinel from `jq`, never an empty TSV field

