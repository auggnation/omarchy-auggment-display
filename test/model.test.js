const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const hyprctl = JSON.stringify([
  {
    name: "eDP-1", description: "BOE NE135A1M-NY1", model: "NE135A1M-NY1", disabled: false, focused: true,
    width: 2880, height: 1920, refreshRate: 120.0, scale: 2, transform: 0, x: 0, y: 0,
    mirrorOf: "none", vrr: 0, colorManagementPreset: "srgb",
    availableModes: ["2880x1920@120.00Hz", "2880x1920@60.00Hz", "1920x1080@120.00Hz"]
  },
  {
    name: "DP-3", description: "Dell Inc. DELL S2718D 2HV50768133L", model: "DELL S2718D", disabled: false, focused: false,
    width: 2560, height: 1440, refreshRate: 59.951, scale: 1, transform: 1, x: 1440, y: -480,
    mirrorOf: "eDP-1", vrr: 1, colorManagementPreset: "hdr",
    availableModes: ["2560x1440@59.95Hz", "1920x1080@60.00Hz", "1920x1080@60.00Hz", "1920x1080@59.94Hz"]
  }
])

test("parseMonitors normalizes and dedupes modes", () => {
  const displays = Model.parseMonitors(hyprctl)
  assert.equal(displays.length, 2)
  const dell = displays[1]
  assert.equal(dell.hz, 59.95)
  assert.equal(dell.scale, "1")
  assert.equal(dell.mirrorOf, "eDP-1")
  assert.equal(dell.hdr, true)
  assert.equal(dell.internal, false)
  assert.equal(displays[0].internal, true)
  assert.deepEqual(dell.modes.map(m => Model.modeString(m.width, m.height, m.hz)),
    ["2560x1440@59.95", "1920x1080@60.00", "1920x1080@59.94"])
})

test("parseMonitors tolerates garbage", () => {
  assert.deepEqual(Model.parseMonitors("nope"), [])
  assert.deepEqual(Model.parseMonitors(""), [])
  assert.deepEqual(Model.parseMonitors("{}"), [])
})

test("resolutions and refreshRates", () => {
  const dell = Model.parseMonitors(hyprctl)[1]
  assert.deepEqual(Model.resolutions(dell.modes).map(r => r.value), ["2560x1440", "1920x1080"])
  assert.deepEqual(Model.refreshRates(dell.modes, 1920, 1080).map(r => r.value), ["60.00", "59.94"])
})

test("cleanScale rounds up to a clean divisor", () => {
  assert.equal(Model.cleanScale(1.6, 2880, 1920), "1.6")
  assert.equal(Model.cleanScale(1.25, 2560, 1440), "1.25")
  assert.equal(Model.cleanScale(3, 2560, 1440), "3.2")
  assert.equal(Model.cleanScale(1.25, 1366, 768), "2")
  assert.equal(Model.cleanScale("x", 2560, 1440), "")
})

test("availableScales collapses duplicates", () => {
  const presets = ["1", "1.25", "1.6", "2", "3", "4"]
  assert.deepEqual(Model.availableScales(presets, 2560, 1440), ["1", "1.25", "1.6", "2", "3.2", "4"])
})

test("luaLine renders a full display", () => {
  const displays = Model.parseMonitors(hyprctl)
  const dell = Model.settingsFromDisplay(displays[1])
  assert.equal(Model.luaLine(dell),
    'hl.monitor({ output = "desc:Dell Inc. DELL S2718D 2HV50768133L", mode = "2560x1440@59.95", position = "1440x-480", scale = 1, transform = 1, mirror = "eDP-1", vrr = 1, cm = "hdr", bitdepth = 10 })')
  const boe = Model.settingsFromDisplay(displays[0])
  assert.equal(Model.luaLine(boe),
    'hl.monitor({ output = "desc:BOE NE135A1M-NY1", mode = "2880x1920@120.00", position = "0x0", scale = 2, transform = 0 })')
})

