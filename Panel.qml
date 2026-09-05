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
    if (workProc.running) return
    lastCommand = args.length ? args[0] : ""
    workProc.command = ["python3", root.ctlPath].concat(args)
    workProc.running = true
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
    onExited: root.refresh()
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

        Row {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.intervals
            Button {
              required property var modelData
              text: modelData + "m"
              selected: root.intervalMinutes === modelData
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.space(10)
              onClicked: root.runCtl(["set-timer", String(modelData)])
            }
          }
          Item { width: 1; height: 1; Layout.fillWidth: true }
          Button {
            text: "Agora"
            enabled: !root.busy
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.runCtl(["next", "--force"])
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
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: modelData.accent || Color.accent
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

            Row {
              anchors.fill: parent
              spacing: Style.space(10)

              Image {
                width: Style.space(72)
                height: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter
                source: modelData.path ? ("file://" + modelData.path) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 144
                sourceSize.height: 88
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
                  text: modelData.active ? "atual" : (modelData.enabled ? "no rodízio" : "fora")
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
