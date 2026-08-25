pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

// Detail panel for the codexbar Omarchy shell plugin. Owns the data: polls
// `codexbar --json` (raw numbers + state strings, no markup) and renders one
// section per usage window — animated meter with an elapsed/pace marker,
// percent, reset countdown, pacing indicator — plus credits and staleness.
Panel {
  id: root
  moduleName: "mryll.codexbar"
  ipcTarget: "mryll.codexbar"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so popout coordination has to identify as that widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Panel content colors (popup surface); the bar face uses barFaceForeground
  // below, which tracks the bar's own (transparency-aware) foreground.
  // The panel draws on the POPUP CARD, so it takes the popup surface's text
  // token — not the bar's. bar.foreground is chosen against the bar, which on a
  // transparent bar means "against the wallpaper"; that is the wrong contrast
  // reference for a card, and a theme that defines popups.text separately would
  // be ignored outright. (printbar already did this; the rest of the family now
  // agrees.)
  readonly property color foreground: Color.popups.text
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)

  // ---- Freshness suffix tint, shared by the whole family. The timestamp is
  // ALWAYS dim ("when is this from" is information, not a warning); only the
  // "· stale (…)" suffix carries a muted warning tone, never full urgent. Text
  // stays the primary carrier, so a monochrome panel loses nothing.
  readonly property color freshnessWarn: !panelColored ? dim : mix(dim, urgent, 0.4)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent, urgent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barFaceForeground: bar ? bar.barForeground : Color.foreground
  readonly property color barFaceDim: Qt.darker(barFaceForeground, 1.55)

  readonly property string binName: "codexbar"

  // Monochrome mode, mirroring the CLI's --no-color states. The plugin never
  // passes --no-color to codexbar: it consumes the structured JSON, which is
  // colorless by design (and keeps publishing `palette`), and decides its own
  // rendering here. Monochrome = foreground / dimmed foreground only: no ramp,
  // no urgent, no accent. Severity stays legible through the numbers, glyphs
  // and meter geometry, and the JSON `state` field still carries it for
  // anything scripting on top.
  // An unrecognized value normalizes to "full": a hand-edited shell.json must
  // not be able to silently take the color off both surfaces.
  readonly property string colorMode: {
    var v = String(setting("colorMode", "full"))
    return ["full", "none", "bar-only", "panel-only"].indexOf(v) >= 0 ? v : "full"
  }
  readonly property bool barColored:   colorMode === "full" || colorMode === "bar-only"
  readonly property bool panelColored: colorMode === "full" || colorMode === "panel-only"

  readonly property bool showLabel: setting("showLabel", true) === true
  readonly property bool vertical: bar ? bar.vertical : false

  // Ramp color for panel surfaces, flattened to plain foreground when the
  // panel is monochrome. The bar face has its own gate (see barColor).
  function panelUsageColor(pct) { return panelColored ? usageColor(pct) : foreground }

  // ---------------------------------------------------------------- data

  // Last good `codexbar --json` payload. Kept on failure so stale data stays
  // visible instead of flashing empty.
  property var report: null
  property string errorMessage: ""
  // The CLI answered `loading:true`: it has nothing yet and is waiting on the
  // network. Distinct from "no data and no idea why", which is the empty state.
  property bool loading: false

  // Countdowns and "updated" read this instead of Date.now() so the panel
  // keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var usageWindows: report && report.windows ? report.windows : []
  readonly property var credits: report ? (report.credits || null) : null
  readonly property bool hasCredits: !!credits && credits.has_credits === true
  readonly property string plan: report && report.plan ? String(report.plan) : ""

  // Hero brand mark: OpenAI's mark is monochrome by design — black on light,
  // white on dark — so it takes the panel foreground, which the theme already
  // resolves to whichever of those two this surface needs. That IS the brand
  // color here; there is no colored variant to honor.
  //
  // The glyph is the product's IDENTITY, not a gauge: it never follows the
  // usage ramp and never goes urgent, because severity is already said by the
  // numbers, the meters and the bar's alarm dot. Same reasoning as claudebar,
  // which wears Anthropic's orange for the same reason.
  readonly property color brandColor: foreground
  readonly property bool stale: pluginStale || (!!report && report.stale === true)
  readonly property var lastError: report ? (report.last_error || null) : null

  // ---------------------------------------------------------------- helpers

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  // WCAG relative luminance / contrast ratio.
  function relLuminance(c) {
    function chan(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
  }

  function contrastRatio(a, b) {
    var la = relLuminance(a)
    var lb = relLuminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // Generic contrast floor: blend `c` toward `safe` — preserving hue — only as
  // far as it takes to clear `minRatio` against `backdrop`. Normally a no-op.
  // Parameterised rather than hardcoded to the bar, because the panel's brand
  // mark needs the same treatment against a different surface and a different
  // ratio.
  function contrastFloor(c, backdrop, safe, minRatio) {
    if (contrastRatio(c, backdrop) >= minRatio) return c
    for (var t = 1; t <= 10; t++) {
      var blended = mix(c, safe, t / 10)
      if (contrastRatio(blended, backdrop) >= minRatio) return blended
    }
    return safe
  }

  // What the bar label is actually drawn against. An opaque bar paints its own
  // background; a transparent one shows the wallpaper, which we cannot sample —
  // but the shell already did, and picked a light or dark `barForeground`
  // accordingly, so we take the extreme that choice implies. Blending toward
  // `bar.background` on a transparent bar would floor the contrast against a
  // surface nobody can see.
  readonly property color barBackdrop: {
    var fg = bar ? bar.barForeground : Color.foreground
    if (bar && bar.transparent)
      return relLuminance(fg) > 0.5 ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
    return bar ? bar.background : Color.background
  }

  function legibleOnBar(c) { return contrastFloor(c, barBackdrop, barFaceForeground, 4.5) }

  // ------------------------------------------------------------ gauge ramp
  //
  // The meters read like a fuel gauge: green at 0% usage, through yellow and
  // amber, to red at the top. The four anchors come straight from the CLI
  // payload, which resolves them exactly once (--color-* flags > Omarchy
  // theme > One Dark defaults) — so the panel and the waybar rendering draw
  // the same palette from a single definition and honor the same overrides.
  //
  // Fallback (payload not in yet, or an older codexbar without `palette`):
  // derive the anchors from the theme instead of hardcoding hex — fixed
  // gauge hues, saturation off Color.urgent, lightness off Color.foreground,
  // both clamped so the ramp stays legible on any theme.
  function gaugeColor(hue) {
    var saturation = clamp(urgent.hslSaturation, 0.45, 0.85)
    var lightness = clamp(foreground.hslLightness, 0.32, 0.72)
    return Qt.hsla(hue, saturation, lightness, 1)
  }

  // Style.colorFromHex validates the string and returns the fallback when the
  // payload carries something that isn't a #hex color (e.g. a named CSS color
  // passed through --color-*, which the bash side renders but can't lerp).
  function paletteColor(key, fallback) {
    var p = report ? report.palette : null
    var value = p ? p[key] : null
    if (typeof value !== "string" || value === "") return fallback
    return Style.colorFromHex(value, fallback)
  }

  // Which colors come from where:
  //
  //   low / mid / high — from the CLI palette, because the shell's Color
  //     singleton has no green, yellow or orange. There is no other way for
  //     this panel to know what "green at 0%" means on the current theme.
  //   critical        — from the shell's `urgent`, NOT the payload. The shell
  //     already owns this concept, and its value is transparency-aware and
  //     animates on a theme switch; pinning a hex from the last poll would
  //     desync the meter from the rest of the bar for up to a refresh
  //     interval. The two agree on Omarchy anyway (both resolve the theme's
  //     red), so this costs nothing and keeps the widget in step.
  readonly property color gaugeLow:      paletteColor("low",  gaugeColor(0.33))
  readonly property color gaugeMid:      paletteColor("mid",  gaugeColor(0.14))
  readonly property color gaugeHigh:     paletteColor("high", gaugeColor(0.07))
  readonly property color gaugeCritical: paletteColor("critical", urgent)

  // The payload's own critical anchor, used only to recognise which published
  // stops belong to the critical band so they can be swapped for `urgent`.
  readonly property string paletteCriticalHex: {
    var p = report ? report.palette : null
    var v = p ? p.critical : null
    return (typeof v === "string") ? v.toLowerCase() : ""
  }

  // The ramp is DEFINED BY THE CORE: `palette.stops` carries both the colors
  // and the percentages they sit at, so a threshold change in codexbar moves
  // this panel with it. No severity percentage is written down in this file.
  //
  // The fallback list is only for a payload that predates `stops` (an older
  // binary on PATH); it pairs the anchor colors with the historical positions.
  readonly property var fallbackRampStops: [
    { "pct": 0,   "color": gaugeLow },
    { "pct": 50,  "color": gaugeMid },
    { "pct": 75,  "color": gaugeHigh },
    { "pct": 90,  "color": gaugeCritical },
    { "pct": 100, "color": gaugeCritical }
  ]

  readonly property var rampStops: {
    var p = report && report.palette ? report.palette.stops : null
    if (!Array.isArray(p) || p.length < 2) return fallbackRampStops
    var out = []
    for (var i = 0; i < p.length; i++) {
      var pct = Number(p[i] ? p[i].pct : NaN)
      if (!isFinite(pct)) return fallbackRampStops
      var hex = String(p[i].color || "")
      // Stops in the critical band render in the shell's live `urgent` rather
      // than the payload's hex — see the gaugeCritical note above.
      var c = (hex.toLowerCase() === paletteCriticalHex && paletteCriticalHex !== "")
        ? gaugeCritical
        : Style.colorFromHex(hex, foreground)
      out.push({ "pct": clamp(pct, 0, 100), "color": c })
    }
    return out
  }

  // One stop of the ramp, clamped to the ends — lets the gradient below
  // declare a fixed number of stops without caring how many the core sent.
  function rampStopAt(i) {
    var s = rampStops
    return s[clamp(i, 0, s.length - 1)]
  }

  // Color of scale position pct on the gauge: piecewise-linear across whatever
  // stops the core published. The meter fill uncovers this fixed ramp up to
  // the current value — the ramp itself never shifts with the value.
  function usageColor(pct) {
    var p = Number(pct)
    if (!isFinite(p)) p = 0
    p = clamp(p, 0, 100)
    var s = rampStops
    if (p <= s[0].pct) return s[0].color
    for (var i = 1; i < s.length; i++) {
      if (p <= s[i].pct) {
        var span = s[i].pct - s[i - 1].pct
        return mix(s[i - 1].color, s[i].color, span > 0 ? (p - s[i - 1].pct) / span : 1)
      }
    }
    return s[s.length - 1].color
  }

  // Text handed to the shell's shared tooltip is rendered as rich text outside
  // this plugin's control, and window labels can carry API-supplied model
  // names, so escape first and then wrap: the <span> forces AutoText into
  // rich-text mode, which is what makes the escaped entities decode correctly.
  function safeTooltip(s) {
    return "<span>" + String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        .replace(/>/g, "&gt;").replace(/\n/g, "<br/>") + "</span>"
  }

  // For shell components whose Text this plugin cannot set textFormat on —
  // PanelHero's meta line is one — an API string could arrive looking like
  // markup and be picked up by AutoText. Stripping the characters that make
  // Qt::mightBeRichText() say yes forces it down the plain-text path. Lossy by
  // design: a plan label containing these is hostile, not decorative.
  function plainForAutoText(s) {
    return String(s).replace(/[<>&]/g, " ").replace(/\s+/g, " ").trim()
  }

  function windowTitle(w) {
    if (!w) return ""
    var label = String(w.label || "")
    return w.group ? String(w.group) + " · " + label : label
  }

  // null means "no reset known" — a negative number is a real, already-passed
  // reset (rendered as "Resets now"), so it must stay distinguishable.
  function resetMsFor(w) {
    if (!w || !w.reset_at) return null
    var ms = new Date(String(w.reset_at)).getTime()
    return isFinite(ms) ? ms - root.nowMs : null
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function resetText(w) {
    var ms = resetMsFor(w)
    if (ms === null) return ""
    return ms <= 0 ? "Resets now" : "Resets in " + formatDuration(ms)
  }

  // Arrow and text both come from the SIGN of the delta, so they can never
  // disagree. The tolerance band lives in the state and paints only the COLOR.
  function paceText(w) {
    if (!w || !w.pace) return ""
    var d = Number(w.pace.delta_points)
    if (!isFinite(d) || d === 0) return "→ on pace"
    return (d > 0 ? "↑ " : "↓ ") + String(w.pace.points_label || "")
  }

  // Pacing severity → color. The CLI already owns where the bands turn and
  // publishes the answer as `pace.state`; re-deriving the thresholds here is
  // how the two surfaces of one product end up disagreeing. Only burning fast
  // earns full urgent; slightly ahead gets a nudge; under or on pace stays
  // quiet. Blended from `dim`, not from `foreground`, so "slightly ahead"
  // reads as a warmed-up version of the calm tone rather than a washed-out
  // version of the loud one.
  function paceColor(state) {
    // Monochrome keeps the distinction as lightness rather than hue: burning
    // fast reads at full foreground, everything calmer stays dimmed.
    if (!panelColored) return state === "hot" ? foreground : dim
    if (state === "hot") return urgent
    if (state === "ahead") return mix(dim, urgent, 0.5)
    return dim
  }

  // The API sends the balance as a string, so String() renders "24.5" for a
  // balance the CLI's own tooltip prints as "24.50". Two decimals everywhere:
  // a money figure that drops a digit reads as a different number.
  function creditsBalanceText(c) {
    if (!c) return ""
    if (c.unlimited === true) return "Unlimited"
    var n = Number(c.balance)
    return isFinite(n) ? n.toFixed(2) : String(c.balance || "")
  }

  function creditsDetailText(c) {
    if (!c) return ""
    var parts = []
    var local = c.approx_local_messages || [0, 0]
    var cloud = c.approx_cloud_messages || [0, 0]
    function range(pair) {
      var lo = Number(pair[0] || 0), hi = Number(pair[1] || 0)
      return lo === hi ? String(lo) : lo + "–" + hi
    }
    if (Number(local[1] || 0) > 0) parts.push("~" + range(local) + " local msgs")
    if (Number(cloud[1] || 0) > 0) parts.push("~" + range(cloud) + " cloud msgs")
    return parts.join(" · ")
  }

  function updatedTimeText() {
    if (!report || !report.updated_at) return ""
    var ms = new Date(String(report.updated_at)).getTime()
    if (!isFinite(ms)) return ""
    return Qt.formatTime(new Date(ms), "HH:mm")
  }

  // Freshness footer, in the house shape every widget of the family uses:
  // clock glyph, "Updated HH:MM", and a "· <status>" suffix only when the data
  // is not fresh. The waybar tooltip builds the same line from the same parts,
  // so a reader sees one footer regardless of which frontend renders it.
  function footerText() {
    if (!report) return loading ? "󰅐  Waiting for first usage data…" : ""
    var at = updatedTimeText()
    if (at === "" && !root.stale) return ""
    return "󰅐  Updated " + (at !== "" ? at : "—")
  }

  // Its own run, so it can carry the warning tint while the timestamp stays dim.
  function footerSuffix() {
    if (!root.stale) return ""
    if (root.pluginStale) return " · stale (refresh failed)"
    return " · stale (" + (report && report.stale_reason === "network"
      ? "waiting for network" : "API errors") + ")"
  }

  // ---------------------------------------------------------------- bar face

  readonly property string barWindowSetting: String(setting("barWindow", "Session")).toLowerCase()

  readonly property var barWindow: {
    if (usageWindows.length === 0) return null
    if (barWindowSetting === "worst") {
      var best = usageWindows[0]
      for (var i = 1; i < usageWindows.length; i++)
        if (Number(usageWindows[i].used_pct) > Number(best.used_pct)) best = usageWindows[i]
      return best
    }
    for (var j = 0; j < usageWindows.length; j++)
      if (String(usageWindows[j].id) === barWindowSetting) return usageWindows[j]
    return usageWindows[0]
  }

  // The percent the bar face actually displays, chosen by the barWindow
  // setting. The face is colored by THIS window and never by another one:
  // showing one window's number in a different window's color misreports both.
  readonly property real barWindowPct: {
    if (!barWindow) return 0
    var p = Number(barWindow.used_pct)
    return isFinite(p) ? clamp(p, 0, 100) : 0
  }

  // The label gate lives here and not in the bar widget: the panel already owns
  // the settings and the data, so one place decides whether there is a label.
  readonly property string barLabel: {
    if (!showLabel || vertical || !barWindow) return ""
    return Math.round(barWindowPct) + "%"
  }

  // A window OTHER than the one on the bar face sitting at critical severity.
  // The face reports its own window honestly; this is what stops it from
  // quietly hiding that a different limit is already spent. Codex exposes
  // several independent ones — session, weekly, code review, per-model meters
  // — and barWindow defaults to Session, so an exhausted weekly would
  // otherwise show up nowhere until the panel is opened.
  readonly property var criticalOthers: {
    var out = []
    if (!report) return out
    var shownId = barWindow ? String(barWindow.id) : ""
    for (var i = 0; i < usageWindows.length; i++) {
      var w = usageWindows[i]
      if (String(w.id) === shownId) continue
      if (String(w.state) === "critical") out.push(w)
    }
    return out
  }

  readonly property bool hasCriticalOther: criticalOthers.length > 0

  // Names the offender so the dot explains itself instead of being a mystery
  // mark: "Weekly: 100%", one line each when several are spent.
  readonly property string criticalOthersText: {
    var lines = []
    for (var i = 0; i < criticalOthers.length; i++) {
      var w = criticalOthers[i]
      lines.push(windowTitle(w) + ": " + Math.round(Number(w.used_pct)) + "%")
    }
    return lines.join("\n")
  }

  // Empty when there is no dot — Bar.showTooltip short-circuits on empty text,
  // so the bar face stays tooltip-free and the panel remains the detail view.
  readonly property string barTooltip: {
    var parts = []
    if (hasCriticalOther) parts.push(criticalOthersText)
    if (barStale) parts.push(" Stale — showing the last data from " + (updatedTimeText() || "earlier"))
    return parts.length > 0 ? safeTooltip(parts.join("\n")) : ""
  }

  // The dot is a warning, so it takes the gauge's critical anchor (under the
  // same contrast floor as the label); monochrome keeps the mark but drops the
  // color, since the tooltip is what carries the meaning.
  readonly property color criticalDotColor: barColored ? legibleOnBar(gaugeCritical) : barFaceForeground

  // The bar face takes the gauge ramp at the value it displays, so the same
  // number reads the same color on the bar and in the panel — under a contrast
  // floor that keeps a pale ramp color legible on the bar surface. No data yet
  // or stale data dims toward the muted shade.
  readonly property color barColor: {
    if (!report) return barFaceDim
    return barColored ? legibleOnBar(usageColor(barWindowPct)) : barFaceForeground
  }

  // Serving cached data. Drawn on the bar as ⏸, matching the CLI's bar text.
  // Freshness is deliberately NOT a color: blending the face toward the muted
  // shade restated staleness in the one channel that already means "how much is
  // used", so the same percentage read as two different tones depending on
  // whether the last poll succeeded — and disagreed with the panel, which kept
  // painting the true ramp color.
  readonly property bool barStale: !!report && stale

  // ---------------------------------------------------------------- polling
  //
  // Process runs are finalized only once BOTH the exit code and the collected
  // stdout are in (either can arrive first); a run requested while one is in
  // flight is queued last-command-wins and replayed with current settings.
  // Failures surface as an explicit error banner — never a silent swallow —
  // while the last-known-good report stays rendered underneath.

  property bool collectorDone: true
  property bool processDone: true

  // A fetch is in flight. BOTH halves matter: the exit code and the collected
  // stdout arrive in either order, which is exactly why maybeFinalize() waits
  // for the pair. The refresh button gates on this, not on collectorDone alone
  // — otherwise it re-enables in the gap between the two signals and a click
  // there queues a second run through pendingCmd, which is the one thing its
  // disabled state promises cannot happen.
  readonly property bool fetchBusy: !collectorDone || !processDone
  property string capturedText: ""
  property int exitCode: 0
  property var pendingCmd: null

  function buildCmd(force) {
    return force === true ? [binName, "--json", "--refresh"] : [binName, "--json"]
  }

  function refresh(force) {
    startRun(buildCmd(force === true))
  }

  function startRun(cmd) {
    if (proc.running) { pendingCmd = cmd; return }   // last-command-wins snapshot
    collectorDone = false; processDone = false; capturedText = ""
    proc.command = cmd; proc.running = true
  }

  function maybeFinalize() {
    if (!collectorDone || !processDone) return
    exitFallback.stop()
    finalizeRun()
  }

  function finalizeRun() {
    var text = capturedText.trim()
    if (text === "") {
      // The install hint lives HERE and not in the core, which is where every
      // other message of this family lives. The one message the core cannot
      // emit is the one about its own absence. But it is only true when
      // nothing else already explained the emptiness: the StdioCollector
      // tripwire also leaves capturedText empty, and there "not installed" is
      // a lie — the binary answered, it answered too much — so it would send
      // the reader off to install what they already have.
      if (root.errorMessage === "")
        setError(binName + " produced no output — not installed or not on PATH?\n\n"
                 + "Install it with:  yay -S codexbar\n"
                 + "Then open this panel again.")
    } else {
      handle(text)
    }
    if (pendingCmd) { var c = pendingCmd; pendingCmd = null; Qt.callLater(function() { root.startRun(c) }) }
  }


  // Set when the plugin's own run fails, cleared by the next good parse. ORed
  // into the freshness state so a failure here reads like any other staleness.
  property bool pluginStale: false

  function setError(message) {
    root.errorMessage = String(message)              // last-known-good report stays
    root.loading = false
    // The last good payload stays on screen — deliberate — but it must stop
    // claiming to be current. Without this the footer keeps printing a plain
    // "Updated HH:MM" for data the CLI can no longer refresh.
    pluginStale = true
  }

  function handle(out) {
    var d
    try {
      d = JSON.parse(out)
    } catch (e) {
      setError("Unreadable output from " + binName
               + (root.exitCode !== 0 ? " (exit " + root.exitCode + ")" : ""))
      return
    }
    if (d.loading === true) {                        // still waiting; keep last data
      root.loading = true
      return
    }
    root.loading = false
    if (d.error !== null && d.error !== undefined) {
      // A structured error document beats a generic exit-code message.
      setError(String(d.error.message || "Unknown error"))
      return
    }
    if (root.exitCode !== 0) {
      setError(binName + " exited with code " + root.exitCode)
      return
    }
    root.errorMessage = ""
    root.pluginStale = false
    root.report = d
  }

  Process {
    id: proc
    // A command that does not exist gives NEITHER `started` NOR `exited` —
    // Quickshell just drops `running` back to false. That is the only signal a
    // failed start emits, and without this handler the panel sits on its
    // loading text for ever: maybeFinalize() waits on processDone, which
    // nothing would ever set. This IS the first run of anyone who installed
    // the plugin from the marketplace and does not have the CLI yet.
    onRunningChanged: {
      if (running) return
      root.processDone = true
      exitFallback.restart()
      root.maybeFinalize()
    }
    onExited: function(exitCode) {
      root.exitCode = exitCode
      root.processDone = true
      exitFallback.restart()   // failed-start case: collector may never fire
      root.maybeFinalize()
    }
    stdout: StdioCollector {
      waitForEnd: true
      // A tripwire, not a limit. StdioCollector has already buffered the whole
      // stream by the time this runs, so this cannot cap the peak memory — the
      // real bound is in the CLI, which reads every file and every response
      // under a byte cap of its own. What this does is refuse to RETAIN an
      // answer that is far outside anything the CLI can legitimately produce,
      // and say so, instead of parsing megabytes of unknown text into the
      // long-lived shell process.
      readonly property int maxBytes: 1024 * 1024
      onStreamFinished: {
        if (text.length > maxBytes) {
          root.capturedText = ""
          root.setError(root.binName + " returned more than " + (maxBytes / 1024) + " KiB — refusing it")
        } else {
          root.capturedText = text
        }
        root.collectorDone = true
        root.maybeFinalize()
      }
    }
  }

  Timer {
    id: exitFallback
    interval: 300
    repeat: false
    onTriggered: {                                   // give up on the collector
      root.collectorDone = true
      root.maybeFinalize()
    }
  }

  Timer {
    interval: Math.max(15, parseInt(root.setting("refreshIntervalSec", 60), 10) || 60) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // Keeps countdowns and the footer honest while the panel sits open.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Panel-open sweep: every meter fills 0 -> value once per open. Data
  // refreshes while the panel sits open keep the 160ms width Behaviors and
  // never re-sweep — only the open path restarts this. The sweep is geometry
  // only: the ramp it uncovers is fixed to the scale and never animates, so
  // the colors under a given percentage stay put through the whole sweep.
  // openProgress constructs at 1 so a never-opened panel renders full meters.
  property real openProgress: 1

  // Gates the 160ms width Behaviors during the sweep: set BEFORE the jump to
  // 0 (or the Behavior would smear the reset), cleared in onFinished — not
  // onStopped, which fires spuriously when restart() interrupts a running
  // sweep on rapid re-opens.
  property bool openSweeping: false

  NumberAnimation {
    id: openSweep
    target: root
    property: "openProgress"
    from: 0
    to: 1
    duration: 200
    easing.type: Easing.OutCubic
    onFinished: root.openSweeping = false
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    // A panel that reopens where it was left scrolled shows the middle of
    // itself; every open starts at the top.
    if (panelFlick) panelFlick.contentY = 0
    openSweeping = true
    openSweep.restart()
    refresh(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // The shell's base handler covers open/close/show/hide/toggle; this one adds
  // `refresh` so a keybind or a script can force a fetch without opening the
  // panel. Overriding means restating the five, so `manageIpc: false` above
  // turns the base one off and this is the only handler on the target.
  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(true) }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refresh(true)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh(true) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: glyph · Codex · plan ----------
          PanelHero {
            width: parent.width
            title: "Codex"
            // A state word, not a restatement of the title right next to it:
            // PanelHero uppercases meta, so the fallback read "OPENAI CODEX
            // USAGE" under the word "Codex".
            meta: root.plan !== "" ? root.plainForAutoText(root.plan) : (root.loading ? "Loading" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: "\ue7cf"
                color: root.brandColor
                font.family: "Font Awesome 7 Brands"
                font.pixelSize: Style.font.display
              }
            }
          }

          // ---------- Empty / error states ----------
          // Two different situations, two different surfaces, the same two in
          // claudebar: "nothing to show yet" is a quiet centred line, while a
          // hard failure is a bordered card — a thing that went wrong deserves
          // an edge around it. An error BEHIND stale data is neither: that one
          // rides under the data it explains, at the bottom of the panel.
          Text {
            visible: root.usageWindows.length === 0 && root.errorMessage === ""
            width: parent.width
            topPadding: Style.space(16)
            textFormat: Text.PlainText
            text: "No usage data yet.\nLog in with the codex CLI and refresh."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            visible: root.errorMessage !== ""
            width: parent.width
            implicitHeight: errorText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.panelColored ? root.urgent : root.foreground, 0.10)
            borderSpec: Border.flat(root.alpha(root.panelColored ? root.urgent : root.foreground, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: errorText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              textFormat: Text.PlainText
              text: root.errorMessage
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Usage windows ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: root.usageWindows.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.usageWindows

              WindowRow {
                required property var modelData
                width: usageSection.width
                win: modelData
              }
            }
          }

          // ---------- Credits ----------
          PanelSeparator {
            visible: creditsSection.visible
            foreground: root.foreground
          }

          Column {
            id: creditsSection
            visible: root.hasCredits
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              width: parent.width
              text: "CREDITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(creditsLabel.implicitHeight, creditsValue.implicitHeight)

              // Same grammar as claudebar's EXTRA USAGE headline row: a dim
              // caption on the left saying what the figure is, the figure
              // itself bold on the right. Same structural row, same reading.
              Text {
                id: creditsLabel
                text: "Prepaid balance"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: creditsValue
                textFormat: Text.PlainText
                text: root.creditsBalanceText(root.credits)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              visible: text !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: root.creditsDetailText(root.credits)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Last API error (behind stale data) ----------
          //
          // A rule introduces it: without one the line floats against the
          // CREDITS block above and reads as part of it.
          PanelSeparator {
            visible: !!root.lastError
            foreground: root.foreground
          }

          Text {
            visible: !!root.lastError
            width: parent.width
            textFormat: Text.PlainText
            text: root.lastError
              ? ("HTTP " + root.lastError.http_status
                 + (String(root.lastError.message || "") !== "" ? " — " + root.lastError.message : ""))
              : ""
            // 5xx is the server failing; 4xx is usually something the user can
            // act on. Full urgent is reserved for the former.
            color: root.lastError && Number(root.lastError.http_status) >= 500
              ? (root.panelColored ? root.urgent : root.foreground)
              : (root.panelColored ? root.mix(root.dim, root.urgent, 0.5) : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---- Freshness footer: when the data is from, plus an inline
          //      refresh. The button re-runs the CLI right now — the same
          //      forced refresh the bar's middle-click does — so a stale panel
          //      can be corrected without closing it, and it is disabled while
          //      a fetch is already in flight so clicks cannot queue up. The
          //      rule and the row are always shown: the button has to stay
          //      reachable exactly when there is no timestamp to print yet.
          PanelSeparator {
            foreground: root.foreground
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(footerLabel.implicitHeight, refreshButton.implicitHeight)

            Row {
              id: footerLabel
              anchors.left: parent.left
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                text: root.footerText()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: text !== ""
                text: root.footerSuffix()
                textFormat: Text.PlainText
                color: root.freshnessWarn
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              // nf-md-refresh (U+F0450). Written literally: a JS "\\u" escape takes
              // exactly FOUR hex digits, so "\\uf0450" is U+F045 followed by a "0".
              iconText: "󰑐"
              tooltipText: "Refresh now"
              foreground: root.dim
              hoverColor: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              size: Style.space(20)
              enabled: !root.fetchBusy
              onClicked: root.refresh(true)
            }
          }
        }
      }
    }
  }

  // One usage window: title + percent/pace, meter with elapsed marker, and
  // reset countdown.
  component WindowRow: Column {
    id: windowRow
    property var win: null

    readonly property real usedPct: {
      var p = win ? Number(win.used_pct) : 0
      return isFinite(p) ? root.clamp(p, 0, 100) : 0
    }
    readonly property bool hasElapsed: !!win && !!win.reset_at
    readonly property real elapsed: hasElapsed ? root.clamp(Number(win.elapsed_pct) / 100, 0, 1) : 0
    // The percent readout takes the ramp's color at the value currently
    // PAINTED, the same one the fill's tip lands on — so the figure and its
    // bar tip hold the same color all the way through the count-up.
    readonly property color valueColor: root.panelUsageColor(meterFill.shownPct)

    // The meter's ramp is fixed to the TRACK's scale, but a Gradient spans the
    // FILL, not the track. Each scale anchor is therefore repositioned to
    // anchor/shownPct, and anchors past the tip collapse onto it carrying the
    // tip's color — so the visible segment is exactly the scale's 0..shownPct
    // portion and the tip always reads color(shownPct).
    //
    // shownPct is the fill's ACTUAL painted percentage (read off its animated
    // width), never the target: stops built from the target would paint a
    // compressed copy of the ramp into a narrower fill and stretch it as the
    // fill grows, sliding every color through both the open sweep and the
    // 160ms refresh animation. At zero width the fill paints nothing, so the
    // guard's return value is never actually seen.
    function rampStop(anchorPct, shownPct) {
      return shownPct > 0 ? Math.min(1, anchorPct / shownPct) : 0
    }
    function rampColor(anchorPct, shownPct) {
      return root.panelUsageColor(Math.min(anchorPct, shownPct))
    }

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(windowLabel.implicitHeight, windowValue.implicitHeight)

      Text {
        id: windowLabel
        textFormat: Text.PlainText
        text: root.windowTitle(windowRow.win)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: windowValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: windowValue
        textFormat: Text.PlainText
        // Counts up with its own meter. The figure and the fill's geometry
        // read ONE animated quantity — the fill's painted width — so they
        // cannot drift apart: not during the 200ms open sweep, and not during
        // the 160ms refresh transition, where the figure counts across to the
        // new value instead of jumping. Same rounding as the final figure, so
        // the last frame lands exactly on the real value.
        text: windowRow.win ? Math.round(meterFill.shownPct) + "%" : "—"
        color: windowRow.valueColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Meter: severity-tinted fill over the shared track, with a thin marker
    // at the elapsed fraction of the window — fill left of the marker means
    // under pace, past it means burning ahead.
    Item {
      id: meter
      width: parent.width
      // Tall enough for the elapsed marker's lane above the track (see below).
      implicitHeight: Style.space(14)

      Rectangle {
        id: meterTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
        radius: height / 2
        color: root.track
      }

      Rectangle {
        id: meterFill
        anchors.left: meterTrack.left
        anchors.verticalCenter: meterTrack.verticalCenter
        height: meterTrack.height
        radius: meterTrack.radius
        width: meterTrack.width * (windowRow.usedPct / 100) * root.openProgress

        // The percentage the fill is CURRENTLY painting, read back off its own
        // animated width. Deriving the stops from this — rather than from the
        // target value — is what keeps the ramp pinned through both
        // animations: the open sweep (driven by openProgress) and the 160ms
        // width Behavior on a data refresh, where the target jumps but the
        // width is still interpolating.
        readonly property real shownPct: meterTrack.width > 0
          ? width / meterTrack.width * 100 : 0

        // Spatial ramp fixed to the scale: the track reads the core's 0% color
        // at its left end and its 100% color at the right, through the stops
        // the core published. The fill just uncovers that ramp up to the
        // current value, so no color moves when usage changes.
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(0).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(0).pct, meterFill.shownPct)
          }
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(1).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(1).pct, meterFill.shownPct)
          }
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(2).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(2).pct, meterFill.shownPct)
          }
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(3).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(3).pct, meterFill.shownPct)
          }
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(4).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(4).pct, meterFill.shownPct)
          }
          GradientStop {
            position: windowRow.rampStop(root.rampStopAt(5).pct, meterFill.shownPct)
            color: windowRow.rampColor(root.rampStopAt(5).pct, meterFill.shownPct)
          }
        }

        Behavior on width {
          enabled: !root.openSweeping
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }

      Rectangle {
        id: elapsedMarker
        visible: windowRow.hasElapsed
        width: Math.max(2, Style.spaceReal(2))
        height: Math.max(3, Style.spaceReal(4))
        // Rides ABOVE the track, never across it. The marker sits at the
        // ELAPSED position, which lands on the fill when usage runs ahead of
        // pace and on the empty track when it runs behind — no single tone
        // holds contrast against both, and drawn over the fill it reads as a
        // seam in the bar rather than as a mark. Outside the track it always
        // meets the panel background, so its contrast is constant, and it can
        // never be mistaken for the fill's tip.
        anchors.bottom: meterTrack.top
        anchors.bottomMargin: Math.max(1, Style.spaceReal(1))
        // Travels with the fill and the figure: all three are scaled by the
        // same openProgress, so the sweep moves them as one.
        x: root.clamp(meterTrack.width * windowRow.elapsed * root.openProgress - width / 2,
                      0, Math.max(0, meterTrack.width - width))
        color: root.alpha(root.foreground, 0.75)

        Behavior on x {
          enabled: !root.openSweeping
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(resetLabel.implicitHeight, paceLabel.implicitHeight)

      Text {
        id: resetLabel
        textFormat: Text.PlainText
        text: root.resetText(windowRow.win)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: paceLabel
        textFormat: Text.PlainText
        text: root.paceText(windowRow.win)
        color: root.paceColor(windowRow.win && windowRow.win.pace ? String(windowRow.win.pace.state) : "")
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
