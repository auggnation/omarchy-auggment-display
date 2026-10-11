pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Shared state for the bar popup and the arrangement window. Every
// hl.monitor change is applied live through `hyprctl eval` and reverted
// after revertSeconds unless kept. Keep writes the whole layout into a
// managed block in ~/.config/hypr/monitors.lua.
Item {
  id: store

  readonly property string pluginId: "io.github.auggnation.auggment-display"
  readonly property int revertSeconds: 15
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property string luaScript: Qt.resolvedUrl("monitors-lua.sh").toString().replace(/^file:\/\//, "")

  property var displays: []
  // name -> { hdr, range } from the monitor's EDID.
  property var edid: ({})
  property string selectedName: ""
  // name -> { before, after } for displays with an unconfirmed live change.
  property var pending: ({})
  property int secondsLeft: 0

  readonly property var selected: {
    for (var i = 0; i < displays.length; i++)
      if (displays[i].name === selectedName) return displays[i]
    return null
  }
  readonly property bool hasPending: Object.keys(pending).length > 0
  readonly property int enabledCount: {
    var n = 0
    for (var i = 0; i < displays.length; i++) if (displays[i].enabled) n++
    return n
  }

  // The unconfirmed change if there is one, otherwise what Hyprland reports.
  function settingsFor(display) {
    var p = pending[display.name]
    return p ? p.after : Model.settingsFromDisplay(display)
  }
  readonly property var current: selected ? settingsFor(selected) : null
  readonly property var selectedEdid: (selected && edid[selected.name]) || { hdr: false, range: "" }

  // Enabled, non-mirrored displays with a real position, in logical pixels.
  readonly property var layoutRects: {
    var rects = []
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      var s = settingsFor(d)
      if (s.disabled || s.mirror) continue
      var rect = Model.logicalRect(s)
      if (rect) rects.push({ name: d.name, model: d.model, settings: s, x: rect.x, y: rect.y, w: rect.w, h: rect.h })
    }
    return rects
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function select(name) {
    selectedName = name
  }

  function change(patch) {
    if (!selected) return
    var name = selected.name
    var existing = pending[name]
    var before = existing ? existing.before : Model.settingsFromDisplay(selected)
    var after = Object.assign({}, existing ? existing.after : Model.settingsFromDisplay(selected), patch)
    after.scale = Model.cleanScale(after.scale, after.width, after.height) || after.scale

    var next = Object.assign({}, pending)
    next[name] = { before: before, after: after }
    pending = next
    secondsLeft = revertSeconds
    runLua(Model.luaLine(after))
  }

  function setEnabled(display, enabled) {
    if (!enabled && display.enabled && enabledCount <= 1) return
    select(display.name)
    change({ disabled: !enabled })
  }

  function setResolution(value) {
    var parts = value.split("x")
    var width = Number(parts[0])
    var height = Number(parts[1])
    var rates = Model.refreshRates(selected.modes, width, height)
    change({ width: width, height: height, hz: rates.length ? Number(rates[0].value) : current.hz })
  }

  function moveDisplay(name, x, y) {
    var moving = null
    var others = []
    for (var i = 0; i < layoutRects.length; i++) {
      if (layoutRects[i].name === name) moving = Object.assign({}, layoutRects[i], { x: x, y: y })
      else others.push(layoutRects[i])
    }
    if (!moving) return
    var snapped = Model.snapPosition(moving, others, 60)
    select(name)
    change({ position: snapped.x + "x" + snapped.y })
  }

  function keep() {
    var lines = []
    for (var i = 0; i < displays.length; i++) lines.push(Model.luaLine(settingsFor(displays[i])))
    pending = {}
    luaFileProc.command = ["bash", "-c", "printf '%s\\n' \"$1\" | \"$0\" write", store.luaScript, lines.join("\n")]
    luaFileProc.running = true
  }

  function revert() {
    var lines = []
    for (var name in pending) lines.push(Model.luaLine(pending[name].before))
    pending = {}
    if (lines.length) runLua(lines.join("\n"))
  }

  function forgetSaved() {
    pending = {}
    luaFileProc.command = ["bash", "-c", "\"$0\" remove && hyprctl reload", store.luaScript]
    luaFileProc.running = true
  }

  function runLua(code) {
    evalProc.command = ["hyprctl", "eval", code]
    evalProc.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1000
    running: store.hasPending
    repeat: true
    onTriggered: {
      store.secondsLeft = store.secondsLeft - 1
      if (store.secondsLeft <= 0) store.revert()
    }
  }

  Process {
    id: stateProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        store.displays = Model.parseMonitors(text)
        if (!edidProc.running) edidProc.running = true
        var names = store.displays.map(function(d) { return d.name })
        if (names.indexOf(store.selectedName) < 0) {
          var focused = store.displays.filter(function(d) { return d.focused })[0] || store.displays[0]
          store.selectedName = focused ? focused.name : ""
        }
      }
    }
  }

  // "name\thdr\tmin-max" per connected output, from the kernel's EDID copy.
  Process {
    id: edidProc
    command: ["bash", "-c", "for d in /sys/class/drm/card*-*/; do out=$(di-edid-decode \"$d/edid\" 2>/dev/null); [[ -n $out ]] || continue; base=${d%/}; base=${base##*/}; name=${base#*-}; hdr=0; grep -q 'HDR Static Metadata' <<<\"$out\" && hdr=1; range=$(grep -o -m1 '[0-9]*-[0-9]* Hz V' <<<\"$out\" | sed 's/ Hz V//'); printf '%s\\t%s\\t%s\\n' \"$name\" \"$hdr\" \"$range\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.edid = Model.parseEdid(text)
    }
  }

  Process {
    id: evalProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) store.refresh()
  }

  Process {
    id: luaFileProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) store.refresh()
  }
}
