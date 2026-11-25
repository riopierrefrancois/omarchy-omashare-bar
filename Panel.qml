import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omashare.share"
  ipcTarget: "omashare.share"
  manageIpc: false
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: installed ? button.implicitHeight : 0
  visible: installed

  readonly property string tool: String(Qt.resolvedUrl("tools.sh")).replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool installed: false
  property bool seeded: false
  property var knownJobs: ({})
  property var runningJobs: []
  property int unread: 0
  property var activities: []
  property var videos: []
  property string dashboard: ""
  property string errorText: ""
  property bool signedOut: false
  property double nowMs: Date.now()
  property bool justFinished: false
  property bool cursorActive: false
  property int keyRow: 0
  property int keyColumn: 0
  property bool copied: false

  // Never hand an untrusted string directly to Omarchy's tooltip or notification
  // components: unlike our own Text elements their text format is not ours to set.
  function safe(value, max) {
    return typeof value === "string" ? value.slice(0, max).replace(/&/g, "&amp;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;") : ""
  }
  function short(value, max) { return typeof value === "string" ? value.slice(0, max) : "" }
  function count(value) { return isFinite(value) ? Math.max(0, Math.min(999999, Math.floor(value))) : 0 }
  function validLink(value) { return typeof value === "string" && /^https:\/\/[^/\s]+\/\S{1,500}$/.test(value) ? value : "" }
  function filename(value) { return short(String(value || "").split("/").pop(), 200) }
  function stage(job) {
    if (job.stage === "uploading") return strings.t("stage.uploading").arg(Commons.I18n.formatNumber(Math.round(job.percent || 0)))
    if (job.stage === "transcribing") return strings.t("stage.transcribing")
    if (job.stage === "writing") return strings.t("stage.writing")
    return strings.t("stage.preparing")
  }
  readonly property var mainJob: runningJobs.length ? runningJobs[0] : null
  readonly property string tooltip: {
    if (mainJob) return safe(stage(mainJob), 150)
    if (unread > 0) {
      var comments = 0, views = 0
      for (var i = 0; i < activities.length; i++) {
        if (activities[i].read) continue
        if (activities[i].kind === "view") views++
        else if (activities[i].kind === "comment" || activities[i].kind === "reply") comments++
      }
      return safe(strings.tn("bar.new", unread).arg(Commons.I18n.formatNumber(unread))
        .arg(Commons.I18n.formatNumber(comments)).arg(Commons.I18n.formatNumber(views)), 180)
    }
    return strings.t("bar.title")
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function checkJobs() { if (!jobsProc.running) jobsProc.running = true }
  function acceptJobs(raw) {
    var data
    try { data = JSON.parse(String(raw || "")) } catch (e) { return }
    if (!Array.isArray(data)) return
    var current = ({}), active = []
    for (var i = 0; i < Math.min(64, data.length); i++) {
      var j = data[i]
      if (!j || !Number.isInteger(j.pid) || j.pid <= 0 || !isFinite(j.startedAt)
          || ["running", "done", "failed"].indexOf(j.state) < 0) continue
      var key = j.pid + ":" + j.startedAt
      var entry = {
        key: key, file: short(j.file, 1024), name: short(j.name, 200),
        stage: ["preparing", "uploading", "transcribing", "writing"].indexOf(j.stage) >= 0 ? j.stage : "preparing",
        state: j.state, percent: Math.max(0, Math.min(100, Number(j.percent) || 0)),
        link: validLink(j.link), title: short(j.title, 200), error: short(j.error, 200)
      }
      current[key] = entry
      if (entry.state === "running") active.push(entry)
      var previous = knownJobs[key]
      if (seeded && previous && previous.state === "running" && entry.state !== "running") {
        if (entry.state === "done") {
          if (entry.link) Quickshell.execDetached(["bash", tool, "copy", entry.link])
          Quickshell.execDetached(["omarchy-notification-send", strings.t("notice.copied"), safe(entry.title || entry.name, 200)])
          justFinished = true
          finishedTimer.restart()
        } else {
          Quickshell.execDetached(["omarchy-notification-send",
            safe(strings.t("notice.failed").arg(filename(entry.file)), 240), safe(entry.error, 200)])
        }
        refreshData()
      }
    }
    knownJobs = current
    runningJobs = active.slice(0, 16)
    seeded = true
  }

  onOpenedChanged: if (opened) {
    cursorActive = false; keyRow = 0; keyColumn = 0
    refreshData()
    checkJobs()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  Component.onCompleted: { availableProc.running = true; checkJobs() }
  Process {
    id: availableProc
    command: ["bash", root.tool, "available"]
    onExited: function(code) { root.installed = code === 0 }
  }
  Process {
    id: jobsProc
    command: ["bash", root.tool, "jobs"]
    stdout: StdioCollector { onStreamFinished: root.acceptJobs(text) }
  }
  Timer {
    interval: root.opened || root.runningJobs.length ? 1000 : 5000
    running: true; repeat: true
    onTriggered: { root.nowMs = Date.now(); root.checkJobs() }
  }
  Timer { id: finishedTimer; interval: 4000; onTriggered: root.justFinished = false }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.justFinished ? "󰄬" : "󰒖"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
        }
        Canvas {
          anchors.fill: parent
          visible: root.mainJob !== null
          property real progress: root.mainJob ? root.mainJob.percent : 0
          property bool spinning: root.mainJob && root.mainJob.stage !== "uploading"
          property real angle: 0
          onProgressChanged: requestPaint()
          onAngleChanged: requestPaint()
          onVisibleChanged: requestPaint()
          NumberAnimation on angle {
            from: 0; to: 360; duration: Style.duration(2500)
            loops: Animation.Infinite; running: parent.visible && parent.spinning
          }
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!visible) return
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, Math.min(width, height) / 2 - 1, -Math.PI / 2 + angle * Math.PI / 180,
              -Math.PI / 2 + angle * Math.PI / 180 + (spinning ? Math.PI * 0.8 : Math.PI * 2 * progress / 100))
            ctx.strokeStyle = root.accent
            ctx.lineWidth = 1.5
            ctx.stroke()
          }
        }
        Rectangle {
          visible: root.unread > 0
          anchors.right: parent.right; anchors.top: parent.top
          width: Style.space(5); height: width; radius: width / 2
          color: root.urgent
        }
      }
    }
    tooltipText: root.tooltip
    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.pickVideo()
      else root.toggle()
    }
  }
}
