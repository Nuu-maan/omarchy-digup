import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var service
  property bool opened: false

  readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
  readonly property int fadeFast: 150

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color muted: Util.alpha(foreground, 0.6)
  readonly property color faint: Util.alpha(foreground, 0.4)
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color mark: Util.alpha(Color.accent, 0.35)
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  readonly property int padding: Style.spacing.panelPadding
  readonly property int cardRadius: Style.cornerRadius
  readonly property int innerRadius: Math.max(0, cardRadius - padding)
  readonly property int headerHeight: Math.max(Style.space(52), Style.font.display + Style.spacing.controlPaddingY * 2)
  readonly property int footerHeight: Math.max(Style.space(24), Style.font.caption + Style.spacing.sm * 2)
  readonly property int bodyHeight: Style.space(440)
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int thumbSize: rowHeight - Style.space(12)
  readonly property int thumbRadius: Math.max(0, innerRadius - Style.space(6))

  property string query: ""
  property int generation: 0
  property int meaningGeneration: -1
  property bool matchingMeaning: false
  property var hits: []
  property int strong: 0
  property int hidden: 0
  property bool showWeaker: false
  property bool answered: false
  property int selectedIndex: 0
  property var selectedHit: null
  property var thumbs: ({})
  property int thumbsVersion: 0
  property string previewImage: ""
  property string previewText: ""

  readonly property bool expanded: query.trim().length > 0 || service.phase === "missing"
  readonly property bool codeMode: Model.parseQuery(query).code
  readonly property string footerText: matchingMeaning ? "Matching meaning…" : service.status

  function open(payloadJson) {
    root.opened = true
    root.thumbs = ({})
    pointerGate.reset()
    input.selectAll()
    input.forceActiveFocus()
    var payload = Util.parseModuleJson(payloadJson)
    if (payload && typeof payload.query === "string") input.text = payload.query
    else if (root.query.trim()) root.runSearch()
    root.service.prewarm()
  }

  function close() {
    root.opened = false
  }

  function runSearch() {
    var gen = ++root.generation
    root.showWeaker = false
    meaningTimer.stop()
    if (!root.query.trim() || (root.codeMode && !root.service.codeEnabled)) {
      root.matchingMeaning = false
      root.answered = false
      root.setHits([], 0)
      return
    }
    root.service.search(root.query, false, function(reply) {
      if (reply && gen === root.generation && root.meaningGeneration !== gen) root.setHits(reply.hits, reply.strong)
    })
    root.service.embedAhead(root.query)
    root.matchingMeaning = true
    meaningTimer.restart()
  }

  function searchMeaning() {
    var gen = root.generation
    root.service.search(root.query, true, function(reply) {
      if (gen !== root.generation) return
      root.meaningGeneration = gen
      root.matchingMeaning = false
      root.answered = true
      if (reply) root.setHits(reply.hits, reply.strong)
    })
  }

  function setHits(hits, strong) {
    var current = root.selectedHit
    root.hits = hits || []
    root.strong = strong || 0
    root.rebuildRows(current ? current.path : "")
  }

  function rebuildRows(keepPath) {
    var grouped = Model.groupHits(root.hits, root.strong, root.showWeaker)
    root.hidden = grouped.hidden
    rows.clear()
    var keep = 0
    for (var i = 0; i < grouped.rows.length; i++) {
      var hit = grouped.rows[i].hit
      if (hit.path === keepPath) keep = i
      rows.append({
        group: grouped.rows[i].group,
        hitIndex: root.hits.indexOf(hit),
        isMore: false,
        name: Model.fileName(hit.path),
        folder: Model.folderOf(hit.path, root.service.home),
        loc: Model.locLabel(hit),
        glyph: Model.GLYPHS[hit.kind] || Model.GLYPHS.doc,
        thumbKey: Model.renderKind(hit) ? hit.path + "#" + Model.renderLoc(hit) : ""
      })
    }
    if (grouped.hidden > 0) {
      rows.append({
        group: grouped.rows.length ? grouped.rows[grouped.rows.length - 1].group : "",
        hitIndex: -1, isMore: true, name: "", folder: "", loc: "", glyph: "", thumbKey: ""
      })
    }
    root.setSelected(keep)
  }

  function select(delta) {
    if (rows.count === 0) return
    pointerGate.reset()
    root.setSelected((root.selectedIndex + delta + rows.count) % rows.count)
  }

  function setSelected(index) {
    var row = index < rows.count ? rows.get(index) : null
    root.selectedIndex = index
    root.selectedHit = row && !row.isMore ? root.hits[row.hitIndex] : null
    if (row) list.positionViewAtIndex(index, ListView.Contain)
    root.previewImage = ""
    root.previewText = ""
    previewTimer.restart()
  }

  function fetchPreview() {
    var hit = root.selectedHit
    if (!hit) return
    var key = hit.path + "#" + hit.segment_id
    if (Model.renderKind(hit)) {
      root.service.render(hit, Style.space(720), function(reply) {
        if (reply && reply.image && root.selectedHit && root.selectedHit.path + "#" + root.selectedHit.segment_id === key)
          root.previewImage = Util.fileUrl(reply.image)
      })
    } else if (hit.kind === "doc" || hit.kind === "code") {
      root.service.text(hit, function(reply) {
        if (reply && reply.text && root.selectedHit && root.selectedHit.path + "#" + root.selectedHit.segment_id === key)
          root.previewText = reply.text
      })
    }
  }

  function thumbFor(key, hitIndex) {
    if (!key) return ""
    if (root.thumbs[key] !== undefined) return root.thumbs[key]
    root.thumbs[key] = ""
    root.service.render(root.hits[hitIndex], Style.space(128), function(reply) {
      if (!reply || !reply.image) return
      root.thumbs[key] = Util.fileUrl(reply.image)
      root.thumbsVersion++
    })
    return ""
  }

  function activate(modifiers) {
    var row = rows.count ? rows.get(root.selectedIndex) : null
    if (row && row.isMore) {
      root.showWeaker = true
      root.rebuildRows(root.selectedHit ? root.selectedHit.path : "")
      return
    }
    if (root.service.phase === "missing") {
      Quickshell.execDetached(["wl-copy", root.service.installer])
      root.close()
      return
    }
    if (!root.selectedHit) return
    root.service.act(modifiers & Qt.ControlModifier ? "reveal" : "open", root.selectedHit)
    root.close()
  }

  function copySelected() {
    if (!root.selectedHit) return
    root.service.act("copy", root.selectedHit)
    root.close()
  }

  ListModel { id: rows }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Timer {
    id: meaningTimer
    interval: 220
    onTriggered: root.searchMeaning()
  }

  Timer {
    id: previewTimer
    interval: 60
    onTriggered: root.fetchPreview()
  }

  component Chip: Rectangle {
    property alias text: label.text
    property bool overImage: false
    implicitWidth: label.implicitWidth + Style.space(12)
    implicitHeight: label.implicitHeight + Style.space(4)
    radius: Math.max(0, root.innerRadius - Style.space(4))
    color: overImage ? Util.alpha(root.background, 0.85) : Util.alpha(root.foreground, 0.1)

    Text {
      id: label
      anchors.centerIn: parent
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
  }

  component ActionButton: Rectangle {
    id: action
    property alias text: actionLabel.text
    property bool primary: false
    signal triggered()

    implicitWidth: actionLabel.implicitWidth + Style.spacing.controlPaddingX * 2
    implicitHeight: Style.spacing.controlHeight
    radius: root.innerRadius
    color: primary
      ? (actionArea.containsMouse ? Qt.lighter(Color.accent, 1.1) : Color.accent)
      : (actionArea.containsMouse ? Style.hoverFill : Style.normalFill)
    scale: actionArea.pressed ? 0.96 : 1

    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: root.easeOut } }
    Behavior on color { ColorAnimation { duration: root.fadeFast } }

    Text {
      id: actionLabel
      anchors.centerIn: parent
      color: action.primary ? root.background : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: actionArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }

  component FadingText: Text {
    id: fading
    Behavior on text {
      SequentialAnimation {
        NumberAnimation { target: fading; property: "opacity"; to: 0; duration: root.fadeFast / 2 }
        PropertyAction {}
        NumberAnimation { target: fading; property: "opacity"; to: 1; duration: root.fadeFast / 2 }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-digup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      x: Math.round((panel.width - width) / 2)
      y: Math.round(panel.height * 0.16)
      width: Math.min(Style.space(820), panel.width - Style.gapsOut * 2)
      height: contentTopInset + contentBottomInset + root.headerHeight + root.footerHeight
        + (root.expanded ? root.bodyHeight + Style.spacing.md * 2 : 0)
      radius: root.cardRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.padding
      clip: true

      MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.codeMode ? Model.GLYPHS.code : "\u{F0349}"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          TextInput {
            id: input
            anchors.left: searchGlyph.right
            anchors.leftMargin: Style.spacing.xxl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Style.selectionFill
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            clip: true
            focus: true
            onTextChanged: {
              root.query = text
              root.runSearch()
            }

            Keys.onPressed: function(event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              if (event.key === Qt.Key_Escape) {
                if (input.text) input.text = ""
                else root.close()
              } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                root.select(1)
              } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                root.select(-1)
              } else if (event.key === Qt.Key_PageDown) {
                root.select(5)
              } else if (event.key === Qt.Key_PageUp) {
                root.select(-5)
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(event.modifiers)
              } else if (ctrl && event.key === Qt.Key_C && !input.selectedText) {
                root.copySelected()
              } else {
                return
              }
              event.accepted = true
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: !input.text
              text: "Describe it: a dog on the beach"
              color: root.faint
              font: input.font
              elide: Text.ElideRight
            }
          }
        }

        Item {
          width: parent.width
          height: root.bodyHeight
          visible: root.expanded
          opacity: root.expanded ? 1 : 0

          Behavior on opacity { NumberAnimation { duration: root.fadeFast; easing.type: Easing.Bezier; easing.bezierCurve: root.easeOut } }

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: Style.normalBorderWidth
            color: Util.alpha(root.border, 0.2)
          }

          ListView {
            id: list
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Style.spacing.lg
            width: Math.round(parent.width * 0.44)
            model: rows
            clip: true
            spacing: Style.spacing.xxs
            boundsBehavior: Flickable.StopAtBounds
            visible: rows.count > 0

            section.property: "group"
            section.delegate: Item {
              required property string section
              width: ListView.view.width
              height: Style.font.caption + Style.spacing.lg * 2

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.sm
                text: parent.section
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.4
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property bool isMore
              required property string name
              required property string folder
              required property string loc
              required property string glyph
              required property string thumbKey
              required property int hitIndex

              readonly property bool current: index === root.selectedIndex
              readonly property string thumb: root.thumbsVersion >= 0 ? root.thumbFor(thumbKey, hitIndex) : ""

              width: ListView.view.width
              height: isMore ? Style.spacing.controlHeight + Style.spacing.lg : root.rowHeight
              radius: root.innerRadius
              color: current ? root.selectedBackground : "transparent"

              Text {
                visible: row.isMore
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: "Show " + root.hidden + (root.hidden === 1 ? " weaker match" : " weaker matches")
                color: row.current ? root.selectedText : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Rectangle {
                id: thumbTile
                visible: !row.isMore
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: root.thumbSize
                height: root.thumbSize
                radius: root.thumbRadius
                color: Util.alpha(root.foreground, 0.06)
                clip: true

                Text {
                  anchors.centerIn: parent
                  text: row.glyph
                  visible: thumbImage.status !== Image.Ready
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                Image {
                  id: thumbImage
                  anchors.fill: parent
                  source: row.thumb
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  opacity: status === Image.Ready ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: root.fadeFast } }
                }
              }

              Column {
                visible: !row.isMore
                anchors.left: thumbTile.right
                anchors.leftMargin: Style.spacing.xxl
                anchors.right: locChip.visible ? locChip.left : parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  text: row.name
                  color: row.current ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignLeft
                  elide: Text.ElideMiddle
                }

                Text {
                  width: parent.width
                  text: row.folder
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideLeft
                }
              }

              Chip {
                id: locChip
                visible: !row.isMore && row.loc !== ""
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                text: row.loc
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (pointerGate.moved(row, mouse) && root.selectedIndex !== row.index) root.setSelected(row.index)
                }
                onClicked: {
                  root.setSelected(row.index)
                  root.activate(0)
                }
              }
            }
          }

          Item {
            id: preview
            anchors.left: list.right
            anchors.leftMargin: root.padding
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Style.spacing.lg + Style.spacing.md
            visible: root.selectedHit !== null

            readonly property var hit: root.selectedHit || ({})
            readonly property bool hasVisual: Model.renderKind(hit) !== "" || hit.kind === "audio"

            Item {
              id: stage
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Math.round(parent.height * 0.56)

              Image {
                id: previewImage
                anchors.fill: parent
                source: root.previewImage
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: preview.hasVisual
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: root.easeOut } }
              }

              Chip {
                visible: previewImage.status === Image.Ready && Model.locLabel(preview.hit) !== ""
                x: Math.round((stage.width - previewImage.paintedWidth) / 2) + Style.spacing.lg
                y: Math.round((stage.height + previewImage.paintedHeight) / 2) - height - Style.spacing.lg
                text: Model.locLabel(preview.hit)
                overImage: true
              }

              Column {
                visible: preview.hit.kind === "audio"
                anchors.centerIn: parent
                spacing: Style.spacing.md

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Model.GLYPHS.audio
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge * 2
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: preview.hit.loc !== undefined ? Model.formatTime(preview.hit.loc) : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.features: { "tnum": 1 }
                }
              }

              Rectangle {
                anchors.fill: parent
                visible: !preview.hasVisual
                radius: root.innerRadius
                color: Util.alpha(root.foreground, 0.04)
                clip: true

                Text {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.xxl
                  textFormat: Text.RichText
                  text: Model.previewHtml(root.previewText || preview.hit.excerpt || "", Model.parseQuery(root.query).q, root.mark, preview.hit.kind === "code")
                  color: root.foreground
                  font.family: preview.hit.kind === "code" ? Style.font.family : root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: preview.hit.kind === "code" ? Text.NoWrap : Text.Wrap
                  opacity: text ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: root.fadeFast } }
                }
              }
            }

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: stage.bottom
              anchors.topMargin: Style.spacing.xxl
              spacing: Style.spacing.xs

              Text {
                width: parent.width
                text: Model.fileName(preview.hit.path)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideMiddle
              }

              Text {
                width: parent.width
                text: Model.folderOf(preview.hit.path, root.service.home)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideLeft
              }

              Text {
                width: parent.width
                text: preview.hit.path ? Model.metaLine(preview.hit) : ""
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
              }

              Item { width: 1; height: Style.spacing.md }

              Text {
                width: parent.width
                text: preview.hit.path ? Model.reason(preview.hit) : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                visible: !!preview.hit.excerpt && preview.hasVisual
                textFormat: Text.RichText
                text: Model.excerptHtml(preview.hit.excerpt || "", root.mark)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                maximumLineCount: 2
              }
            }

            Row {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              spacing: Style.spacing.controlGap

              ActionButton {
                text: "Open"
                primary: true
                onTriggered: root.activate(0)
              }

              ActionButton {
                text: "Show in folder"
                onTriggered: root.activate(Qt.ControlModifier)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width * 0.7
            spacing: Style.spacing.md
            visible: opacity > 0
            opacity: rows.count === 0 && (root.answered || root.service.phase === "missing" || (root.codeMode && !root.service.codeEnabled)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.fadeFast; easing.type: Easing.Bezier; easing.bezierCurve: root.easeOut } }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.service.phase === "missing"
                ? "I need DigUp's engine to search"
                : root.codeMode && !root.service.codeEnabled ? "Code search is off"
                : root.service.phase === "indexing" ? "Nothing yet, I'm still reading your files" : "Nothing matches that yet"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: root.service.phase === "missing"
                ? "Run " + root.service.installer + " once. Press Enter to copy the command."
                : root.codeMode && !root.service.codeEnabled
                  ? "Add your project folders under \"code\" in ~/.config/omarchy/digup.json."
                  : root.service.phase === "indexing" ? "Try again in a minute, or try other words."
                  : root.service.phase === "waiting" ? "I'll read the rest of your files when you plug in."
                  : "Try other words, or add folders in ~/.config/omarchy/digup.json."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Item {
          width: parent.width
          height: root.footerHeight

          FadingText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.footerText
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.selectedHit !== null
            text: "\u21b5 open    ctrl \u21b5 show in folder    ctrl C copy"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
