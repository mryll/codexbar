import QtQuick
import qs.Commons
import qs.Ui

// Bar slot for the codexbar Omarchy shell plugin. Compact by design: the
// OpenAI brand glyph plus a terse usage label, severity-tinted. The full
// breakdown lives in Panel.qml, which also owns the data polling.
BarWidget {
  id: root
  moduleName: "mryll.codexbar"
  readonly property string brandIcon: "\ue7cf"

  readonly property var panelItem: panelLoader.item

  // The plugin clone carries the script at its root. This file knows the
  // clone's path (Qt.resolvedUrl is relative to it). The panel uses this
  // path only when the PATH command cannot start. Empty = no fallback.
  readonly property string bundledCmd: urlToPath(Qt.resolvedUrl("../codexbar"))

  // Decode each segment: the mirror of Util.fileUrl's encoding. A plain
  // scheme strip keeps the encoding and gives a path that does not exist.
  function urlToPath(u) {
    var s = String(u)
    if (s.indexOf("file://") !== 0) return ""
    try { return s.substring(7).split("/").map(decodeURIComponent).join("/") }
    catch (e) { return "" }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("bundledCmd" in target) target.bundledCmd = root.bundledCmd
  }

  // Two names because they mean different things: refresh() honours the read
  // cache (the safe thing to expose to a future shell hook), refreshForce()
  // bypasses it. Middle click is a deliberate user gesture, so it forces.
  function refresh() {
    if (panelItem && panelItem.refresh) panelItem.refresh(false)
  }

  function refreshForce() {
    if (panelItem && panelItem.refresh) panelItem.refresh(true)
  }

  function togglePanel() {
    if (panelItem && panelItem.toggle) panelItem.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelItem ? panelItem.opened === true : false

  function open() {
    if (panelItem && panelItem.open) panelItem.open()
  }

  function close() {
    if (panelItem && panelItem.close) panelItem.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity (Bar.requestPopout prefers closeForPopoutSwitch over close).
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelItem) panelItem.closeForPopoutSwitch()
  }

  // Icon-only on vertical bars and when the label is disabled; the panel is
  // always one click away either way. Both gates are applied in Panel.qml,
  // which owns the settings.
  readonly property string barLabel: panelItem ? panelItem.barLabel : ""
  readonly property string plainText: brandIcon + (barLabel !== "" ? " " + barLabel : "")

  // How wide the bar's open-panel underline should be. Without this hint the bar
  // falls back to 55% of the SLOT, which reads as a dot under a narrow widget
  // but as a bar that visibly stops short under a wide one. The painted content
  // is the honest extent, so the mark tracks what the widget draws instead of a
  // fraction of the box it happens to sit in. (Same hint the first-party clock
  // gives; it passes its label width.)
  // Extent of the open-panel mark, and the width the content row is centered
  // against. The bar computes the mark as
  //     width = Math.round(hint);  x = Math.round((slot.width - width) / 2)
  // so the row must be centered with the SAME rounded width and the SAME
  // formula. Letting `anchors.centerIn` center the row against its own
  // fractional implicitWidth instead puts the two on different pixels whenever
  // the slot width is fractional (it usually is: font metrics are not integers),
  // and the mark reads as shifted under the text.
  readonly property real markExtent: Math.round(contentRow.implicitWidth)
  readonly property real openPanelIndicatorWidth: markExtent

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.plainText
    labelVisible: false
    fixedWidth: root.vertical ? -1 : contentRow.implicitWidth + button.scaledHorizontalMargin * 2
    foreground: root.panelItem ? root.panelItem.barColor
                               : (root.bar ? root.bar.barForeground : Color.foreground)
    // Normally suppressed — the panel is the detail view. The one exception is
    // the alarm dot: a mark you can't interpret is worse than no mark, so
    // hovering names the window that is actually spent.
    tooltipText: root.panelItem ? root.panelItem.barTooltip : ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refreshForce()
      else if (b === Qt.RightButton) {
        if (root.bar) root.bar.run("xdg-open https://chatgpt.com/codex/settings/usage")
      } else root.togglePanel()
    }

    Row {
      id: contentRow
      x: Math.round((parent.width - root.markExtent) / 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: (label.visible || alertSlot.visible) ? Style.spacing.labelGap : 0

      Text {
        text: root.brandIcon
        textFormat: Text.PlainText
        color: button.foreground
        font.family: "Font Awesome 7 Brands"
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        id: label
        visible: root.barLabel !== ""
        text: root.barLabel
        textFormat: Text.PlainText
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
      }


      // Serving cached data — the same ⏸ the CLI appends to the waybar bar text.
      // A mark, not a tint: the number keeps the ramp color of its own value, so
      // the bar and the panel never show one percentage in two colors. Hovering
      // the widget says what it means.
      Text {
        visible: root.panelItem ? root.panelItem.barStale === true : false
        // nf-fa-pause, not U+23F8: the Unicode pause resolves to the COLOR
        // emoji glyph here, which paints its own orange and ignores the theme
        // tone this mark is supposed to wear. U+FE0E does not help — the font
        // stack has no text-presentation glyph for it. The CLI emits the same
        // Nerd glyph in the waybar bar text.
        text: "\uf04c"
        textFormat: Text.PlainText
        color: Qt.darker(button.foreground, 1.55)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Math.round(button.fontSize * 0.85)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      // Alarm dot: some window OTHER than the one shown is spent. Sized off the
      // label's own line box so it centers against the text; a Row top-aligns
      // its children, and binding to the label (never to the Row) keeps that
      // free of a height loop. Hovering the widget names the offender.
      Item {
        id: alertSlot
        visible: root.panelItem ? root.panelItem.hasCriticalOther === true : false
        width: dot.width
        height: label.implicitHeight

        Rectangle {
          id: dot
          anchors.centerIn: parent
          width: Math.max(3, Style.space(4))
          height: width
          radius: width / 2
          color: root.panelItem ? root.panelItem.criticalDotColor
                                : (root.bar ? root.bar.urgent : Color.urgent)
        }
      }
    }
  }
}
