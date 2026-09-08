import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "FerretModel.js" as FerretModel

// Ferret — type-to-open file search.
//
// One hotkey, one text field, one ranked list of everything on the disk.
// Enter opens the highlighted file in whatever app owns its mime type;
// Ctrl+Enter opens the folder it lives in instead.
//
// The ranking and the disk work happen in ./ferret-search (see its header);
// this file is only the surface. Keystrokes are debounced so a fast typist
// spawns one search, not one per letter, and a reply is dropped unless it
// still matches what is in the field — otherwise a slow query landing late
// would overwrite the results of a newer, faster one.
//
// Colors come from the shared [menu] tokens, so any theme that styles the
// Omarchy menu styles Ferret too.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
  readonly property string helper: pluginDir ? pluginDir + "/ferret-search" : ""

  property bool opened: false
  property string query: ""
  property var results: []
  property int selectedIndex: 0
  property bool searching: false

  // The query the in-flight process was launched for. Compared against the
  // field on reply so a slow search landing late cannot overwrite the
  // results of a newer, faster one.
  property string inFlightQuery: ""
  property bool restartPending: false

  // ---- theme ---------------------------------------------------------------
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius

  readonly property int rowHeight: Math.max(Style.space(46), Style.font.body * 3)
  readonly property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  // ---- lifecycle -----------------------------------------------------------
  function open(payloadJson) {
    root.opened = true
    root.query = ""
    root.results = []
    root.selectedIndex = 0
    root.searching = false
    debounce.stop()
    pointerGate.reset()
    Qt.callLater(function () {
      field.text = ""
      field.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    debounce.stop()
    // Let an in-flight search finish on its own; killing it here would race
    // with the collector. Its reply is discarded by the query guard.
    root.results = []
    root.query = ""
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lonefox.ferret")
  }

  // ---- searching -----------------------------------------------------------
  function setQuery(next) {
    root.query = next
    if (next.trim().length < 2) {
      debounce.stop()
      root.results = []
        root.selectedIndex = 0
      root.searching = false
      return
    }
    root.searching = true
    debounce.restart()
  }

  function launchSearch() {
    if (root.helper === "") return
    var wanted = root.query.trim()
    if (wanted.length < 2) return
    if (searchProc.running) {
      // Stop the stale one; onRunningChanged picks the newest query back up.
      root.restartPending = true
      searchProc.running = false
      return
    }
    root.inFlightQuery = wanted
    searchProc.command = [root.helper, wanted]
    searchProc.running = true
  }

  function applyResults(raw) {
    // A reply is only interesting while the field still says what it was
    // asked about, and while the overlay is still up.
    if (!root.opened) return
    if (root.inFlightQuery !== root.query.trim()) return
    root.results = FerretModel.parseResults(raw)
    root.selectedIndex = root.results.length > 0 ? 0 : -1
    root.searching = false
    pointerGate.reset()
    if (root.results.length > 0) resultList.positionViewAtIndex(0, ListView.Beginning)
  }

  // ---- selection and activation -------------------------------------------
  function move(delta) {
    if (root.results.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = root.results.length - 1
    else if (next >= root.results.length) next = 0
    root.selectedIndex = next
    pointerGate.reset()
    resultList.positionViewAtIndex(next, ListView.Contain)
  }

  function movePage(delta) {
    if (root.results.length === 0) return
    var perPage = Math.max(1, Math.floor(resultList.height / root.rowHeight))
    var next = root.selectedIndex + delta * perPage
    if (next < 0) next = 0
    else if (next >= root.results.length) next = root.results.length - 1
    root.selectedIndex = next
    pointerGate.reset()
    resultList.positionViewAtIndex(next, ListView.Contain)
  }

  function activate(index, revealFolder) {
    if (index < 0 || index >= root.results.length) return
    var entry = root.results[index]
    if (!entry || !entry.path) return
    root.dismiss()
    Quickshell.execDetached([root.helper, revealFolder ? "--reveal" : "--open", String(entry.path)])
  }

  // Rows slide under the pointer as results arrive and as the list scrolls.
  // Without this, a cursor that merely happens to rest over the list would
  // steal the selection away from the keyboard on every keystroke.
  PointerMoveGate {
    id: pointerGate
    referenceItem: resultList
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      onStreamFinished: root.applyResults(text)
    }
    onRunningChanged: {
      if (running) return
      root.searching = false
      if (root.restartPending) {
        root.restartPending = false
        Qt.callLater(root.launchSearch)
      }
    }
  }

  // Long enough that a burst of typing collapses into one search, short
  // enough that the list feels attached to the keyboard.
  Timer {
    id: debounce
    interval: 130
    repeat: false
    onTriggered: root.launchSearch()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ferret"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      // Sat slightly above centre: the list grows downward, so an
      // optically-centred card keeps the field where the eye already is.
      y: Math.max(Style.gapsOut, Math.round((parent.height - height) * 0.34))
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      // Swallow clicks so they do not reach the dismissing MouseArea behind.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ---- search field ----------------------------------------------
        Row {
          id: header
          width: parent.width
          spacing: Style.spacing.controlGap

          Text {
            text: FerretModel.GLYPH.search
            color: root.foreground
            opacity: root.searching ? 1.0 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            anchors.verticalCenter: parent.verticalCenter

            // A quiet pulse while a search is out; no spinner, no layout shift.
            SequentialAnimation on opacity {
              running: root.searching
              loops: Animation.Infinite
              NumberAnimation { to: 0.35; duration: 420; easing.type: Easing.InOutQuad }
              NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
            }
          }

          TextField {
            id: field
            width: parent.width - header.spacing - Style.font.heading
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Search your files…"
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            foreground: root.foreground
            background: null
            leftPadding: 0
            rightPadding: 0
            onTextChanged: root.setQuery(text)

            // BeforeItem so navigation keys never reach the text cursor;
            // everything left unaccepted still falls through to editing.
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) {
                if (field.text.length > 0) field.text = ""
                else root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Down
                  || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))
                  || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
                root.move(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up
                  || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))
                  || (event.key === Qt.Key_Backtab)
                  || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                root.move(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_PageDown) {
                root.movePage(1)
                event.accepted = true
              } else if (event.key === Qt.Key_PageUp) {
                root.movePage(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(root.selectedIndex, (event.modifiers & Qt.ControlModifier) !== 0)
                event.accepted = true
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.spacing.hairline)
          color: root.foreground
          opacity: 0.14
        }

        // ---- results ----------------------------------------------------
        Item {
          id: resultArea
          width: parent.width
          height: parent.height - header.height - footer.height
            - Math.max(1, Style.spacing.hairline) - Style.spacing.md * 3

          ListView {
            id: resultList
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            // Whole rows only. A row cut through its path line reads as a
            // rendering glitch; the footer's result count is what tells the
            // reader there is more below.
            height: Math.max(root.rowHeight,
              Math.floor(parent.height / root.rowHeight) * root.rowHeight)
            model: root.results
            clip: true
            visible: root.results.length > 0
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            highlightMoveDuration: 0

            delegate: Rectangle {
              id: row
              required property int index
              required property var modelData

              readonly property bool current: index === root.selectedIndex

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: current ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.rowGap

                Text {
                  text: FerretModel.glyphFor(row.modelData)
                  color: row.current ? root.selectedText : root.foreground
                  opacity: row.current ? 1.0 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                  width: Style.font.iconLarge + Style.spacing.sm
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - (Style.font.iconLarge + Style.spacing.sm)
                    - meta.width - Style.spacing.rowGap * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    textFormat: Text.PlainText
                    text: String(row.modelData.name || "")
                    color: row.current ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    elide: Text.ElideMiddle
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: FerretModel.prettyDir(row.modelData.dir, root.home)
                    color: row.current ? root.selectedText : root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideLeft
                    width: parent.width
                  }
                }

                Text {
                  id: meta
                  textFormat: Text.PlainText
                  text: FerretModel.metaFor(row.modelData)
                  color: root.foreground
                  opacity: 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPositionChanged: function (mouse) {
                  if (pointerGate.moved(row, mouse)) root.selectedIndex = row.index
                }
                onClicked: function (mouse) {
                  root.selectedIndex = row.index
                  root.activate(row.index, mouse.button === Qt.RightButton)
                }
              }
            }
          }

          // ---- empty states ------------------------------------------------
          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.spacing.lg
            visible: root.results.length === 0

            Text {
              text: root.query.trim().length < 2 ? FerretModel.GLYPH.search : FerretModel.GLYPH.empty
              color: root.selectedText
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                if (root.query.trim().length < 2) return "Start typing to search every file on the disk"
                if (root.searching) return "Searching…"
                return "Nothing matches “" + root.query.trim() + "”"
              }
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        }

        // ---- footer -------------------------------------------------------
        Item {
          id: footer
          width: parent.width
          height: Style.font.caption + Style.spacing.md

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.results.length > 0
              ? (root.results.length + (root.results.length === 1 ? " result" : " results"))
              : ""
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "↑↓ select   ⏎ open   ⌃⏎ folder   esc close"
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