test("luaLine renders a disabled display and escapes quotes", () => {
  const s = Model.settingsFromDisplay(Model.parseMonitors(hyprctl)[0])
  s.disabled = true
  s.output = 'desc:Evil "Monitor" \\ co'
  assert.equal(Model.luaLine(s), 'hl.monitor({ output = "desc:Evil \\"Monitor\\" \\\\ co", disabled = true })')
})

test("transformLabel", () => {
  assert.equal(Model.transformLabel(1), "90°")
  assert.equal(Model.transformLabel(5), "90°")
})

test("settingsFromDisplay falls back for a disabled display", () => {
  const raw = JSON.parse(hyprctl)
  raw[1].disabled = true; raw[1].width = 0; raw[1].height = 0; raw[1].refreshRate = 0
  const s = Model.settingsFromDisplay(Model.parseMonitors(JSON.stringify(raw))[1])
  assert.equal(s.disabled, true)
  assert.equal(s.position, "auto")
  s.disabled = false
  assert.match(Model.luaLine(s), /mode = "2560x1440@59.95", position = "auto"/)
})

test("parseEdid", () => {
  const edid = Model.parseEdid("eDP-1\t0\t30-120\nDP-3\t1\t\n\n")
  assert.deepEqual(edid["eDP-1"], { hdr: false, range: "30-120" })
  assert.deepEqual(edid["DP-3"], { hdr: true, range: "" })
})

test("logicalRect divides by scale and swaps when rotated", () => {
  assert.deepEqual(Model.logicalRect({ position: "1440x-480", width: 2880, height: 1920, scale: "2", transform: 0 }), { x: 1440, y: -480, w: 1440, h: 960 })
  assert.deepEqual(Model.logicalRect({ position: "0x0", width: 2560, height: 1440, scale: "1", transform: 1 }), { x: 0, y: 0, w: 1440, h: 2560 })
  assert.equal(Model.logicalRect({ position: "auto", width: 1, height: 1, scale: "1", transform: 0 }), null)
})

test("bounds", () => {
  assert.deepEqual(Model.bounds([{ x: 1440, y: -480, w: 2560, h: 1440 }, { x: 0, y: 0, w: 1440, h: 960 }]), { x: 0, y: -480, w: 4000, h: 1440 })
})

test("snapPosition snaps edges within threshold", () => {
  const laptop = { x: 0, y: 0, w: 1440, h: 960 }
  assert.deepEqual(Model.snapPosition({ x: 1470, y: 20, w: 2560, h: 1440 }, [laptop], 60), { x: 1440, y: 0 })
  assert.deepEqual(Model.snapPosition({ x: 1470, y: -500, w: 2560, h: 1440 }, [laptop], 60), { x: 1440, y: -480 })
  assert.deepEqual(Model.snapPosition({ x: 2000, y: 3000, w: 2560, h: 1440 }, [laptop], 60), { x: 1440, y: 0 })
})

test("snapPosition pushes out of overlap along the shortest axis", () => {
  const laptop = { x: 0, y: 0, w: 1440, h: 960 }
  assert.deepEqual(Model.snapPosition({ x: 1200, y: 200, w: 2560, h: 1440 }, [laptop], 10), { x: 1440, y: 200 })
  assert.deepEqual(Model.snapPosition({ x: -2400, y: 800, w: 2560, h: 1440 }, [laptop], 10), { x: -2560, y: 800 })
})

test("snapPosition closes gaps so displays always touch", () => {
  const dell = { x: 1440, y: -480, w: 2560, h: 1440 }
  assert.deepEqual(Model.snapPosition({ x: -185, y: -480, w: 1440, h: 960 }, [dell], 60), { x: 0, y: -480 })
  const laptop = { x: 0, y: 0, w: 1440, h: 960 }
  assert.deepEqual(Model.snapPosition({ x: 3000, y: 2000, w: 1440, h: 960 }, [laptop], 60), { x: 1440, y: 0 })
  assert.deepEqual(Model.snapPosition({ x: 100, y: 1500, w: 1440, h: 960 }, [laptop], 60), { x: 100, y: 960 })
})
