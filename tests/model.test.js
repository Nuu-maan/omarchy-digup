// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const mod = { exports: {} }
new Function("module", src)(mod)
const M = mod.exports

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) } catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}

test("parseQuery routes code: to the code index", () => {
  assert.deepStrictEqual(M.parseQuery("  Code:  retry with backoff "), { q: "retry with backoff", code: true })
  assert.deepStrictEqual(M.parseQuery("a dog on the beach"), { q: "a dog on the beach", code: false })
  assert.deepStrictEqual(M.parseQuery("decode: x"), { q: "decode: x", code: false })
})

test("formatTime pads seconds and adds hours only when needed", () => {
  assert.strictEqual(M.formatTime(42), "0:42")
  assert.strictEqual(M.formatTime(475.9), "7:55")
  assert.strictEqual(M.formatTime(3723), "1:02:03")
})

test("formatSize and formatCount", () => {
  assert.strictEqual(M.formatSize(196000), "196 KB")
  assert.strictEqual(M.formatSize(88800000), "88.8 MB")
  assert.strictEqual(M.formatSize(512), "512 B")
  assert.strictEqual(M.formatCount(2140), "2,140")
})

test("locLabel per segment", () => {
  assert.strictEqual(M.locLabel({ segment: "frame", loc: 42 }), "0:42")
  assert.strictEqual(M.locLabel({ segment: "page", loc: 4 }), "p. 4")
  assert.strictEqual(M.locLabel({ segment: "lines", loc: 1, loc_end: 47 }), "L1–47")
  assert.strictEqual(M.locLabel({ segment: "image" }), "")
})

test("reason says why it matched, and keyword hits say so", () => {
  assert.strictEqual(M.reason({ segment: "audio", loc: 475, z: 3 }), "Matches what's heard at 7:55")
  assert.strictEqual(M.reason({ segment: "page", loc: 4, z: 2.5 }), "Matches the text on page 4")
  assert.strictEqual(M.reason({ segment: "page", loc: 4, keyword_rank: 1 }), "Has your words")
  assert.strictEqual(M.reason({ segment: "name", z: 2 }), "Matches the file name")
})

test("groupHits groups by first appearance and folds weaker matches", () => {
  const hits = [
    { kind: "video", path: "a" }, { kind: "image", path: "b" }, { kind: "video", path: "c" },
    { kind: "pdf", path: "d" }, { kind: "doc", path: "e" }
  ]
  const folded = M.groupHits(hits, 3, false)
  assert.deepStrictEqual(folded.rows.map(r => r.group + ":" + r.hit.path), ["Video:a", "Video:c", "Images:b"])
  assert.strictEqual(folded.hidden, 2)
  const all = M.groupHits(hits, 3, true)
  assert.strictEqual(all.rows.length, 5)
  assert.strictEqual(all.rows[4].group, "Documents")
  assert.strictEqual(all.hidden, 0)
})

test("highlight escapes html and marks query words", () => {
  const html = M.highlight("Pets <b>allowed</b> under this clause", "pets clause", "#ff0")
  assert.ok(html.includes("&lt;b&gt;"))
  assert.ok(html.includes("<span style=\"background-color:#ff0\">Pets</span>"))
  assert.ok(html.includes(">clause</span>"))
})

test("excerptHtml turns DigUp's «marks» into highlights", () => {
  assert.strictEqual(M.excerptHtml("…not «pets» under <this>", "#ff0"), "…not <span style=\"background-color:#ff0\">pets</span> under &lt;this&gt;")
})

test("openLoc goes to the defining line for code and the page for pdfs", () => {
  assert.strictEqual(M.openLoc({ kind: "code", loc: 1, loc_end: 47, focus: 8 }), 8)
  assert.strictEqual(M.openLoc({ kind: "pdf", loc: 4 }), 4)
  assert.strictEqual(M.openLoc({ kind: "video", loc: 42.7 }), 42)
  assert.strictEqual(M.openLoc({ kind: "image" }), 0)
})

test("statusText per phase", () => {
  assert.strictEqual(M.statusText({ phase: "ready", searchable: 2140 }), "2,140 files")
  assert.strictEqual(M.statusText({ phase: "indexing", searchable: 312, total: 2140 }), "Reading files · 312 of 2,140")
  assert.strictEqual(M.statusText({ phase: "downloading", downloadedBytes: 432, totalBytes: 865 }), "Downloading the model · 49%")
})

test("readConfig expands ~ and falls back to defaults", () => {
  assert.deepStrictEqual(M.readConfig("not json", "/h").folders, ["/h/Documents", "/h/Pictures"])
  assert.deepStrictEqual(M.readConfig('{"folders":["~/a","/b"],"code":["~/src"]}', "/h"), { folders: ["/h/a", "/b"], code: ["/h/src"] })
})

test("folderOf shortens home", () => {
  assert.strictEqual(M.folderOf("/home/n/Documents/Home/Lease.pdf", "/home/n"), "~/Documents/Home")
  assert.strictEqual(M.folderOf("/srv/x.txt", "/home/n"), "/srv")
})

process.exit(failed ? 1 : 0)
