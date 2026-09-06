import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "3v4ng3li0n00.themes"
  ipcTarget: "3v4ng3li0n00.themes"
  manageIpc: true

  readonly property string ctlPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/3v4ng3li0n00.themes/scripts/ctl.py"
  readonly property var intervals: [5, 10, 15, 30, 60]

  property var statusData: ({
    ok: true,
    current: "",
    current_name: "",
    current_bg: "",
    timer: { enabled: false, interval_minutes: 15 },
    sync: { message: "", added: 0, at: "" },
    themes: []
  })
  property string selectedId: ""
  property string lastCommand: ""
  property string flash: ""

  readonly property var themes: statusData.themes || []
  readonly property var selectedTheme: {
    var list = themes
    for (var i = 0; i < list.length; i++)
      if (list[i].id === root.selectedId) return list[i]
    for (var j = 0; j < list.length; j++)
      if (list[j].current) return list[j]
    return list.length ? list[0] : ({ id: "", name: "", backgrounds: [] })
  }
  readonly property var backgrounds: selectedTheme && selectedTheme.backgrounds ? selectedTheme.backgrounds : []
  readonly property bool timerOn: !!(statusData.timer && statusData.timer.enabled)
  readonly property int intervalMinutes: (statusData.timer && statusData.timer.interval_minutes) ? statusData.timer.interval_minutes : 15
  readonly property var scene: (statusData.timer && statusData.timer.scene) ? statusData.timer.scene : ({ map_active: false, chroma_active: false, density: 0.5, key: 0.5, chroma: 0.5, radius: 0.32 })
  property real padDensity: 0.5
  property real padKey: 0.5
  property real padChroma: 0.5
  property var pendingCtl: []
  readonly property bool busy: workProc.running
  readonly property bool syncing: busy && lastCommand === "sync"
  readonly property string heroTitle: selectedTheme.name || statusData.current_name || "Temas"
  readonly property string heroMeta: {
    if (syncing) return "Atualizando favoritos…"
    if (flash) return flash
    if (statusData.sync && statusData.sync.message)
      return (timerOn ? "Rodízio " + intervalMinutes + " min · " : "") + statusData.sync.message
    return timerOn ? ("Rodízio a cada " + intervalMinutes + " min") : "Rodízio desligado"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function runCtl(args) {
    if (workProc.running) {
      pendingCtl = args
      return
    }
    lastCommand = args.length ? args[0] : ""
    workProc.command = ["python3", root.ctlPath].concat(args)
    workProc.running = true
  }

  function commitMap() {
    root.runCtl(["set-scene", "map", String(root.padDensity), String(root.padKey)])
  }

  function commitChroma() {
    root.runCtl(["set-scene", "chroma", String(root.padChroma)])
  }

  function resetMap() {
    root.runCtl(["set-scene", "map", "off"])
  }

  function toggleChromaMenu() {
    if (root.scene.chroma_active)
      root.runCtl(["set-scene", "chroma", "off"])
    else
      root.commitChroma()
  }

  function syncPadFromStatus() {
    var s = root.scene
    if (!s) return
    if (sceneDebounce.running) return
    padDensity = s.density
    padKey = s.key
    padChroma = s.chroma
  }

  function applyStatus(raw) {
    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.ok === false) {
        flash = parsed.error || "erro"
        return
      }
      if (parsed && parsed.themes) {
        statusData = parsed
        if (!selectedId) {
          for (var i = 0; i < parsed.themes.length; i++) {
            if (parsed.themes[i].current) {
              selectedId = parsed.themes[i].id
              break
            }
          }
        }
      }
      if (parsed && parsed.message) flash = parsed.message
      root.syncPadFromStatus()
    } catch (e) {
      flash = "falha ao ler status"
    }
  }

  function selectTheme(slug) {
    selectedId = slug
    runCtl(["set-theme", slug])
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/theme-rotation.json"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Timer {
    interval: 2400
    running: root.flash !== ""
    onTriggered: root.flash = ""
  }

  Timer {
    id: sceneDebounce
    interval: 140
    onTriggered: root.commitMap()
  }

  Process {
    id: statusProc
    command: ["python3", root.ctlPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: workProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: {
      root.refresh()
      if (root.pendingCtl && root.pendingCtl.length) {
        var next = root.pendingCtl
        root.pendingCtl = []
        root.runCtl(next)
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰸌"
    slotSize: Style.bar.iconSlot
    tooltipText: root.heroTitle
    onPressed: function(b) {
      if (b === Qt.RightButton) root.runCtl(["next", "--force"])
      else if (b === Qt.MiddleButton) root.runCtl(["sync"])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.heroTitle
          meta: root.heroMeta.toUpperCase()
          iconComponent: Text {
            text: "󰸌"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
          }
          trailingControl: ToggleSwitch {
            checked: root.timerOn
            busy: root.busy && root.lastCommand === "set-timer"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            onToggled: root.runCtl(["set-timer", root.timerOn ? "off" : "on"])
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Button { text: "5m"; selected: root.intervalMinutes === 5; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; horizontalPadding: Style.space(10); onClicked: root.runCtl(["set-timer", "5"]) }
          Button { text: "10m"; selected: root.intervalMinutes === 10; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; horizontalPadding: Style.space(10); onClicked: root.runCtl(["set-timer", "10"]) }
          Button { text: "15m"; selected: root.intervalMinutes === 15; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; horizontalPadding: Style.space(10); onClicked: root.runCtl(["set-timer", "15"]) }
          Button { text: "30m"; selected: root.intervalMinutes === 30; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; horizontalPadding: Style.space(10); onClicked: root.runCtl(["set-timer", "30"]) }
          Button { text: "60m"; selected: root.intervalMinutes === 60; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; horizontalPadding: Style.space(10); onClicked: root.runCtl(["set-timer", "60"]) }
          Button { text: "Agora"; enabled: !root.busy; foreground: root.bar ? root.bar.foreground : Color.foreground; accent: Color.accent; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; onClicked: root.runCtl(["next", "--force"]) }
        }

        PanelSectionHeader {
          text: "Cena"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Button {
            text: "chroma"
            selected: root.scene.chroma_active === true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            horizontalPadding: Style.space(12)
            onClicked: root.toggleChromaMenu()
          }
        }

        Item {
          id: scenePad
          width: parent.width
          height: Style.space(148)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba((root.bar ? root.bar.foreground : Color.foreground).r, (root.bar ? root.bar.foreground : Color.foreground).g, (root.bar ? root.bar.foreground : Color.foreground).b, 0.08)
          }

          Text {
            text: "light"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(6)
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
          Text {
            text: "dark"
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Style.space(6)
            anchors.bottomMargin: Style.space(18)
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
          Text {
            text: "calm"
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Style.space(6)
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
          Text {
            text: "packed"
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: Style.space(6)
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Item {
            id: plot
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(36)
            anchors.topMargin: Style.space(10)
            anchors.bottomMargin: Style.space(22)

            Repeater {
              model: root.backgrounds
              Rectangle {
                required property var modelData
                width: modelData.active ? 8 : 6
                height: width
                radius: width / 2
                color: modelData.active ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
                opacity: modelData.in_chroma === false ? 0.12 : (modelData.in_map === false ? 0.36 : (modelData.enabled ? 0.95 : 0.4))
                x: Math.max(0, Math.min(plot.width - width, (modelData.density || 0) * plot.width - width / 2))
                y: Math.max(0, Math.min(plot.height - height, (1 - (modelData.key || 0)) * plot.height - height / 2))
              }
            }

            Rectangle {
              id: thumb
              width: Style.space(16)
              height: Style.space(16)
              radius: width / 2
              color: Color.accent
              border.color: root.bar ? root.bar.foreground : Color.foreground
              border.width: 1
              opacity: root.scene.map_active ? 1 : 0.45
              x: Math.max(0, Math.min(plot.width - width, root.padDensity * plot.width - width / 2))
              y: Math.max(0, Math.min(plot.height - height, (1 - root.padKey) * plot.height - height / 2))
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onDoubleClicked: root.resetMap()
              onPressed: function(mouse) { moveTo(mouse.x, mouse.y) }
              onPositionChanged: function(mouse) { if (pressed) moveTo(mouse.x, mouse.y) }
              function moveTo(px, py) {
                root.padDensity = Math.max(0, Math.min(1, px / Math.max(1, plot.width)))
                root.padKey = Math.max(0, Math.min(1, 1 - (py / Math.max(1, plot.height))))
                sceneDebounce.restart()
              }
            }
          }
        }

        Row {
          visible: root.scene.chroma_active === true
          width: parent.width
          spacing: Style.space(10)
          height: visible ? implicitHeight : 0
          Text {
            text: "mute"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
          }
          PanelSlider {
            id: chromaSlider
            width: parent.width - Style.space(110)
            bar: root.bar
            value: root.padChroma
            minimum: 0
            maximum: 1
            step: 0.02
            onMoved: function(v) {
              root.padChroma = v
            }
            onReleased: function(v) {
              root.padChroma = v
              root.commitChroma()
            }
          }
          Text {
            text: "vivid"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
          }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          text: "Temas"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)
          Repeater {
            model: root.themes
            Button {
              required property var modelData
              Layout.fillWidth: true
              text: modelData.name.replace("Aether ", "")
              selected: root.selectedId === modelData.id
              active: modelData.current === true
              bordered: true
              foreground: modelData.foreground || (root.bar ? root.bar.foreground : Color.foreground)
              accent: modelData.accent || Color.accent
              background: modelData.background || "transparent"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              leftAlign: true
              onClicked: root.selectTheme(modelData.id)
            }
          }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          text: "Backgrounds no rodízio"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        ListView {
          id: bgList
          width: parent.width
          height: Math.min(Style.space(220), Math.max(Style.space(72), root.backgrounds.length * Style.space(56)))
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          model: root.backgrounds

          delegate: Item {
            required property var modelData
            width: bgList.width
            height: Style.space(52)
            opacity: modelData.in_scene === false ? 0.28 : (modelData.enabled ? 1 : 0.45)

            Row {
              anchors.fill: parent
              spacing: Style.space(10)

              Item {
                width: Style.space(72)
                height: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  anchors.fill: parent
                  source: modelData.path ? ("file://" + modelData.path) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: 144
                  sourceSize.height: 88
                  opacity: modelData.active ? 1 : 0.95
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runCtl(["set-bg", root.selectedTheme.id, modelData.file])
                }
              }

              Column {
                width: parent.width - Style.space(72) - Style.space(52) - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.label || modelData.file
                  elide: Text.ElideRight
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  textFormat: Text.PlainText
                }

                Text {
                  width: parent.width
                  text: ((modelData.density_label || "") + " · " + (modelData.key_label || "") + " · " + (modelData.chroma_label || "") + " · " + (modelData.active ? "atual" : (modelData.enabled ? "no rodízio" : "fora")))
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
              }

              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.enabled === true
                busy: root.busy && root.lastCommand === "toggle-bg"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                accent: Color.accent
                onToggled: root.runCtl(["toggle-bg", root.selectedTheme.id, modelData.file])
              }
            }
          }

          Text {
            visible: root.backgrounds.length === 0
            anchors.centerIn: parent
            text: "Nenhum background neste tema"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }

        Button {
          width: parent.width
          text: root.syncing ? "Atualizando favoritos…" : "Atualizar temas"
          enabled: !root.busy
          foreground: root.bar ? root.bar.foreground : Color.foreground
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.runCtl(["sync"])
        }
      }
    }
  }
}
