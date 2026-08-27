# CLAUDE.md

## Tooling

- Single bash script (`codexbar`) — no build step, no dependencies to install
- Install: `make install PREFIX=~/.local`

## Non-Obvious Rules

- **Quickshell emits NEITHER `started` NOR `exited` when the command does not exist** — `running` just drops back to false. `sawExit` is the discriminator: no `exited` = the run could not start; an `exited` run with empty output is an operational failure, never "not installed". Probed live: `exited` always arrives before `running` drops.
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

## Release

1. Commit `chore: release X.Y.Z` on `develop` bumping the `manifest.json` version (the script carries no version string; the tag and the manifest ARE the version), push.
2. Move master to the release — master only advances here: `git push origin develop:master`. Then `git tag vX.Y.Z && git push origin --tags`.
3. `gh release create vX.Y.Z` (bash widget: source-only release, nothing to build).
4. Only then bump the AUR package (`codexbar`) per the workspace `AGENTS.md` (`~/Work/personal/AGENTS.md`).
