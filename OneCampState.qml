pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// What the bar knows about your OneCamp workspace. One instance for every
// monitor's bar, so the workspace is asked once per interval, not per screen.
//
// Reads ~/.config/onemana/onecamp.conf (written by scripts/connect) and asks
// the workspace's API with the token in onecamp.header. curl reads that header
// from the file (-H @file): the token is never on a command line.
Item {
  id: root

  property var settings: ({})
  readonly property int intervalSec: Math.max(30, Number(settings && settings.refreshIntervalSec) || 60)
  readonly property bool notifyEnabled: !(settings && settings.notifications === false)

  readonly property string confDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/onemana"
  readonly property string headerPath: confDir + "/onecamp.header"
  readonly property string scriptsDir: String(Qt.resolvedUrl("scripts")).replace(/^file:\/\//, "")

  property bool configured: false
  property string workspace: ""
  property string api: ""
  property var unread: Model.parseUnread("")
  property var attention: Model.parseAttention("")
  property string error: ""
  property bool loading: false

  readonly property string badge: Model.badgeText(unread.total, attention.approvals)
  readonly property bool needsAction: attention.approvals > 0
  readonly property string summary: !configured
    ? "Connect your workspace"
    : (error !== "" ? error : Model.summaryLine(unread, attention))

  // The approvals count last seen, so a new one is announced once.
  property int _lastApprovals: -1

  function refresh() {
    confFile.reload()
    if (!configured || unreadProc.running) return
    loading = true
    unreadProc.running = true
  }

  function workspaceUrl(path) { return Model.joinUrl(workspace, path || "/app/home") }

  // Open a page of the workspace (or a full link) the way scripts/open does.
  function openPath(path) {
    Quickshell.execDetached([scriptsDir + "/open", path || "/app/home"])
  }

  // Setup steps run in Omarchy's floating terminal, where they can ask
  // questions and show progress; plugins themselves never install anything.
  function runScript(name) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", scriptsDir + "/" + name])
  }

  function _apply(text, exitCode) {
    var r = Model.splitStatus(text)
    if (exitCode !== 0 || r.http !== 200) {
      error = Model.errorText(exitCode, r.http)
      return null
    }
    error = ""
    return r.body
  }

  FileView {
    id: confFile
    path: root.confDir + "/onecamp.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.refresh() }
    onLoaded: {
      var c = Model.parseConf(text())
      root.workspace = c.workspace
      root.api = c.api
      root.configured = c.ok
    }
    onLoadFailed: {
      root.configured = false
      root.workspace = ""
      root.api = ""
    }
  }

  Process {
    id: unreadProc
    command: ["curl", "-sS", "--max-time", "10", "-H", "@" + root.headerPath,
              "-w", "\n%{http_code}", Model.joinUrl(root.api, "/v1/unread")]
    stdout: StdioCollector {
      id: unreadOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var body = root._apply(unreadOut.text, exitCode)
      if (body !== null) root.unread = Model.parseUnread(body)
      attentionProc.running = true
    }
  }

  // The AI edition's approvals and overdue tasks. A 404 means the workspace
  // has no AI; that is not an error, the bar shows unread alone.
  Process {
    id: attentionProc
    command: ["curl", "-sS", "--max-time", "10", "-H", "@" + root.headerPath,
              "-w", "\n%{http_code}", Model.joinUrl(root.api, "/v1/attention")]
    stdout: StdioCollector {
      id: attentionOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.loading = false
      var r = Model.splitStatus(attentionOut.text)
      if (exitCode !== 0 || r.http !== 200) {
        root.attention = Model.parseAttention("")
        return
      }
      root.attention = Model.parseAttention(r.body)
      var n = root.attention.approvals
      if (root.notifyEnabled && root._lastApprovals >= 0 && n > root._lastApprovals) {
        Quickshell.execDetached(["notify-send", "-a", "OneCamp", "-i", "dialog-question",
          n === 1 ? "An agent is waiting for your approval" : n + " agent actions are waiting for your approval",
          "Open OneCamp to approve or deny."])
      }
      root._lastApprovals = n
    }
  }

  Timer {
    interval: root.intervalSec * 1000
    running: root.configured
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // The first read can race the shell starting up; one late reload settles it.
  Timer {
    interval: 1500
    running: true
    onTriggered: root.refresh()
  }
}
