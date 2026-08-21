# Demo fixture

`demo-data` impersonates `codexbar` with a fixed, plausible day of usage, so README
screenshots show every section at once without exposing a real account. It does
not reimplement any rendering: it builds a throwaway `HOME` holding the API
documents the real script would have cached, stubs `curl`, and then runs the
real script against it. Bar text, tooltip, `--json`, `--no-color`,
`--remaining` and theme resolution therefore behave exactly as in production —
this only substitutes the data. Instants are computed at run time, so countdowns,
elapsed markers and pacing all read live.

```bash
PATH="$PWD/screenshots/demo:$PATH" codexbar          # waybar mode
PATH="$PWD/screenshots/demo:$PATH" codexbar --json   # structured mode
```

## The demo day

The same day claudebar's fixture renders, slot for slot: same usage numbers, same
elapsed positions, same gauge bands, same pacing states. The two widgets sit
next to each other in every README, so a reader comparing them is comparing the
design and not two unrelated afternoons.

| window | used | elapsed | band | pace |
| --- | --- | --- | --- | --- |
| Session (5h) | 34% | 15% | green | +19 ahead |
| Weekly (7d) | 68% | 68% | amber | on pace |
| Code review (7d) | 82% | 95% | orange | −13 under |
| Spark (5h) | 94% | 60% | critical | +34 ahead |
| Spark (7d) | 12% | 60% | deep green | −48 under |
| Credits | $24.50 | — | — | — |

The Spark 5h meter at 94% is what makes the bar face show its alarm dot: the
face itself displays the green session window, so without the dot a spent limit
would go unmentioned until the panel is opened. The last row is the one thing
claudebar's fixture cannot mirror — Codex sells credits, Claude sells extra
usage against a monthly cap.

## Variants

| variable | effect |
| --- | --- |
| `CODEXBAR_DEMO_STALE=1` | the network is unreachable: cached data behind the ⏸ mark |
| `CODEXBAR_DEMO_ERROR=503` | the API answered an error: the stale mark plus the HTTP card. Takes `code` or `code:message` |

Both drive the real staleness path — an aged cache plus what the stubbed `curl`
answers — rather than planting the marker files the script writes for itself, so
the demo cannot drift from the code it documents.

`codexbar` in this directory is a real file, not a symlink: `omarchy-plugin-validate`
rejects symlinks anywhere inside a plugin folder, and this repo root *is* the
plugin folder. It execs `demo-data`, which is what makes the `PATH` line above
intercept the real binary.

This directory is documentation tooling only — not part of the build, the
install target, or the test suite.
