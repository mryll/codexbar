# waybar-codex-usage

Waybar widget that displays your OpenAI Codex subscription usage — session (5h) limit, weekly limit, code review limit, and credits — with colored progress bars and countdown timers.

![screenshot](screenshot.png)

## Features

- Session (5h) and weekly usage with progress bars
- Code review usage tracking
- Credits balance display
- Pacing indicators (ahead/under/on track)
- Colored severity levels (green → yellow → orange → red)
- Rich Pango tooltip with box-drawing borders
- Token auto-refresh with background sync
- 60s cache to reduce API calls
- Graceful fallback on network errors

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) (`codex login` for authentication)
- `curl`, `jq`, GNU `date`, `base64` (standard on most Linux distros)
- A [Nerd Font](https://www.nerdfonts.com/) for icons
- Waybar

## Install

```bash
# User-local
make install PREFIX=~/.local

# System-wide
sudo make install

# Or just copy
cp codex-usage ~/.local/bin/
chmod +x ~/.local/bin/codex-usage
```

## Waybar Configuration

Add to your Waybar config:

```jsonc
"modules-right": ["custom/codex-usage", ...],

"custom/codex-usage": {
    "exec": "~/.local/bin/codex-usage",
    "return-type": "json",
    "interval": 60,
    "tooltip": true,
    "on-click": "xdg-open https://chatgpt.com/codex/settings/usage"
}
```

### CSS Styling

```css
#custom-codex-usage {
    margin: 0 8px;
    font-size: 11px;
}

#custom-codex-usage.low {
    color: #98c379;
}

#custom-codex-usage.mid {
    color: #e5c07b;
}

#custom-codex-usage.high {
    color: #d19a66;
}

#custom-codex-usage.critical {
    color: #e06c75;
}
```

## Custom Formats

```bash
# Bar text format
codex-usage --format '{session_pct}% · {weekly_pct}%'

# Tooltip format (plain text, replaces Pango tooltip)
codex-usage --tooltip-format 'Session: {session_pct}% | Weekly: {weekly_pct}%'
```

### Available Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `{icon}` | Codex icon (empty) | |
| `{plan}` | Plan label | `Plus` |
| `{session_pct}` | Session (5h) usage % | `42` |
| `{session_reset}` | Session countdown | `1h 30m` |
| `{session_elapsed}` | Session time elapsed % | `58` |
| `{session_pace}` | Pacing icon | `↑` / `↓` / `→` |
| `{session_pace_pct}` | Pacing deviation | `12% ahead` |
| `{weekly_pct}` | Weekly usage % | `27` |
| `{weekly_reset}` | Weekly countdown | `4d 1h` |
| `{weekly_elapsed}` | Weekly elapsed % | `42` |
| `{weekly_pace}` | Pacing icon | `↑` / `↓` / `→` |
| `{weekly_pace_pct}` | Pacing deviation | `5% under` |
| `{review_pct}` | Code review usage % | `4` |
| `{review_reset}` | Code review countdown | `6d 23h` |
| `{credits_balance}` | Credits balance | `0` |
| `{credits_local}` | Approx local messages | `10–15` |
| `{credits_cloud}` | Approx cloud messages | `5–8` |

## How It Works

1. Reads OAuth tokens from `~/.codex/auth.json` (created by `codex login`)
2. Auto-refreshes expired tokens via OpenAI's OAuth endpoint
3. Fetches usage data from the ChatGPT backend API
4. Caches responses for 60 seconds
5. Outputs JSON for Waybar: `{text, tooltip, class}`

## License

MIT
