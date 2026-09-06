import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "pdphillips.fun60-ultra"
  ipcTarget: "pdphillips.fun60-ultra"
  manageIpc: hostWidget === null

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property bool connected: false
  property string link: "none"
  property string vid: "0x3151"
  property string pid: ""
  property string devicePath: ""
  property string deviceName: ""
  property int battery: -1
  property bool charging: false
  property string protocol: "none"
  property bool writeSupported: false
  property string writeVia: ""
  property real actuationMm: 1.5
  property bool rtOn: false
  property real rtTravelMm: 0.3
  property bool snapOn: false
  property string lastError: ""
  property string profileName: "default"
  property string actionStatus: ""
  property var pending: []
  property string lastCmd: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(contentForeground, 1.55)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: Model.fileFromUrl(Qt.resolvedUrl("helper/fun60.py"))
  readonly property string barLabel: Model.barLabel(connected, link, battery)
  readonly property bool writesOk: connected && writeSupported
  readonly property bool snapWritesOk: false
  readonly property string opcodeHint: Model.UDEV_HINT

  function open() {
    root.controller.show()
    root.refresh()
  }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() { root.runHelper(["status"]) }

  function runHelper(argv) {
    if (helperProc.running) {
      root.pending = root.pending.concat([argv])
      return
    }
    root.lastCmd = argv[0] || ""
    helperProc.command = ["python3", root.helperPath].concat(argv)
    helperProc.running = true
  }

  function drainQueue() {
    if (root.pending.length === 0) return
    var next = root.pending[0]
    root.pending = root.pending.slice(1)
    root.runHelper(next)
  }

  function handleResult(exitCode, stdout, stderr) {
    var parsed = Model.parseJson(stdout)
    if (root.lastCmd === "udev-rule" && parsed && parsed.rule) {
      Quickshell.execDetached(["wl-copy", String(parsed.rule)])
      root.actionStatus = "Copied udev rule"
      actionClear.restart()
      return
    }
    if (root.lastCmd === "profile-load" && parsed && parsed.ok && parsed.profile) {
      var p = parsed.profile
      if (p.actuationMm !== undefined && p.actuationMm !== null) root.actuationMm = Model.clamp(p.actuationMm, Model.ACTUATION_MIN, Model.ACTUATION_MAX, 1.5)
      if (p.rtOn === true || p.rtOn === false) root.rtOn = p.rtOn
      if (p.rtTravelMm !== undefined && p.rtTravelMm !== null) root.rtTravelMm = Model.clamp(p.rtTravelMm, Model.RT_TRAVEL_MIN, Model.RT_TRAVEL_MAX, 0.3)
      if (p.snapOn === true || p.snapOn === false) root.snapOn = p.snapOn
      root.actionStatus = "Loaded " + String(parsed.name || root.profileName)
      actionClear.restart()
      if (root.writesOk) root.applyDevice()
      return
    }
    if (parsed) {
      if (root.lastCmd === "status" || parsed.connected !== undefined) Model.applyStatus(root, parsed)
      if (parsed.ok === false) {
        root.lastError = Model.elide(parsed.hint || parsed.error || stderr, 160)
        if (parsed.hint) root.actionStatus = Model.elide(parsed.hint, 140)
      } else if (root.lastCmd === "profile-save") {
        root.actionStatus = "Saved " + String(parsed.name || root.profileName)
        root.lastError = ""
        actionClear.restart()
      } else if (root.lastCmd === "set-actuation" || root.lastCmd === "rt") {
        root.lastError = ""
        root.actionStatus = ""
      }
    } else if (exitCode !== 0) {
      root.lastError = Model.elide(stderr || stdout || "helper failed", 160)
    }
  }

  function applyActuation() {
    if (!root.writesOk) return
    root.runHelper(["set-actuation", "--mm", String(Model.clamp(root.actuationMm, Model.ACTUATION_MIN, Model.ACTUATION_MAX, 1.5))])
  }

  function applyRt() {
    if (!root.writesOk) return
    var args = ["rt", root.rtOn ? "--on" : "--off"]
    if (root.rtOn) args = args.concat(["--mm", String(Model.clamp(root.rtTravelMm, Model.RT_TRAVEL_MIN, Model.RT_TRAVEL_MAX, 0.3))])
    root.runHelper(args)
  }

  function applySnap() {
    root.runHelper(["snap", root.snapOn ? "--on" : "--off"])
  }

  function applyDevice() {
    root.applyActuation()
    root.applyRt()
  }

  function saveProfile() {
    var name = Model.profileName(profileField.text)
    if (name === "") {
      root.lastError = "Profile name must be letters, digits, dot, underscore, or dash"
      return
    }
    root.profileName = name
    root.runHelper([
      "profile-save", "--name", name,
      "--actuation", String(root.actuationMm),
      "--rt", root.rtOn ? "on" : "off",
      "--rt-mm", String(root.rtTravelMm),
      "--snap", root.snapOn ? "on" : "off"
    ])
  }

  function loadProfile() {
    var name = Model.profileName(profileField.text)
    if (name === "") {
      root.lastError = "Profile name must be letters, digits, dot, underscore, or dash"
      return
    }
    root.profileName = name
    root.runHelper(["profile-load", "--name", name])
  }

  function copyUdev() { root.runHelper(["udev-rule"]) }

  function openWeb() {
    Quickshell.execDetached(["bash", "-lc",
      "for b in brave brave-browser chromium chromium-browser google-chrome-stable google-chrome; do command -v \"$b\" >/dev/null 2>&1 && exec \"$b\" --new-window https://app.monsgeek.com; done; exec xdg-open https://app.monsgeek.com"])
    root.actionStatus = "Opened official web driver (Linux HID not claimed)"
    actionClear.restart()
  }

  onOpenedChanged: if (opened) root.refresh()

  Timer {
    interval: 20000
    repeat: true
    running: root.hostWidget !== null || root.opened
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: actionClear
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: helperProc
    running: false
    command: []
    stdout: StdioCollector { id: helperOut; waitForEnd: true }
    stderr: StdioCollector { id: helperErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.handleResult(exitCode, String(helperOut.text || ""), String(helperErr.text || ""))
      root.drainQueue()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "FUN60 Ultra"
            meta: Model.heroMeta(root.connected, root.link, root.battery, root.charging)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: Model.deviceLine(root.vid, root.pid, root.protocol)
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            visible: root.actionStatus !== "" || root.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.actionStatus !== "" ? root.actionStatus : root.lastError
            color: root.actionStatus !== "" ? root.dim : (bar ? bar.urgent : Color.urgent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "ACTUATION"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.actuationMm.toFixed(2) + " mm"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            enabled: root.writesOk
            opacity: enabled ? 1 : 0.45
            minimum: Model.ACTUATION_MIN
            maximum: Model.ACTUATION_MAX
            step: 0.01
            value: root.actuationMm
            onMoved: function(v) { root.actuationMm = Model.clamp(v, Model.ACTUATION_MIN, Model.ACTUATION_MAX, 1.5) }
            onReleased: function(v) {
              root.actuationMm = Model.clamp(v, Model.ACTUATION_MIN, Model.ACTUATION_MAX, 1.5)
              root.applyActuation()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.writesOk
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.opcodeHint
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Toggle {
            width: parent.width
            label: "Rapid Trigger"
            description: root.writesOk ? (root.rtOn ? "On · " + root.rtTravelMm.toFixed(2) + " mm" : "Off") : root.opcodeHint
            checked: root.rtOn
            enabled: root.writesOk
            opacity: enabled ? 1 : 0.45
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: {
              if (!root.writesOk) return
              root.rtOn = !root.rtOn
              root.applyRt()
            }
          }

          PanelSlider {
            width: parent.width
            visible: root.rtOn
            bar: root.bar
            enabled: root.writesOk
            opacity: enabled ? 1 : 0.45
            minimum: Model.RT_TRAVEL_MIN
            maximum: Model.RT_TRAVEL_MAX
            step: 0.01
            value: root.rtTravelMm
            onMoved: function(v) { root.rtTravelMm = Model.clamp(v, Model.RT_TRAVEL_MIN, Model.RT_TRAVEL_MAX, 0.3) }
            onReleased: function(v) {
              root.rtTravelMm = Model.clamp(v, Model.RT_TRAVEL_MIN, Model.RT_TRAVEL_MAX, 0.3)
              root.applyRt()
            }
          }

          Toggle {
            width: parent.width
            label: "Snap Key / SOCD"
            description: root.snapWritesOk ? (root.snapOn ? "On" : "Off") : root.opcodeHint
            checked: root.snapOn
            enabled: root.snapWritesOk
            opacity: enabled ? 1 : 0.45
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: {
              if (!root.snapWritesOk) return
              root.snapOn = !root.snapOn
              root.applySnap()
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "LOCAL PROFILE"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          TextField {
            id: profileField
            width: parent.width
            text: root.profileName
            placeholderText: "profile name"
            foreground: root.contentForeground
            font.family: root.contentFontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Button {
              text: "Save"
              foreground: root.contentForeground
              onClicked: root.saveProfile()
            }
            Button {
              text: "Load"
              foreground: root.contentForeground
              onClicked: root.loadProfile()
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Saved under ~/.config/omarchy/fun60-ultra/ (mode 0600)"
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.contentForeground }

          Button {
            width: parent.width
            text: "Open official web driver"
            foreground: root.contentForeground
            onClicked: root.openWeb()
          }

          Button {
            width: parent.width
            text: "Copy udev rule"
            foreground: root.contentForeground
            onClicked: root.copyUdev()
          }
        }
      }
    }
  }
}
