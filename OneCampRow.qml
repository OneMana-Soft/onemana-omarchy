import QtQuick
import qs.Commons

// One clickable line in the OneCamp popup: a title, and a count or detail on
// the right. Titles come from the workspace, so they are always plain text.
Item {
  id: line
  property string title: ""
  property string meta: ""
  property bool urgent: false
  signal activated()
  width: parent ? parent.width : 0
  height: Style.space(24)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: hover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent, Color.urgent) : "transparent"
  }
  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.right: metaText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: line.title
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: line.urgent ? Color.urgent : Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: metaText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    text: line.meta
    textFormat: Text.PlainText
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: line.activated() }
}
