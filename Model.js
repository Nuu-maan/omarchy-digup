.pragma library

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var GROUPS = {
  screenshot: "images",
  image: "images",
  video: "video",
  audio: "audio",
  pdf: "documents",
  doc: "documents",
  code: "code"
}

var GROUP_LABELS = {
  images: "Images",
  video: "Video",
  audio: "Audio",
  documents: "Documents",
  code: "Code"
}

var KIND_LABELS = {
  screenshot: "Screenshot",
  image: "Image",
  video: "Video",
  audio: "Audio",
  pdf: "PDF",
  doc: "Document",
  code: "Code"
}

var GLYPHS = {
  screenshot: "\u{F0E51}",
  image: "\u{F02E9}",
  video: "\u{F0567}",
  audio: "\u{F075A}",
  pdf: "\u{F0226}",
  doc: "\u{F0219}",
  code: "\u{F0169}"
}

var RENDERABLE = { screenshot: "image", image: "image", video: "video", pdf: "pdf" }

function parseQuery(text) {
  var raw = String(text || "")
  var match = raw.match(/^\s*code:\s*/i)
  if (match) return { q: raw.slice(match[0].length).trim(), code: true }
  return { q: raw.trim(), code: false }
}

function formatTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var ss = s < 10 ? "0" + s : String(s)
  if (h > 0) return h + ":" + (m < 10 ? "0" + m : m) + ":" + ss
  return m + ":" + ss
}

