// Presentation helpers for the Ferret result list: what glyph a file gets,
// how its path reads, and how its size and age are written out.
//
// Glyphs are Nerd Font (Material Design plane), which JetBrainsMono Nerd Font
// -- the shell's default monospace -- covers in full.

.pragma library

// Written as codepoints rather than literal Private Use Area characters so the
// file stays readable in any editor and greppable in any terminal.
var GLYPH = {
  folder:  String.fromCodePoint(0xF024B),
  file:    String.fromCodePoint(0xF0214),
  pdf:     String.fromCodePoint(0xF0226),
  image:   String.fromCodePoint(0xF02E9),
  video:   String.fromCodePoint(0xF0567),
  audio:   String.fromCodePoint(0xF0387),
  archive: String.fromCodePoint(0xF05C0),
  code:    String.fromCodePoint(0xF0174),
  doc:     String.fromCodePoint(0xF0219),
  sheet:   String.fromCodePoint(0xF021B),
  slides:  String.fromCodePoint(0xF0227),
  text:    String.fromCodePoint(0xF0219),
  config:  String.fromCodePoint(0xF0493),
  font:    String.fromCodePoint(0xF031A),
  disk:    String.fromCodePoint(0xF02CA),
  search:  String.fromCodePoint(0xF0349),
  empty:   String.fromCodePoint(0xF0209),
}

var BY_EXT = {
  pdf: "pdf",

  png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image",
  svg: "image", bmp: "image", ico: "image", tiff: "image", avif: "image",
  heic: "image", raw: "image", psd: "image", xcf: "image",

  mp4: "video", mkv: "video", avi: "video", mov: "video", webm: "video",
  wmv: "video", flv: "video", m4v: "video", mpg: "video", mpeg: "video",

  mp3: "audio", flac: "audio", wav: "audio", ogg: "audio", m4a: "audio",
  aac: "audio", opus: "audio", wma: "audio", mid: "audio",

  zip: "archive", tar: "archive", gz: "archive", bz2: "archive", xz: "archive",
  "7z": "archive", rar: "archive", zst: "archive", tgz: "archive", iso: "disk",
  img: "disk", qcow2: "disk", vdi: "disk",

  js: "code", ts: "code", jsx: "code", tsx: "code", py: "code", rb: "code",
  go: "code", rs: "code", c: "code", h: "code", cpp: "code", hpp: "code",
  cc: "code", cs: "code", java: "code", kt: "code", swift: "code",
  php: "code", lua: "code", sh: "code", bash: "code", zsh: "code",
  fish: "code", vim: "code", el: "code", qml: "code", html: "code",
  css: "code", scss: "code", sql: "code", pl: "code", r: "code",

  json: "config", yaml: "config", yml: "config", toml: "config",
  ini: "config", conf: "config", cfg: "config", xml: "config",
  env: "config", lock: "config", desktop: "config",

  doc: "doc", docx: "doc", odt: "doc", rtf: "doc", pages: "doc",
  xls: "sheet", xlsx: "sheet", ods: "sheet", csv: "sheet", tsv: "sheet",
  ppt: "slides", pptx: "slides", odp: "slides", key: "slides",

  txt: "text", md: "text", markdown: "text", org: "text", rst: "text",
  log: "text", nfo: "text",

  ttf: "font", otf: "font", woff: "font", woff2: "font",
}

function glyphFor(entry) {
  if (!entry) return GLYPH.file
  if (entry.isDir) return GLYPH.folder
  var key = BY_EXT[String(entry.ext || "").toLowerCase()]
  return GLYPH[key] || GLYPH.file
}

// Home-relative paths are shorter and read the way people think about their
// own files. Anything outside $HOME keeps its absolute path.
function prettyDir(dir, home) {
  var text = String(dir || "")
  if (home && text === home) return "~"
  if (home && text.indexOf(home + "/") === 0) return "~" + text.slice(home.length)
  return text
}

function formatSize(bytes) {
  var n = Number(bytes) || 0
  if (n <= 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (i === 0 ? n.toFixed(0) : n.toFixed(n < 10 ? 1 : 0)) + " " + units[i]
}

// Coarse on purpose: "when roughly" is what matters when picking between two
// files with the same name, and a coarse label never needs a live clock.
function formatAge(mtime) {
  var seconds = Math.floor(Date.now() / 1000) - (Number(mtime) || 0)
  if (seconds < 0) return ""
  var minutes = Math.floor(seconds / 60)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d ago"
  if (days < 30) return Math.floor(days / 7) + "w ago"
  if (days < 365) return Math.floor(days / 30) + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

// The result line's right-hand column: size and age, whichever exist.
function metaFor(entry) {
  if (!entry) return ""
  var parts = []
  if (!entry.isDir) {
    var size = formatSize(entry.size)
    if (size) parts.push(size)
  }
  var age = formatAge(entry.mtime)
  if (age) parts.push(age)
  return parts.join("  ·  ")
}

function parseResults(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    return Array.isArray(parsed) ? parsed : []
  } catch (e) {
    return []
  }
}
