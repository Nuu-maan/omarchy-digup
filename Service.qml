import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Model.js" as Model

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: Model.localPath(Qt.resolvedUrl("."))
  readonly property string digup: pluginDir + "/bin/digup"
  readonly property string opener: pluginDir + "/bin/digup-open"
  readonly property string installer: pluginDir + "/bin/install-helper"
  readonly property string configPath: home + "/.config/omarchy/digup.json"

  property var folders: []
  property var codeFolders: []
  readonly property bool codeEnabled: codeFolders.length > 0

  property bool helperMissing: false
  property real downloadedBytes: 0
  property real totalBytes: 0
  property int searchable: 0
  property int pending: 0
  readonly property bool onBattery: UPower.onBattery

  readonly property string phase: {
    if (helperMissing) return "missing"
    if (downloader.running) return "downloading"
    if (onBattery && pending > 0) return "waiting"
    if (indexer.running && pending > 0) return "indexing"
    return searcher.running ? "ready" : "starting"
  }
  readonly property string status: Model.statusText(root)

  property int _nextId: 1
  property var _callbacks: ({})
  property string _configKey: ""
  property bool _needsModel: false
  property bool _dirty: false
  property bool _restartSearcher: false
  property bool _restartIndexer: false

  function search(text, meaning, callback) {
    var query = Model.parseQuery(text)
    return request("search", { q: query.q, code: query.code, meaning: meaning, prefix_last: !meaning, limit: 40 }, callback)
  }

  function embedAhead(text) {
    var query = Model.parseQuery(text)
    if (query.q) request("embed_ahead", { q: query.q, code: query.code })
  }

  function render(hit, pixels, callback) {
    var kind = Model.renderKind(hit)
    if (!kind) return 0
    return request("render", { path: hit.path, kind: kind, loc: Model.renderLoc(hit), pixels: pixels }, callback)
  }

  function text(hit, callback) {
    return request("text", { segment: hit.segment_id, code: hit.kind === "code" }, callback)
  }

  function prewarm() {
    request("prewarm", {})
  }

  function act(action, hit) {
    Quickshell.execDetached([root.opener, action, hit.path, hit.kind, String(Model.openLoc(hit))])
  }

  function request(op, fields, callback) {
    if (!searcher.running) {
      if (callback) callback(null)
      return 0
    }
    var id = root._nextId++
    var message = fields || {}
    message.id = id
    message.op = op
    if (callback) root._callbacks[id] = callback
    searcher.write(JSON.stringify(message) + "\n")
    return id
  }

  function applyConfig(raw) {
    var config = Model.readConfig(raw, root.home)
    var key = JSON.stringify(config)
    if (key === root._configKey) return
    root._configKey = key
    root.folders = config.folders
    root.codeFolders = config.code
    root.restart()
  }

  function restart() {
    if (searcher.running) {
      root._restartSearcher = true
      searcher.running = false
    } else {
      searcher.running = true
    }
    if (indexer.running) {
      root._restartIndexer = true
      indexer.running = false
    } else {
      root.startIndexing()
    }
  }

  function startIndexing() {
    if (root.helperMissing || downloader.running) return
    if (indexer.running) indexer.write("sync\n")
    else indexer.running = true
  }

  function refreshCounts() {
    request("status", {}, function(reply) {
      if (!reply || reply.pending === undefined) return
      root.searchable = reply.searchable
      root.pending = reply.pending
    })
  }

  function codeArgs() {
    var args = []
    for (var i = 0; i < root.codeFolders.length; i++) args.push("--code-root", root.codeFolders[i])
    return args
  }

  function parse(line) {
    try { return JSON.parse(line) } catch (e) { return null }
  }

  function handleReply(line) {
    var reply = root.parse(line)
    if (!reply) return
    if (reply.event === "ready") {
      root.helperMissing = false
      root.refreshCounts()
      return
    }
    var callback = root._callbacks[reply.id]
    if (!callback) return
    delete root._callbacks[reply.id]
    callback(reply)
  }

  function handleIndexEvent(line) {
    var event = root.parse(line)
    if (!event) return
    if (event.searchable !== undefined) {
      root.searchable = event.searchable
      root.pending = event.pending
    }
    if (event.event === "file") {
      root.pending = Math.max(0, root.pending - 1)
      if (event.state === "done" || event.state === "partial") root.searchable++
      root._dirty = true
    } else if (event.event === "waiting") {
      root._needsModel = true
    } else if (event.event === "error") {
      console.warn("digup index:", event.message)
    }
  }

  function indexingFinished() {
    if (root._needsModel) {
      root._needsModel = false
      downloader.running = true
      return
    }
    request("reload", {})
    root.refreshCounts()
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: {
      var defaults = { folders: ["~/Documents", "~/Pictures"], code: [] }
      setText(JSON.stringify(defaults, null, 2) + "\n")
      root.applyConfig(JSON.stringify(defaults))
    }
    onFileChanged: reload()
  }

  Process {
    id: searcher
    stdinEnabled: true
    command: [root.digup, "search-service"].concat(root.folders, root.codeArgs())
    stdout: SplitParser { onRead: function(line) { root.handleReply(line) } }
    onExited: function(exitCode) {
      root._callbacks = ({})
      if (root._restartSearcher) {
        root._restartSearcher = false
        searcher.running = true
      } else if (exitCode === 127) {
        root.helperMissing = true
      } else {
        searcherRestart.restart()
      }
    }
  }

  onOnBatteryChanged: {
    if (indexer.running) indexer.write(onBattery ? "backfill off\n" : "backfill on\n")
    else if (!onBattery) startIndexing()
  }

  Process {
    id: indexer
    stdinEnabled: true
    command: [root.digup, "index-service"].concat(root.folders, root.codeArgs(), ["--prune"], root.onBattery ? [] : ["--backfill"])
    stdout: SplitParser { onRead: function(line) { root.handleIndexEvent(line) } }
    onExited: {
      if (root._restartIndexer) {
        root._restartIndexer = false
        root.startIndexing()
      } else {
        root.indexingFinished()
      }
    }
  }

  Process {
    id: downloader
    command: [root.digup, "download-model"]
    stdout: SplitParser {
      onRead: function(line) {
        var event = root.parse(line)
        if (!event || event.all_total === undefined) return
        root.downloadedBytes = event.all_bytes
        root.totalBytes = event.all_total
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.restart()
    }
  }

  Timer {
    id: searcherRestart
    interval: 3000
    onTriggered: if (!root.helperMissing) searcher.running = true
  }

  Timer {
    interval: 5000
    repeat: true
    running: indexer.running
    onTriggered: {
      if (!root._dirty) return
      root._dirty = false
      root.request("reload", {})
    }
  }

  // ponytail: polls folders every 10 min; an inotify watcher would make new files searchable within seconds.
  Timer {
    interval: 10 * 60 * 1000
    repeat: true
    running: root._configKey !== ""
    onTriggered: root.startIndexing()
  }
}
