# Demo fixture (for README screenshots)

`demo-data` stands in for the `codexbar` CLI with a synthetic account that shows
everything at once: session (5h) and weekly windows, the code-review limit, a
model-scoped meter (both of its windows), and a credits balance — placed across
the whole gauge so green, amber, orange and critical all appear in one shot,
with pacing running ahead, on pace and under. It builds a fake `HOME` and runs
the repo's own `codexbar` against it, so `--json`, the waybar document,
`--no-color`/`NO_COLOR` and every other flag behave exactly as in production.
Instants are computed at run time, so countdowns and "Updated HH:MM" always read
sensibly; it contains no account data and never touches the network.

```bash
PATH="$PWD/screenshots/demo:$PATH" <widget>      # e.g. the Omarchy plugin, or waybar
./screenshots/demo/demo-data --json | jq         # inspect it directly
CODEXBAR_DEMO=stale ./screenshots/demo/demo-data # stale banner + HTTP 503 card
```

`codexbar` in this directory is a symlink to `demo-data`, which is what makes the
`PATH` line above intercept the real binary. Not wired into the build, the
install target, or the test suite.
