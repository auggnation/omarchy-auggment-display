// Pure helpers for the display panel. No QML, no side effects, so node can test it.
// Scale helpers follow the same clean-scale rule as omarchy-hyprland-monitor-scaling.

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

// Hyprland only accepts scales where the mode divides into whole logical
// pixels in 1/120 steps. Round the requested scale up to the nearest clean value.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

// Presets collapsed to distinct clean scales for this mode, keeping the
// preset label closest to each effective value.
function availableScales(presets, width, height) {
  var byEffective = {}
  for (var i = 0; i < presets.length; i++) {
    var requested = Number(presets[i])
    var effective = cleanScale(requested, width, height)
    if (effective === "") continue
    var distance = Math.abs(requested - Number(effective))
    var existing = byEffective[effective]
    if (!existing || distance < existing.distance) {
      byEffective[effective] = { value: effective, index: i, distance: distance }
    }
  }
  return Object.keys(byEffective)
    .map(function(key) { return byEffective[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function parseMode(text) {
  var match = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(text || "").trim())
  if (!match) return null
  return {
    width: Number(match[1]),
    height: Number(match[2]),
    hz: Math.round(Number(match[3]) * 100) / 100
  }
}

function modeString(width, height, hz) {
  return width + "x" + height + "@" + Number(hz).toFixed(2)
}

function isInternal(name) {
  return /^(eDP|LVDS|DSI)-/.test(String(name || ""))
}

// hyprctl monitors all -j -> the display objects the panel renders.
function parseMonitors(raw) {
  var monitors = []
  try {
    monitors = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    monitors = []
  }
  if (!Array.isArray(monitors)) return []

  return monitors.map(function(m) {
    var seen = {}
    var modes = []
    var available = Array.isArray(m.availableModes) ? m.availableModes : []
    for (var i = 0; i < available.length; i++) {
      var mode = parseMode(available[i])
      if (!mode) continue
      var key = modeString(mode.width, mode.height, mode.hz)
      if (seen[key]) continue
      seen[key] = true
      modes.push(mode)
    }
    return {
      name: String(m.name || ""),
      description: String(m.description || ""),
      model: String(m.model || m.description || m.name || ""),
      internal: isInternal(m.name),
      enabled: m.disabled !== true,
      focused: m.focused === true,
      width: Number(m.width) || 0,
      height: Number(m.height) || 0,
      hz: Math.round((Number(m.refreshRate) || 0) * 100) / 100,
      scale: normalizeScale(m.scale) || "1",
      transform: Number(m.transform) || 0,
      x: Number(m.x) || 0,
      y: Number(m.y) || 0,
      mirrorOf: m.mirrorOf && m.mirrorOf !== "none" ? String(m.mirrorOf) : "",
      vrr: Number(m.vrr) || 0,
      hdr: String(m.colorManagementPreset || "").toLowerCase() === "hdr",
      modes: modes
    }
  })
}

// Distinct resolutions, largest first.
function resolutions(modes) {
  var seen = {}
  var list = []
  for (var i = 0; i < modes.length; i++) {
    var key = modes[i].width + "x" + modes[i].height
    if (seen[key]) continue
    seen[key] = true
    list.push({ value: key, label: modes[i].width + " × " + modes[i].height, width: modes[i].width, height: modes[i].height })
  }
  return list.sort(function(a, b) { return b.width * b.height - a.width * a.height })
}

// Refresh rates for one resolution, fastest first.
function refreshRates(modes, width, height) {
  var list = []
  for (var i = 0; i < modes.length; i++) {
    if (modes[i].width !== width || modes[i].height !== height) continue
    list.push({ value: Number(modes[i].hz).toFixed(2), label: Number(modes[i].hz).toFixed(2) + " Hz" })
  }
  return list.sort(function(a, b) { return Number(b.value) - Number(a.value) })
}

// The hl.monitor() table we apply and persist for one display. A disabled
// display reports no usable mode or position, so fall back to its first
// (preferred) mode and let Hyprland place it.
function settingsFromDisplay(d) {
  var first = d.modes[0] || { width: 0, height: 0, hz: 60 }
  var hasMode = d.width > 0 && d.height > 0 && d.hz > 0
  return {
    output: "desc:" + d.description,
    disabled: !d.enabled,
    width: hasMode ? d.width : first.width,
    height: hasMode ? d.height : first.height,
    hz: hasMode ? d.hz : first.hz,
    position: d.enabled ? d.x + "x" + d.y : "auto",
    scale: d.scale,
    transform: d.transform,
    mirror: d.mirrorOf,
    vrr: d.vrr,
    hdr: d.hdr
  }
}

function luaString(text) {
  return '"' + String(text).replace(/[\\"]/g, "\\$&").replace(/[\r\n]/g, " ") + '"'
}

// One hl.monitor({...}) call. Used verbatim for `hyprctl eval` and for monitors.lua.
function luaLine(s) {
  var fields = ["output = " + luaString(s.output)]
  if (s.disabled) {
    fields.push("disabled = true")
    return "hl.monitor({ " + fields.join(", ") + " })"
  }
  fields.push("mode = " + luaString(modeString(s.width, s.height, s.hz)))
  fields.push("position = " + luaString(s.position))
  fields.push("scale = " + s.scale)
  fields.push("transform = " + s.transform)
  if (s.mirror) fields.push("mirror = " + luaString(s.mirror))
  if (s.vrr) fields.push("vrr = " + s.vrr)
  if (s.hdr) fields.push("cm = \"hdr\", bitdepth = 10")
  return "hl.monitor({ " + fields.join(", ") + " })"
}

// Output of the edid script in Panel.qml: "name\thdr\tmin-max" per line.
function parseEdid(raw) {
  var byName = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2 || !parts[0]) continue
    byName[parts[0]] = { hdr: parts[1] === "1", range: parts[2] || "" }
  }
  return byName
}

function parsePosition(text) {
  var match = /^(-?\d+)x(-?\d+)$/.exec(String(text || ""))
  return match ? { x: Number(match[1]), y: Number(match[2]) } : null
}

// Logical rectangle Hyprland lays out: mode divided by scale, swapped when rotated.
function logicalRect(s) {
  var position = parsePosition(s.position)
  if (!position) return null
  var rotated = s.transform % 2 === 1
  var w = Math.round((rotated ? s.height : s.width) / Number(s.scale))
  var h = Math.round((rotated ? s.width : s.height) / Number(s.scale))
  return { x: position.x, y: position.y, w: w, h: h }
}

function bounds(rects) {
  if (!rects.length) return { x: 0, y: 0, w: 1, h: 1 }
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < rects.length; i++) {
    minX = Math.min(minX, rects[i].x)
    minY = Math.min(minY, rects[i].y)
    maxX = Math.max(maxX, rects[i].x + rects[i].w)
    maxY = Math.max(maxY, rects[i].y + rects[i].h)
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
}

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

function nearest(value, candidates, threshold) {
  var best = value
  var bestDistance = threshold
  for (var i = 0; i < candidates.length; i++) {
    var distance = Math.abs(candidates[i] - value)
    if (distance < bestDistance) { best = candidates[i]; bestDistance = distance }
  }
  return best
}

function projectionsOverlap(a, b) {
  return {
    x: a.x < b.x + b.w && b.x < a.x + a.w,
    y: a.y < b.y + b.h && b.y < a.y + a.h
  }
}

function touches(a, b) {
  var p = projectionsOverlap(a, b)
  var xTouch = a.x + a.w === b.x || b.x + b.w === a.x
  var yTouch = a.y + a.h === b.y || b.y + b.h === a.y
  return (xTouch && p.y) || (yTouch && p.x)
}

// Cheapest move that makes rect share an edge with other, so the cursor can
// always cross between displays. Diagonal gaps close sideways and align tops.
function closeGap(rect, other) {
  var p = projectionsOverlap(rect, other)
  var closedX = rect.x > other.x ? other.x + other.w : other.x - rect.w
  var closedY = rect.y > other.y ? other.y + other.h : other.y - rect.h
  var moves = []
  if (p.y) moves.push({ x: closedX, y: rect.y })
  if (p.x) moves.push({ x: rect.x, y: closedY })
  if (!p.x && !p.y) moves.push({ x: closedX, y: other.y }, { x: other.x, y: closedY })
  var best = null
  for (var i = 0; i < moves.length; i++) {
    var cost = Math.abs(moves[i].x - rect.x) + Math.abs(moves[i].y - rect.y)
    if (!best || cost < best.cost) best = { x: moves[i].x, y: moves[i].y, cost: cost }
  }
  return best
}

// Snap the dragged rect's edges to the others, push it out of any overlap
// along the shortest axis, then close any remaining gap. Returns a new {x, y}.
function snapPosition(moving, others, threshold) {
  var xs = [], ys = []
  for (var i = 0; i < others.length; i++) {
    var o = others[i]
    xs.push(o.x + o.w, o.x - moving.w, o.x, o.x + o.w - moving.w)
    ys.push(o.y + o.h, o.y - moving.h, o.y, o.y + o.h - moving.h)
  }
  var rect = { x: nearest(moving.x, xs, threshold), y: nearest(moving.y, ys, threshold), w: moving.w, h: moving.h }

  for (var pass = 0; pass < 8; pass++) {
    var pushed = false
    for (var j = 0; j < others.length; j++) {
      var other = others[j]
      if (!overlaps(rect, other)) continue
      var moves = [
        { x: other.x + other.w, y: rect.y },
        { x: other.x - rect.w, y: rect.y },
        { x: rect.x, y: other.y + other.h },
        { x: rect.x, y: other.y - rect.h }
      ]
      var best = null
      for (var k = 0; k < moves.length; k++) {
        var cost = Math.abs(moves[k].x - rect.x) + Math.abs(moves[k].y - rect.y)
        if (!best || cost < best.cost) best = { x: moves[k].x, y: moves[k].y, cost: cost }
      }
      rect.x = best.x
      rect.y = best.y
      pushed = true
    }
    if (!pushed) break
  }

  var touching = false
  for (var t = 0; t < others.length; t++) if (touches(rect, others[t])) touching = true
  if (!touching && others.length) {
    var closest = null
    for (var c = 0; c < others.length; c++) {
      var candidate = closeGap(rect, others[c])
      if (!closest || candidate.cost < closest.cost) closest = candidate
    }
    rect.x = closest.x
    rect.y = closest.y
  }
  return { x: Math.round(rect.x), y: Math.round(rect.y) }
}

function transformLabel(transform) {
  return ["0°", "90°", "180°", "270°"][Number(transform) % 4] || "0°"
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    availableScales: availableScales,
    parseMode: parseMode,
    modeString: modeString,
    parseMonitors: parseMonitors,
    resolutions: resolutions,
    refreshRates: refreshRates,
    settingsFromDisplay: settingsFromDisplay,
    luaLine: luaLine,
    parseEdid: parseEdid,
    parsePosition: parsePosition,
    logicalRect: logicalRect,
    bounds: bounds,
    snapPosition: snapPosition,
    transformLabel: transformLabel,
    brightnessName: brightnessName
  }
}
