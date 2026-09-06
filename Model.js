var ACTUATION_MIN = 0.1
var ACTUATION_MAX = 3.4
var RT_TRAVEL_MIN = 0.01
var RT_TRAVEL_MAX = 2.0
var UDEV_HINT = "requires helper / unknown opcode"

function emptyStatus() {
  return {
    ok: false,
    connected: false,
    link: "none",
    vid: "0x3151",
    pid: null,
    path: null,
    name: "",
    battery: null,
    charging: false,
    protocol: "none",
    writeSupported: false,
    writeVia: null,
    actuationMm: 1.5,
    rtOn: false,
    rtTravelMm: 0.3,
    snapOn: false,
    error: ""
  }
}

function parseJson(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var parsed = JSON.parse(text)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (e) {
    return null
  }
}

function applyStatus(target, parsed) {
  var d = parsed && parsed.ok !== undefined ? parsed : emptyStatus()
  target.connected = d.connected === true
  target.link = String(d.link || "none")
  target.vid = String(d.vid || "0x3151")
  target.pid = d.pid ? String(d.pid) : ""
  target.devicePath = d.path ? String(d.path) : ""
  target.deviceName = String(d.name || "")
  target.battery = d.battery === null || d.battery === undefined ? -1 : Number(d.battery)
  target.charging = d.charging === true
  target.protocol = String(d.protocol || "none")
  target.writeSupported = d.writeSupported === true
  target.writeVia = String(d.writeVia || "")
  if (d.actuationMm !== null && d.actuationMm !== undefined) target.actuationMm = Number(d.actuationMm)
  if (d.rtOn === true || d.rtOn === false) target.rtOn = d.rtOn === true
  if (d.rtTravelMm !== null && d.rtTravelMm !== undefined) target.rtTravelMm = Number(d.rtTravelMm)
  if (d.snapOn === true || d.snapOn === false) target.snapOn = d.snapOn === true
  target.lastError = d.ok === false ? String(d.error || d.hint || "") : String(d.hint || "")
}

function clamp(value, lo, hi, fallback) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  if (n < lo) n = lo
  if (n > hi) n = hi
  return Math.round(n * 100) / 100
}

function linkLabel(link) {
  if (link === "wired") return "USB"
  if (link === "2.4g") return "2.4G"
  if (link === "bt") return "BT"
  return "none"
}

function barLabel(connected, link, battery) {
  if (!connected) return "—"
  var mode = linkLabel(link)
  if (battery >= 0 && battery <= 100) return mode + " " + battery + "%"
  return mode
}

function heroMeta(connected, link, battery, charging) {
  if (!connected) return "No FUN60 Ultra"
  var parts = [linkLabel(link)]
  if (battery >= 0 && battery <= 100) parts.push(battery + "%" + (charging ? " charging" : ""))
  return parts.join(" · ")
}

function deviceLine(vid, pid, protocol) {
  var id = pid ? (vid + ":" + pid) : vid
  return id + " · " + (protocol === "ry5088" ? "RY5088 HID" : "protocol unknown")
}

function fileFromUrl(url) {
  var s = String(url || "")
  if (s.indexOf("file://") === 0) s = decodeURIComponent(s.substring(7))
  return s
}

function profileName(value) {
  var text = String(value || "").replace(/^\s+|\s+$/g, "")
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(text)) return ""
  return text
}

function elide(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  if (value.length <= max) return value
  return value.substring(0, Math.max(0, max - 1)) + "…"
}
