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

  readonly property var keyRows: {
    var rows = [[{kind: "pick"}]]
    if (signedOut) return []
    if (unread > 0) {
      for (var a = 0; a < activities.length && a < 5; a++)
        rows.push([{kind: "activity", index: a}])
      rows.push([{kind: "readAll"}])
    }
    for (var v = 0; v < videos.length && v < 8; v++)
      rows.push([{kind: "video", index: v}, {kind: "copy", index: v}, {kind: "open", index: v}])
    if (dashboard) rows.push([{kind: "dashboard"}])
    return rows
  }
  readonly property var keyTarget: cursorActive && keyRow < keyRows.length
    ? keyRows[keyRow][Math.min(keyColumn, keyRows[keyRow].length - 1)] : null
  function selected(kind, index) {
    return keyTarget && keyTarget.kind === kind && keyTarget.index === (index || 0)
  }
  function point(kind, index) {
    for (var r = 0; r < keyRows.length; r++)
      for (var c = 0; c < keyRows[r].length; c++)
        if (keyRows[r][c].kind === kind && keyRows[r][c].index === (index || 0)) {
          cursorActive = true; keyRow = r; keyColumn = c; return
        }
  }
  function moveKey(dx, dy) {
    if (!keyRows.length) return
    if (!cursorActive) { cursorActive = true; keyRow = 0; keyColumn = 0; return }
    keyRow = Math.max(0, Math.min(keyRows.length - 1, keyRow + dy))
    keyColumn = Math.max(0, Math.min(keyRows[keyRow].length - 1, keyColumn + dx))
  }
  function activate() {
    var target = keyTarget || (keyRows.length ? keyRows[0][0] : null)
    if (!target) return
    if (target.kind === "pick") pickVideo()
    else if (target.kind === "readAll") markRead(["--all"])
    else if (target.kind === "dashboard") openLink(dashboard)
    else if (target.kind === "activity") openActivity(activities[target.index])
    else if (target.kind === "video" || target.kind === "open") openLink(videos[target.index].link)
    else if (target.kind === "copy") copyLink(videos[target.index].link)
  }
  function pickVideo() {
    if (!installed || pickProc.running) return
    close()
    pickProc.running = true
  }
  function openLink(link) {
    var url = validLink(link)
    if (url) Quickshell.execDetached(["xdg-open", url])
    close()
  }
  function copyLink(link) {
    var url = validLink(link)
    if (!url) return
    Quickshell.execDetached(["bash", tool, "copy", url])
    copied = true; copiedTimer.restart()
  }
  function openActivity(item) {
    if (!item) return
    if (!item.read) markRead([item.id])
    openLink(item.link)
  }
  function relative(iso) {
    var age = Math.max(0, Math.floor((nowMs - new Date(iso).getTime()) / 60000))
    if (!isFinite(age)) return ""
    if (age < 1) return strings.t("time.now")
    if (age < 60) return strings.tn("time.minutes", age).arg(Commons.I18n.formatNumber(age))
    var hours = Math.floor(age / 60)
    if (hours < 24) return strings.tn("time.hours", hours).arg(Commons.I18n.formatNumber(hours))
    var days = Math.floor(hours / 24)
    return strings.tn("time.days", days).arg(Commons.I18n.formatNumber(days))
  }
  function activityText(item) {
    var who = item.who || strings.t("activity.someone")
    var title = item.videoTitle || strings.t("activity.video")
    if (item.kind === "view") return strings.t("activity.view").arg(who).arg(title)
    if (item.kind === "reaction") return strings.t("activity.reaction").arg(who).arg(title)
    if (item.kind === "reply") return strings.t("activity.reply").arg(who).arg(title).arg(item.text || "")
    return strings.t("activity.comment").arg(who).arg(title).arg(item.text || "")
  }
  function videoDate(video) {
    var date = new Date(video.createdAt)
    if (!isFinite(date.getTime())) return ""
    var stamp = Qt.locale(Commons.I18n.formatLocale).toString(date, "MMM d")
    var seconds = Math.floor(video.duration)
    return strings.t("video.date").arg(stamp).arg(Math.floor(seconds / 60) + ":" + ("0" + seconds % 60).slice(-2))
  }
  function videoCounts(video) {
    return strings.t("video.counts")
      .arg(strings.tn("video.views", video.views).arg(Commons.I18n.formatNumber(video.views)))
      .arg(strings.tn("video.comments", video.comments).arg(Commons.I18n.formatNumber(video.comments)))
  }

  Process {
    id: pickProc
    command: ["bash", root.tool, "pick"]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path.startsWith("/") && path.length <= 4096 && !/[\r\n\0]/.test(path))
          Quickshell.execDetached(["bash", root.tool, "upload", path])
      }
    }
  }
  Timer { id: copiedTimer; interval: 2000; onTriggered: root.copied = false }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))
    heightLive: true

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveKey(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: strings.t("bar.title")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Column {
            visible: root.runningJobs.length > 0 && !root.signedOut
            width: parent.width
            spacing: Style.space(5)
            Text {
              textFormat: Text.PlainText
              text: strings.t("panel.sharing")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.runningJobs
              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(3)
                Text {
                  textFormat: Text.PlainText
                  text: root.filename(modelData.file)
                  width: parent.width; elide: Text.ElideRight
                  color: root.foreground; font.family: root.fontFamily
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.stage(modelData)
                  color: root.dim; font.family: root.fontFamily
                }
                Rectangle {
                  width: parent.width; height: Style.space(3)
                  color: root.dim; radius: height / 2
                  Rectangle {
                    width: parent.width * (modelData.stage === "uploading" ? modelData.percent / 100 : 0.12)
                    height: parent.height; radius: height / 2; color: root.accent
                  }
                }
              }
            }
          }

          ActionRow {
            visible: !root.signedOut
            width: parent.width
            label: strings.t("panel.pick")
            glyph: "󰐕"
            highlighted: root.selected("pick")
            onHovered: root.point("pick", 0)
            onTriggered: root.pickVideo()
          }

          Text {
            visible: root.signedOut
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("panel.signIn")
            wrapMode: Text.WordWrap
            color: root.foreground; font.family: root.fontFamily
          }
          Text {
            visible: !root.signedOut && root.errorText !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.errorText
            wrapMode: Text.WordWrap
            color: root.dim; font.family: root.fontFamily
          }

          Column {
            visible: !root.signedOut && root.unread > 0
            width: parent.width
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: strings.t("panel.new")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.activities.slice(0, 5)
              ActionRow {
                required property var modelData
                required property int index
                width: parent.width
                label: root.activityText(modelData)
                detail: root.relative(modelData.createdAt)
                highlighted: root.selected("activity", index)
                onHovered: root.point("activity", index)
                onTriggered: root.openActivity(modelData)
              }
            }
            ActionRow {
              width: parent.width
              label: strings.t("panel.readAll")
              highlighted: root.selected("readAll")
              onHovered: root.point("readAll", 0)
              onTriggered: root.markRead(["--all"])
            }
          }

          Column {
            visible: !root.signedOut
            width: parent.width
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: strings.t("panel.recent")
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              visible: root.videos.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: strings.t("panel.empty")
              wrapMode: Text.WordWrap
              color: root.dim; font.family: root.fontFamily
            }
            Repeater {
              model: root.videos.slice(0, 8)
              RowLayout {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(6)
                Item {
                  Layout.preferredWidth: Style.space(56)
                  Layout.preferredHeight: Style.space(38)
                  Rectangle { anchors.fill: parent; color: root.dim; radius: Style.space(3) }
                  Image {
                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                    source: modelData.thumbnail || ""
                    visible: modelData.thumbnail !== ""
                    cache: false; asynchronous: true
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: !modelData.thumbnail
                    textFormat: Text.PlainText; text: "󰕧"
                    color: root.foreground; font.family: root.fontFamily
                  }
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  ActionRow {
                    Layout.fillWidth: true
                    label: modelData.title
                    detail: root.videoDate(modelData) + " · " + root.videoCounts(modelData)
                    highlighted: root.selected("video", index)
                    onHovered: root.point("video", index)
                    onTriggered: root.openLink(modelData.link)
                  }
                }
                ActionRow {
                  Layout.preferredWidth: Style.space(55)
                  label: root.copied && root.selected("copy", index) ? strings.t("panel.copied") : strings.t("panel.copy")
                  highlighted: root.selected("copy", index)
                  onHovered: root.point("copy", index)
                  onTriggered: root.copyLink(modelData.link)
                }
                ActionRow {
                  Layout.preferredWidth: Style.space(40)
                  label: strings.t("panel.open")
                  highlighted: root.selected("open", index)
                  onHovered: root.point("open", index)
                  onTriggered: root.openLink(modelData.link)
                }
              }
            }
          }

          ActionRow {
            visible: !root.signedOut && root.dashboard !== ""
            width: parent.width
            label: strings.t("panel.dashboard")
            highlighted: root.selected("dashboard")
            onHovered: root.point("dashboard", 0)
            onTriggered: root.openLink(root.dashboard)
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: row
    property string label: ""
    property string detail: ""
    property string glyph: ""
    property bool highlighted: false
    signal hovered()
    signal triggered()
    hasCursor: highlighted
    foreground: root.foreground
    implicitHeight: body.implicitHeight + Style.space(8)
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered()
      onClicked: row.triggered()
    }
    Column {
      id: body
      anchors.left: parent.left; anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6); anchors.rightMargin: Style.space(6)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: row.glyph ? row.glyph + " " + row.label : row.label
        color: root.foreground; font.family: root.fontFamily
        elide: Text.ElideRight
      }
      Text {
        visible: row.detail !== ""
        textFormat: Text.PlainText
        width: parent.width; text: row.detail
        color: root.dim; font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
