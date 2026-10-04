pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as OneMana

// OneCamp on the Omarchy bar: the OneCamp ring with what is waiting for you
// (unread messages, and agent actions waiting for your approval). Click for
// the list; right-click opens OneCamp; middle-click refreshes.
BarWidget {
  id: root
  moduleName: "dev.onemana.onecamp"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  readonly property var st: OneMana.OneCampState

  function open() { popupOpen = true; st.refresh() }
  function close() { popupOpen = false }
  function toggle() { popupOpen ? close() : open() }
  function closeForPopoutSwitch() { close() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSettingsChanged: st.settings = root.settings || ({})
  Component.onCompleted: st.settings = root.settings || ({})

  IpcHandler {
    target: "dev.onemana.onecamp"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function refresh(): string { root.st.refresh(); return root.st.summary }
    function status(): string {
      return JSON.stringify({
        configured: root.st.configured,
        unread: root.st.unread.total,
        approvals: root.st.attention.approvals,
        overdue: root.st.attention.overdue,
        error: root.st.error
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The ring is OneCamp's mark; the count is everything waiting for you.
    text: root.st.badge === "" ? "" : " " + root.st.badge
    active: root.st.needsAction
    dimmed: !root.st.configured
    tooltipText: "OneCamp · " + root.st.summary
    onPressed: function(b) {
      if (b === Qt.RightButton) root.st.openPath("/app/home")
      else if (b === Qt.MiddleButton) root.st.refresh()
      else root.toggle()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: ""
          color: root.st.needsAction ? Color.urgent : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          width: parent.width - Style.space(28)
          Text {
            text: "OneCamp"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.st.summary
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.st.error !== "" ? Color.urgent : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Not connected yet: one clear step.
      Column {
        visible: !root.st.configured
        width: parent.width
        spacing: Style.space(6)
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Show your unread messages and the agent actions waiting for you, right here."
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Button {
          text: "Connect your workspace"
          bordered: true
          onClicked: { root.close(); root.st.runScript("connect") }
        }
      }

      PanelSectionHeader {
        visible: root.st.configured && root.st.attention.items.length > 0
        text: "Waiting for you"
      }
      Repeater {
        model: root.st.configured ? root.st.attention.items : []
        delegate: OneMana.OneCampRow {
          required property var modelData
          title: modelData.title
          meta: modelData.subtitle !== "" ? modelData.subtitle : modelData.kind
          urgent: modelData.source === "approval"
          onActivated: { root.close(); root.st.openPath(modelData.url !== "" ? modelData.url : "/app/home") }
        }
      }

      PanelSectionHeader {
        visible: root.st.configured && root.st.unread.top.length > 0
        text: "Unread"
      }
      Repeater {
        model: root.st.configured ? root.st.unread.top : []
        delegate: OneMana.OneCampRow {
          required property var modelData
          title: modelData.name
          meta: String(modelData.count)
          onActivated: { root.close(); root.st.openPath(modelData.path) }
        }
      }

      Text {
        visible: root.st.configured && root.st.error === "" && root.st.unread.total === 0 && root.st.attention.items.length === 0
        text: root.st.loading ? "Checking…" : "All caught up."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: column.width }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        Button {
          visible: root.st.configured
          text: "Open OneCamp"
          bordered: true
          onClicked: { root.close(); root.st.openPath("/app/home") }
        }
        Button {
          visible: root.st.configured
          text: "Refresh"
          onClicked: root.st.refresh()
        }
        Button {
          text: "Desktop app"
          tooltipText: "Install the OneCamp desktop app (signature checked)"
          onClicked: { root.close(); root.st.runScript("install-desktop") }
        }
        Button {
          text: "Local AI"
          tooltipText: "Run AI on this computer: Ollama and qwen3:4b-instruct"
          onClicked: { root.close(); root.st.runScript("install-local-ai") }
        }
        Button {
          visible: !root.st.configured
          text: "Start free"
          tooltipText: "OneCamp is free for teams up to 25 people"
          onClicked: { root.close(); Quickshell.execDetached(["xdg-open", "https://onemana.dev/free"]) }
        }
        Button {
          visible: root.st.configured
          text: "Reconnect"
          onClicked: { root.close(); root.st.runScript("connect") }
        }
      }
    }
  }
}