function formatCount(n) {
  return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function formatSize(bytes) {
  var n = Number(bytes) || 0
  if (n < 1000) return n + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var i = -1
  do { n /= 1000; i++ } while (n >= 1000 && i < units.length - 1)
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

function formatDate(epochSeconds) {
  var d = new Date((Number(epochSeconds) || 0) * 1000)
  return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}

function fileName(path) {
  var p = String(path || "")
  return p.slice(p.lastIndexOf("/") + 1)
}

function folderOf(path, home) {
  var p = String(path || "")
  var dir = p.slice(0, Math.max(0, p.lastIndexOf("/"))) || "/"
  if (home && (dir === home || dir.indexOf(home + "/") === 0)) return "~" + dir.slice(home.length)
  return dir
}

function lineRange(hit) {
  var start = Math.round(hit.loc)
  var end = hit.loc_end !== undefined ? Math.round(hit.loc_end) : start
  return end > start ? start + "–" + end : String(start)
}

function locLabel(hit) {
  if (hit.loc === undefined || hit.loc === null) return ""
  switch (hit.segment) {
  case "frame":
  case "audio":
    return formatTime(hit.loc)
  case "page":
  case "page_image":
    return "p. " + Math.round(hit.loc)
  case "lines":
    return "L" + lineRange(hit)
  case "cells":
    return "cells " + lineRange(hit)
  default:
    return ""
  }
}

function reason(hit) {
  var meaning = hit.z !== undefined && hit.z !== null
  if (hit.segment === "name") return "Matches the file name"
  if (!meaning) return "Has your words"
  switch (hit.segment) {
  case "image": return "Matches the picture"
  case "ocr": return "Matches the text in it"
  case "frame": return "Matches the frame at " + formatTime(hit.loc)
  case "audio": return "Matches what's heard at " + formatTime(hit.loc)
  case "page": return "Matches the text on page " + Math.round(hit.loc)
  case "page_image": return "Matches page " + Math.round(hit.loc)
  case "chunk": return "Matches this passage"
  case "lines": return "Matches lines " + lineRange(hit)
  case "cells": return "Matches cells " + lineRange(hit)
  default: return "Matches what you described"
  }
}

function metaLine(hit) {
  var info = hit.info || {}
  var parts = [KIND_LABELS[hit.kind] || "File", formatDate(hit.modified)]
  if (info.pages) parts.push(info.pages + (Number(info.pages) === 1 ? " page" : " pages"))
  if (info.duration) parts.push(formatTime(info.duration))
  if (info.width && info.height) parts.push(info.width + " × " + info.height)
  parts.push(formatSize(hit.size))
  return parts.join(" · ")
}

function renderKind(hit) {
  if (hit.kind === "pdf") return hit.segment === "page" || hit.segment === "page_image" ? "pdf" : ""
  return RENDERABLE[hit.kind] || ""
}

function renderLoc(hit) {
  if (hit.kind === "pdf") return Math.max(1, Math.round(hit.loc || 1))
  if (hit.kind === "video") return Number(hit.loc) || 0
  return 0
}

function openLoc(hit) {
  if (hit.kind === "code") return Math.round(hit.focus !== undefined ? hit.focus : (hit.loc || 1))
  if (hit.loc === undefined || hit.loc === null) return 0
  return hit.kind === "pdf" ? Math.round(hit.loc) : Math.floor(hit.loc)
}

function groupHits(hits, strong, showWeaker) {
  var list = Array.isArray(hits) ? hits : []
  var limit = showWeaker ? list.length : Math.min(list.length, Math.max(0, strong))
  var order = []
  var byGroup = {}
  for (var i = 0; i < limit; i++) {
    var group = GROUPS[list[i].kind] || "documents"
    if (!byGroup[group]) { byGroup[group] = []; order.push(group) }
    byGroup[group].push(list[i])
  }
  var rows = []
  for (var g = 0; g < order.length; g++) {
    var items = byGroup[order[g]]
    for (var j = 0; j < items.length; j++) rows.push({ group: GROUP_LABELS[order[g]], hit: items[j] })
  }
  return { rows: rows, hidden: list.length - limit }
}

function escapeHtml(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function queryWords(q) {
  return String(q || "").toLowerCase().split(/[\s.,;:!?'"()[\]{}<>\/\\|`~@#$%^&*+=-]+/).filter(function(w) { return w.length > 2 })
}

function highlight(text, q, color) {
  var html = escapeHtml(text)
  var words = queryWords(q)
  if (words.length === 0) return html
  var pattern = new RegExp("(" + words.map(function(w) { return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }).join("|") + ")", "gi")
  return html.replace(pattern, "<span style=\"background-color:" + color + "\">$1</span>")
}

function excerptHtml(excerpt, color) {
  return escapeHtml(excerpt).replace(/«([^»]*)»/g, "<span style=\"background-color:" + color + "\">$1</span>")
}

function statusText(s) {
  switch (s.phase) {
  case "missing": return "DigUp's engine isn't installed"
  case "downloading":
    return s.totalBytes > 0
      ? "Downloading the model · " + Math.floor(100 * s.downloadedBytes / s.totalBytes) + "%"
      : "Downloading the model"
  case "indexing":
    return s.total > 0
      ? "Reading files · " + formatCount(s.searchable) + " of " + formatCount(s.total)
      : "Looking through your folders"
  case "ready": return formatCount(s.searchable) + (s.searchable === 1 ? " file" : " files")
  default: return "Starting"
  }
}

function expandHome(path, home) {
  var p = String(path || "")
  if (p === "~") return home
  return p.indexOf("~/") === 0 ? home + p.slice(1) : p
}

function readConfig(raw, home) {
  var defaults = ["~/Documents", "~/Pictures"]
  var parsed = {}
  try { parsed = JSON.parse(raw || "{}") || {} } catch (e) { parsed = {} }
  var folders = Array.isArray(parsed.folders) ? parsed.folders : defaults
  var code = Array.isArray(parsed.code) ? parsed.code : []
  var expand = function(p) { return expandHome(p, home) }
  return { folders: folders.map(expand), code: code.map(expand) }
}

function localPath(url) {
  return decodeURIComponent(String(url || "").replace(/^file:\/\//, "")).replace(/\/$/, "")
}

if (typeof module !== "undefined") {
  module.exports = {
    GLYPHS: GLYPHS, parseQuery: parseQuery, formatTime: formatTime, formatCount: formatCount,
    formatSize: formatSize, formatDate: formatDate, fileName: fileName, folderOf: folderOf,
    locLabel: locLabel, reason: reason, metaLine: metaLine, renderKind: renderKind, renderLoc: renderLoc,
    openLoc: openLoc, groupHits: groupHits, escapeHtml: escapeHtml, highlight: highlight, excerptHtml: excerptHtml,
    statusText: statusText, expandHome: expandHome, readConfig: readConfig, localPath: localPath
  }
}
