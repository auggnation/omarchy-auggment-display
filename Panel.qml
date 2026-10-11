import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar widget + popup. Pick a display in the list, edit it below. Display
// state and the keep/revert flow live in DisplayStore, shared with the
// arrangement window (Arrange.qml). Brightness and text size are local.
Panel {
  id: root
  moduleName: DisplayStore.pluginId
  ipcTarget: DisplayStore.pluginId
  manageIpc: false

  property string hoveredName: ""

  property bool brightnessAvailable: false
  property int brightnessPercent: 0
  property bool brightnessSetQueued: false
  property real wheelAccumulator: 0

  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1

  // Auggment settings
  readonly property var auggBgIntervals: [60, 120, 300, 600, 900, 1800, 3600]
  readonly property var auggSsTimes: [60, 120, 180, 300, 600, 900, 1800]
  readonly property var auggScreenOffTimes: [120, 300, 600, 900, 1800, 3600]
  property int auggBgIndex: 2
  property int auggSsIndex: 3
  property int auggScreenOffIndex: 2
  property bool auggAutoColor: false

  // Bundled helper scripts live next to this panel (bin/).
  readonly property string auggBinDir: Qt.resolvedUrl("bin").toString().replace("file://", "")
  readonly property int auggBgSeconds: auggBgIntervals[auggBgIndex]

  readonly property var scaleOptions: DisplayStore.current
    ? Model.availableScales(DisplayStore.scalePresets, DisplayStore.current.width, DisplayStore.current.height).map(function(s) { return { value: s, label: s + "x" } })
    : []
  readonly property var resolutionOptions: DisplayStore.selected ? Model.resolutions(DisplayStore.selected.modes) : []
  readonly property var refreshOptions: DisplayStore.current
    ? Model.refreshRates(DisplayStore.selected.modes, DisplayStore.current.width, DisplayStore.current.height)
    : []
  readonly property var mirrorOptions: {
    var options = [{ value: "", label: "Extend" }]
    var displays = DisplayStore.displays
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (!DisplayStore.selected || d.name === DisplayStore.selected.name || !d.enabled) continue
      options.push({ value: d.name, label: "Mirror " + d.model })
    }
    return options
  }

  function openArrange() {
    root.close()
    if (root.bar && root.bar.shell) root.bar.shell.summon(DisplayStore.pluginId, "{}")
  }

  function readBrightness() {
    if (!DisplayStore.selected) return
    brightnessReadProc.command = ["omarchy-brightness-display", "--monitor", DisplayStore.selected.name]
    brightnessReadProc.running = true
  }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    brightnessPercent = percent
    if (brightnessSetProc.running) { brightnessSetQueued = true; return }
    brightnessSetQueued = false
    brightnessSetProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", DisplayStore.selected.name, percent + "%"]
    brightnessSetProc.running = true
  }

  function nearestTextStop(px) {
    var best = 0
    for (var i = 0; i < textSizeStops.length; i++)
      if (Math.abs(textSizeStops[i] - px) < Math.abs(textSizeStops[best] - px)) best = i
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  function setTextSize(index) {
    textSizePreviewIndex = index
    textSizeProc.command = ["omarchy-display-text-size", String(textSizeStops[index])]
    textSizeProc.running = true
  }

  function setAuggBg(index) {
    auggBgIndex = index
    var val = auggBgIntervals[index]
    auggBgProc.command = ["bash", "-c", "mkdir -p $HOME/.config/auggment && echo " + val + " > $HOME/.config/auggment/bg_interval"]
    auggBgProc.running = true
  }

  function auggmentRotateNow() {
    auggBgProc.command = ["bash", "-c", root.auggBinDir + "/bgchanger.sh --once"]
    auggBgProc.running = true
  }

  function setAuggSs(index) {
    auggSsIndex = index
    var val = auggSsTimes[index]
    auggSsProc.command = ["bash", "-c", "mkdir -p $HOME/.config/auggment && echo " + val + " > $HOME/.config/auggment/screensaver_timeout && jq '.idle.screensaver = " + val + "' $HOME/.config/omarchy/shell.json > /tmp/shell.json.new && mv /tmp/shell.json.new $HOME/.config/omarchy/shell.json"]
    auggSsProc.running = true
  }

  function setAuggScreenOff(index) {
    auggScreenOffIndex = index
    var val = auggScreenOffTimes[index]
    auggScreenOffProc.command = ["bash", "-c", "mkdir -p $HOME/.config/auggment && echo " + val + " > $HOME/.config/auggment/screen_off_timeout && " + root.auggBinDir + "/auggment-idle-sync.sh"]
    auggScreenOffProc.running = true
  }

  function setAuggAutoColor(val) {
    auggAutoColor = val
    auggColorProc.command = ["bash", "-c", "mkdir -p $HOME/.config/auggment && echo " + (val ? 1 : 0) + " > $HOME/.config/auggment/auto_color_match"]
    auggColorProc.running = true
  }


  function modeSummary(d) {
    if (!d.enabled) return "Off"
    var text = d.width + "×" + d.height + " @ " + Math.round(d.hz) + " Hz · " + d.scale + "x"
    if (d.transform) text += " · " + Model.transformLabel(d.transform)
    if (d.mirrorOf) text += " · mirrors " + d.mirrorOf
    return text
  }

  // omarchy-shell io.github.auggnation.auggment-display <method> [arg]
  IpcHandler {
    target: DisplayStore.pluginId

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function arrange() { root.openArrange() }
    function state(): string { return JSON.stringify({ selected: DisplayStore.selectedName, pending: DisplayStore.pending, displays: DisplayStore.displays }) }
    function select(name: string) { DisplayStore.select(name) }
    function change(patchJson: string) { DisplayStore.change(JSON.parse(patchJson)) }
    function keep() { DisplayStore.keep() }
    function revert() { DisplayStore.revert() }
    function forget() { DisplayStore.forgetSaved() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function readAuggConfig() {
    readAuggBg.running = true
    readAuggSs.running = true
    readAuggScreenOff.running = true
    readAuggColor.running = true
  }

  Component.onCompleted: {
    readBrightness()
    readAuggConfig()
  }

  onOpenedChanged: if (opened) { DisplayStore.refresh(); readBrightness() }

  Connections {
    target: DisplayStore
    function onSelectedNameChanged() { root.readBrightness() }
  }

  Timer {
    interval: 5000
    running: root.opened && !DisplayStore.hasPending
    repeat: true
    onTriggered: DisplayStore.refresh()
  }

  Process {
    id: brightnessReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text).trim(), 10)
        root.brightnessAvailable = isFinite(value)
        root.brightnessPercent = isFinite(value) ? value : 0
      }
    }
  }

  Process {
    id: brightnessSetProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running && root.brightnessSetQueued) root.setBrightness(root.brightnessPercent)
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: textSizeProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: readAuggBg
    command: ["bash", "-c", "cat $HOME/.config/auggment/bg_interval 2>/dev/null || echo 300"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var val = parseInt(String(text).trim(), 10)
        for (var i = 0; i < root.auggBgIntervals.length; i++)
          if (root.auggBgIntervals[i] === val) { root.auggBgIndex = i; break }
      }
    }
  }

  Process {
    id: readAuggSs
    command: ["bash", "-c", "cat $HOME/.config/auggment/screensaver_timeout 2>/dev/null || echo 300"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var val = parseInt(String(text).trim(), 10)
        for (var i = 0; i < root.auggSsTimes.length; i++)
          if (root.auggSsTimes[i] === val) { root.auggSsIndex = i; break }
      }
    }
  }

  Process {
    id: readAuggScreenOff
    command: ["bash", "-c", "cat $HOME/.config/auggment/screen_off_timeout 2>/dev/null || echo 600"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var val = parseInt(String(text).trim(), 10)
        for (var i = 0; i < root.auggScreenOffTimes.length; i++)
          if (root.auggScreenOffTimes[i] === val) { root.auggScreenOffIndex = i; break }
      }
    }
  }

  Process {
    id: readAuggColor
    command: ["bash", "-c", "cat $HOME/.config/auggment/auto_color_match 2>/dev/null || echo 0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.auggAutoColor = (String(text).trim() === "1") }
    }
  }

  Process { id: auggBgProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: auggSsProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: auggScreenOffProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: auggColorProc; stdout: StdioCollector { waitForEnd: true } }

  // Rotate the wallpaper on the configured interval; the bundled script does
  // the pick/set/retint work. No systemd service required.
  Timer {
    id: auggBgTimer
    interval: Math.max(1, root.auggBgSeconds) * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.auggmentRotateNow()
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      if (root.textSizePreviewIndex >= 0 && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: DisplayStore.displays.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.setBrightness(root.brightnessPercent + wheel.steps * 5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: DisplayStore.selected ? DisplayStore.selected.model : "Display"
            meta: DisplayStore.selected ? DisplayStore.selected.name + " · " + root.modeSummary(DisplayStore.selected) : ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                text: DisplayStore.displays.length > 1 ? "󰍺" : "󰍹"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Display list ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(displaysHeader.implicitHeight, arrangeButton.implicitHeight)

              PanelSectionHeader {
                id: displaysHeader
                text: "DISPLAYS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: arrangeButton
                visible: DisplayStore.layoutRects.length > 1
                text: "Arrange…"
                bordered: true
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.openArrange()
              }
            }

            Repeater {
              model: DisplayStore.displays

              CursorSurface {
                id: displayRow
                required property var modelData
                width: panelColumn.width
                implicitHeight: rowInner.implicitHeight + Style.spacing.xl
                current: modelData.name === DisplayStore.selectedName
                hasCursor: modelData.name === root.hoveredName
                foreground: root.bar.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: root.hoveredName = containsMouse ? displayRow.modelData.name : (root.hoveredName === displayRow.modelData.name ? "" : root.hoveredName)
                  onClicked: DisplayStore.select(displayRow.modelData.name)
                }

                Row {
                  id: rowInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  Text {
                    text: displayRow.modelData.internal ? "󰌢" : "󰍹"
                    color: root.bar.foreground
                    opacity: displayRow.modelData.enabled ? 1 : 0.45
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.title
                    width: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    width: parent.width - Style.space(22) - enableSwitch.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: displayRow.modelData.model + (displayRow.modelData.focused ? " · focused" : "")
                      color: root.bar.foreground
                      opacity: displayRow.modelData.enabled ? 1 : 0.45
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: displayRow.modelData.name + " · " + root.modeSummary(displayRow.modelData)
                      color: Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  ToggleSwitch {
                    id: enableSwitch
                    checked: displayRow.modelData.enabled
                    interactive: !displayRow.modelData.enabled || DisplayStore.enabledCount > 1
                    foreground: root.bar.foreground
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: DisplayStore.setEnabled(displayRow.modelData, !displayRow.modelData.enabled)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Selected display ----------
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: DisplayStore.current !== null && !DisplayStore.current.disabled

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.brightnessAvailable

              Item {
                width: parent.width
                implicitHeight: brightnessHeader.implicitHeight

                PanelSectionHeader {
                  id: brightnessHeader
                  text: "BRIGHTNESS"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  anchors.left: parent.left
                }

                Text {
                  text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "% · " + Model.brightnessName(root.brightnessPercent).toUpperCase()
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                }
              }

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                width: parent.width - Style.space(12)
                anchors.horizontalCenter: parent.horizontalCenter
                minimum: 1
                maximum: 100
                step: 1
                integer: true
                value: root.brightnessPercent
                onMoved: function(v) { root.brightnessPercent = Math.round(v); brightnessDebounce.restart() }
                onReleased: function(v) { brightnessDebounce.stop(); root.setBrightness(v) }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "RESOLUTION"
                options: root.resolutionOptions
                value: DisplayStore.current ? DisplayStore.current.width + "x" + DisplayStore.current.height : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.setResolution(v) }
              }

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "REFRESH RATE"
                options: root.refreshOptions
                value: DisplayStore.current ? Number(DisplayStore.current.hz).toFixed(2) : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.change({ hz: Number(v) }) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              PanelSectionHeader { text: "SCALE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              ButtonGroup {
                options: root.scaleOptions
                value: DisplayStore.current ? DisplayStore.current.scale : ""
                focusable: false
                foreground: root.bar.foreground
                background: root.bar.background
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                onChanged: function(v) { DisplayStore.change({ scale: v }) }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap

                PanelSectionHeader { text: "ROTATION"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

                ButtonGroup {
                  options: [0, 1, 2, 3].map(function(t) { return { value: String(t), label: Model.transformLabel(t) } })
                  value: DisplayStore.current ? String(DisplayStore.current.transform) : "0"
                  focusable: false
                  foreground: root.bar.foreground
                  background: root.bar.background
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onChanged: function(v) { DisplayStore.change({ transform: Number(v) }) }
                }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap

                PanelSectionHeader {
                  text: "VRR" + (DisplayStore.selectedEdid.range ? " · " + DisplayStore.selectedEdid.range + " HZ" : "")
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }

                ButtonGroup {
                  options: [{ value: "0", label: "Off" }, { value: "1", label: "On" }, { value: "2", label: "Fullscreen" }]
                  value: DisplayStore.current ? String(DisplayStore.current.vrr) : "0"
                  focusable: false
                  foreground: root.bar.foreground
                  background: root.bar.background
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onChanged: function(v) { DisplayStore.change({ vrr: Number(v) }) }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "MIRROR"
                options: root.mirrorOptions
                value: DisplayStore.current ? DisplayStore.current.mirror : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.change({ mirror: v }) }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                visible: DisplayStore.selectedEdid.hdr

                PanelSectionHeader { text: "HDR"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

                Item {
                  width: parent.width
                  height: Style.spacing.controlHeight

                  ToggleSwitch {
                    checked: DisplayStore.current ? DisplayStore.current.hdr : false
                    foreground: root.bar.foreground
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: DisplayStore.change({ hdr: !DisplayStore.current.hdr })
                  }

                  Text {
                    text: "10-bit HDR"
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Text size (global) ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: textHeader.implicitHeight

              PanelSectionHeader {
                id: textHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
              }

              Text {
                text: root.textSizeStops[textSizeSlider.dragging ? Math.round(textSizeSlider.liveValue) : root.currentTextIndex()] + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
              }
            }

            PanelSlider {
              id: textSizeSlider
              bar: root.bar
              width: parent.width - Style.space(12)
              anchors.horizontalCenter: parent.horizontalCenter
              minimum: 0
              maximum: root.textSizeStops.length - 1
              step: 1
              integer: true
              tickCount: root.textSizeStops.length
              value: root.currentTextIndex()
              onReleased: function(v) { root.setTextSize(Math.round(v)) }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Auggment Settings ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "AUGGMENT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(20)
              rowSpacing: Style.space(10)
              property real cell: (width - columnSpacing) / 2

              Column {
                width: parent.cell
                spacing: Style.space(4)
                Text { text: "Background: " + (auggBgIntervals[auggBgIndex]/60) + "m"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                PanelSlider {
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: auggBgIntervals.length - 1
                  step: 1
                  integer: true
                  value: auggBgIndex
                  onReleased: function(v) { setAuggBg(Math.round(v)) }
                }
              }

              Column {
                width: parent.cell
                spacing: Style.space(4)
                Text { text: "Screensaver: " + auggSsTimes[auggSsIndex] + "s"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                PanelSlider {
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: auggSsTimes.length - 1
                  step: 1
                  integer: true
                  value: auggSsIndex
                  onReleased: function(v) { setAuggSs(Math.round(v)) }
                }
              }

              Column {
                width: parent.cell
                spacing: Style.space(4)
                Text { text: "Screen off: " + (auggScreenOffTimes[auggScreenOffIndex]/60) + "m"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                PanelSlider {
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: auggScreenOffTimes.length - 1
                  step: 1
                  integer: true
                  value: auggScreenOffIndex
                  onReleased: function(v) { setAuggScreenOff(Math.round(v)) }
                }
              }

              Column {
                width: parent.cell
                spacing: Style.space(4)
                Text { text: "Auto color match"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                Row {
                  spacing: Style.space(6)
                  CheckBox { checked: auggAutoColor; onToggled: setAuggAutoColor(!auggAutoColor) }
                  Text { text: auggAutoColor ? "On" : "Off"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

// ---------- Pending change bar ----------

          Rectangle {
            width: parent.width
            visible: DisplayStore.hasPending
            implicitHeight: pendingRow.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Style.selectedFillFor(root.bar.foreground, Color.accent)

            Row {
              id: pendingRow
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              spacing: Style.space(8)

              Text {
                width: parent.width - keepButton.width - revertButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: "Keep these settings? Reverting in " + DisplayStore.secondsLeft + "s"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Button {
                id: keepButton
                text: "Keep"
                bordered: true
                selected: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: DisplayStore.keep()
              }

              Button {
                id: revertButton
                text: "Revert"
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: DisplayStore.revert()
              }
            }
          }

          Item {
            width: parent.width
            height: forgetButton.implicitHeight
            visible: !DisplayStore.hasPending

            Button {
              id: forgetButton
              text: "Forget saved layout"
              tooltipText: "Remove this panel's block from monitors.lua and reload Hyprland"
              fontSize: Style.font.caption
              foreground: Qt.darker(root.bar.foreground, 1.4)
              fontFamily: root.bar.fontFamily
              anchors.right: parent.right
              onClicked: DisplayStore.forgetSaved()
            }
          }
        }
      }
    }
  }
}
