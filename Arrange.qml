import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Fullscreen overlay with a drag canvas. Summoned with
// `omarchy-shell shell summon io.github.auggnation.auggment-display '{}'`.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property string fontFamily: Style.font.family

  function open(payloadJson) {
    DisplayStore.refresh()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(DisplayStore.pluginId)
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-display-arrange"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(760), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(540), parent.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Arrange displays"
          meta: "Drag a display. Edges snap to neighbours."
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰍺"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Rectangle {
          id: canvas
          width: parent.width
          height: parent.height - y - footer.height - parent.spacing
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, Color.accent)

          readonly property int pad: Style.space(20)
          readonly property var box: Model.bounds(DisplayStore.layoutRects)
          readonly property real fit: Math.min((width - pad * 2) / box.w, (height - pad * 2) / box.h)
          readonly property real originX: pad + (width - pad * 2 - box.w * fit) / 2
          readonly property real originY: pad + (height - pad * 2 - box.h * fit) / 2

          Repeater {
            model: DisplayStore.layoutRects

            Item {
              id: slot
              required property var modelData
              x: canvas.originX + (modelData.x - canvas.box.x) * canvas.fit
              y: canvas.originY + (modelData.y - canvas.box.y) * canvas.fit
              width: modelData.w * canvas.fit
              height: modelData.h * canvas.fit

              // Drag moves this child, so the slot's bindings survive the drag.
              Rectangle {
                id: tile
                width: parent.width
                height: parent.height
                radius: Style.cornerRadius
                color: Style.selectedFillFor(root.foreground, Color.accent)
                border.width: slot.modelData.name === DisplayStore.selectedName ? 2 : 1
                border.color: slot.modelData.name === DisplayStore.selectedName ? Color.accent : Qt.darker(root.foreground, 1.6)

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(12)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: slot.modelData.model
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: slot.modelData.name + " · " + slot.modelData.w + "×" + slot.modelData.h + " · " + slot.modelData.x + "," + slot.modelData.y
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.SizeAllCursor
                  drag.target: tile
                  drag.axis: Drag.XAndYAxis
                  onClicked: DisplayStore.select(slot.modelData.name)
                  onReleased: {
                    var logicalX = slot.modelData.x + tile.x / canvas.fit
                    var logicalY = slot.modelData.y + tile.y / canvas.fit
                    tile.x = 0
                    tile.y = 0
                    if (Math.abs(logicalX - slot.modelData.x) + Math.abs(logicalY - slot.modelData.y) < 1) return
                    DisplayStore.moveDisplay(slot.modelData.name, logicalX, logicalY)
                  }
                }
              }
            }
          }
        }

        Row {
          id: footer
          width: parent.width
          spacing: Style.space(8)
          layoutDirection: Qt.RightToLeft

          Button {
            text: "Close"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.dismiss()
          }

          Button {
            visible: DisplayStore.hasPending
            text: "Revert"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: DisplayStore.revert()
          }

          Button {
            visible: DisplayStore.hasPending
            text: "Keep"
            bordered: true
            selected: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: DisplayStore.keep()
          }

          Text {
            visible: DisplayStore.hasPending
            text: "Reverting in " + DisplayStore.secondsLeft + "s"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
