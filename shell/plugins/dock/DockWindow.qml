import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  // Feature settings, from the "dock" section of ~/.config/omarchy/shell.json.
  // Each falls back to its default when missing or of the wrong type.
  readonly property var config: dock && dock.dockConfig ? dock.dockConfig : ({})

  function setting(group, key, fallback) {
    var section = window.config[group]
    var value = section && typeof section === "object" ? section[key] : undefined
    return value === undefined || value === null || typeof value !== typeof fallback ? fallback : value
  }

  // A theme role (urgent, accent, foreground, background, muted) or any
  // color Qt understands, such as "#ff5555".
  function themeColor(value, fallback) {
    var role = String(value || "").toLowerCase()
    if (role === "urgent") return Commons.Color.urgent
    if (role === "accent") return Commons.Color.accent
    if (role === "foreground" || role === "text") return Commons.Color.foreground
    if (role === "background") return Commons.Color.background
    if (role === "muted") return Commons.Color.muted
    if (role && Qt.colorEqual(role, role)) return role
    return window.themeColor(fallback, "urgent")
  }

  // WCAG 2.x contrast. Text needs 4.5:1 (AA); outlines and other non-text
  // parts need 3:1 against what they sit next to.
  readonly property bool ensureContrast: setting("contrast", "enabled", true)
  readonly property real textContrast: setting("contrast", "text", 4.5)
  readonly property real partContrast: setting("contrast", "parts", 3)

  function luminance(c) {
    function channel(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
  }

  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // The preferred color if it reaches the ratio against the other color;
  // otherwise the theme color that comes closest to it while passing, and
  // black or white as the last resort (one of them always passes 4.5:1).
  function readable(preferred, against, ratio) {
    if (!window.ensureContrast || contrast(preferred, against) >= ratio) return preferred
    var candidates = [Commons.Color.foreground, Commons.Color.background, Commons.Color.accent,
      Commons.Color.urgent, Commons.Color.muted, Qt.color("#ffffff"), Qt.color("#000000")]
    var best = null, bestDistance = 1e9
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i]
      if (contrast(c, against) < ratio) continue
      var distance = Math.abs(c.r - preferred.r) + Math.abs(c.g - preferred.g) + Math.abs(c.b - preferred.b) + (i >= 5 ? 0.5 : 0)
      if (distance < bestDistance) { best = c; bestDistance = distance }
    }
    if (best) return best
    return contrast(Qt.color("#ffffff"), against) >= contrast(Qt.color("#000000"), against) ? Qt.color("#ffffff") : Qt.color("#000000")
  }

  readonly property bool dotsEnabled: setting("windowDots", "enabled", true)
  readonly property int dotsMax: Math.max(1, setting("windowDots", "max", 3))
  readonly property color dotsColor: setting("windowDots", "color", "") ? themeColor(setting("windowDots", "color", ""), "foreground") : Commons.Color.bar.text

  // "pulse" brightens the icon, "tint" pulses it toward the color, "glow"
  // pulses a colored backdrop behind it, "off" shows nothing.
  readonly property string attentionStyle: setting("attention", "style", "pulse")
  readonly property color attentionColor: themeColor(setting("attention", "color", "urgent"), "urgent")
  readonly property int attentionPeriod: Math.max(200, setting("attention", "period", 1400))

  readonly property bool badgesEnabled: setting("badges", "enabled", true)
  readonly property color badgeColor: themeColor(setting("badges", "color", "accent"), "accent")
  readonly property color badgeTextColor: readable(themeColor(setting("badges", "textColor", "background"), "background"), badgeColor, textContrast)
  readonly property color badgeBorderColor: readable(themeColor(setting("badges", "borderColor", "background"), "background"), badgeColor, partContrast)
  // The dots' outline has to stand apart from the dot itself.
  readonly property color dotsOutline: readable(Commons.Color.background, dotsColor, partContrast)
  readonly property int badgeBorderWidth: Math.max(0, setting("badges", "borderWidth", 1))
  readonly property real badgeSize: Math.max(0.5, Math.min(2, setting("badges", "size", 1)))
  // top-right, top-left, bottom-right or bottom-left of the icon.
  readonly property string badgeCorner: setting("badges", "position", "top-right")
  readonly property int badgeMax: Math.max(1, setting("badges", "max", 99))

  readonly property bool tooltipEnabled: setting("tooltip", "enabled", true)
  readonly property int tooltipDelay: Math.max(0, setting("tooltip", "delay", 450))
  readonly property bool previewsEnabled: setting("tooltip", "previews", true)
  readonly property int previewsMax: Math.max(1, setting("tooltip", "maxPreviews", 6))
  // A slim frame around each preview, so a window the same color as the
  // popup still reads as a window.
  // The hover popup's colors: theme roles or hex, contrast-checked.
  readonly property color popupBackground: themeColor(setting("popup", "background", "background"), "background")
  readonly property color popupBorder: readable(themeColor(setting("popup", "border", "accent"), "accent"), popupBackground, partContrast)
  readonly property color popupText: readable(themeColor(setting("popup", "text", "foreground"), "foreground"), popupBackground, textContrast)
  readonly property color popupTitle: readable(themeColor(setting("popup", "title", "accent"), "accent"), popupBackground, textContrast)
  // The preview under the pointer: its frame, and a faint wash behind it.
  readonly property color popupHover: readable(themeColor(setting("popup", "hover", "accent"), "accent"), popupBackground, partContrast)

  // "hover" shows each preview's close button while the pointer is on it,
  // "always" keeps it shown, "off" hides it.
  readonly property string previewClose: setting("tooltip", "closeButton", "hover")
  readonly property color closeFill: popupBackground
  readonly property color closeGlyph: popupText
  readonly property color closeHoverFill: popupHover
  readonly property color closeHoverGlyph: readable(Commons.Color.background, closeHoverFill, textContrast)
  readonly property int previewBorderWidth: Math.max(0, setting("tooltip", "previewBorderWidth", 1))
  readonly property color previewBorderColor: readable(themeColor(setting("tooltip", "previewBorderColor", "muted"), "muted"), popupBackground, partContrast)

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || insertIndex >= 0)
  readonly property bool contentShown: shown && !tucked

  readonly property int gap: Style.spacing.xs
  readonly property int iconSize: Math.round(36 * Style.fontScale)
  // Each app has a square slot with its icon in the middle, and the slots run
  // straight to the edge of the dock.
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  // Extra room on the screen-edge side of each slot, where the window dots sit.
  readonly property int dotRoom: Style.space(5)
  // A slot's depth across the dock, and where its icon sits in it.
  readonly property int slotDepth: slotSize + dotRoom
  readonly property int iconX: iconInset + (position === "left" ? dotRoom : 0)
  readonly property int iconY: iconInset + (position === "top" ? dotRoom : 0)
  // A pinned app that is not running is drawn faded.
  readonly property real idleOpacity: 0.7
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has five rows.
  readonly property int popupRoom: Math.max(Style.spacing.popupRowHeight * 5 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2,
    previewHeight + Style.font.body * 4 + Style.spacing.sm * 6 + popClearance) + gap * 2
  // Window previews in the hover popup are this tall; width follows the window.
  readonly property int previewHeight: Math.round(140 * Style.fontScale)
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x, screenY - at.y - body.y)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    var along = window.vertical ? point.y : point.x
    var first = window.slotSize
    var count = window.dock ? window.dock.itemModel.count : 0
    return Math.max(0, Math.min(count, Math.round((along - first) / window.slotSize)))
  }
  // The app slot under the pointer, and the one whose tooltip shows once the
  // pointer has rested on it a moment.
  property Item hoverSlot: null
  property Item tipSlot: null

  function hoverChanged(slot, hovered) {
    if (hovered) {
      window.hoverSlot = slot
      if (window.tipSlot) window.tipSlot = slot
      else tipTimer.restart()
    } else if (window.hoverSlot === slot) {
      window.hoverSlot = null
      tipHideTimer.restart()
    }
  }

  Timer {
    id: tipTimer
    interval: window.tooltipDelay
    onTriggered: if (window.tooltipEnabled && window.hoverSlot && !window.menuOpen && !window.dragging) window.tipSlot = window.hoverSlot
  }

  Timer {
    id: tipHideTimer
    interval: 120
    onTriggered: if (!window.hoverSlot && !tipHover.hovered) window.tipSlot = null
  }

  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onWorkspaceIdChanged: if (dock) dock.readMode(workspaceId)
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
  }
  Component.onCompleted: if (dock) dock.readMode(workspaceId)

  function openMenu(item, slot) {
    window.tipSlot = null
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // How far an icon reaches past its slot when it pops on hover, with its
  // unread badge on top; the hover popup stays clear of both.
  readonly property int popClearance: Math.round(window.iconSize * 0.15)
    + Math.round(Math.max(10, window.iconSize * 0.42 * window.badgeSize) * 0.35 * 1.15)

  // Places the menu inward of the dock, centered on a slot. Extra pushes it
  // further away from the dock.
  function popupX(slot, popup, extra) {
    if (!slot) return 0
    var more = extra || 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + window.gap + more
    if (window.position === "right") return body.x - window.gap - popup.width - more
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup, extra) {
    if (!slot) return 0
    var more = extra || 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + window.gap + more
    if (window.position === "bottom") return body.y - window.gap - popup.height - more
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.gap + window.slotDepth + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.gap + window.slotDepth + window.popupRoom

  mask: Region {
    item: window.contentShown ? body : null

    Region { item: window.shown && window.autohide ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
    Region { item: tip.visible ? tip : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.gap + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : body.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : body.y
    width: window.vertical ? depth : body.width
    height: window.vertical ? body.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    width: slots.implicitWidth
    height: slots.implicitHeight
    // How far the dock is tucked past its edge. Auto-hide slides it, but only
    // while the dock is on screen: arriving on a floating workspace shows it
    // where it belongs at once.
    property real tuck: window.tucked ? window.slotDepth + window.gap : 0

    // Tucking away is quicker than coming back. A gentler curve than
    // Style.easeOut, which crosses the short slide in a frame or two.
    Behavior on tuck {
      id: tuckMotion
      enabled: window.shown
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 120 : 180)
        easing.type: Easing.OutCubic
      }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : Math.round((window.height - height) / 2)
    // Switching between tiled and floating workspaces shows and hides the dock
    // at once, with nothing to watch in between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : appRepeater.count + 1

      AppsSlot {}

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: AppSlot {}
      }
    }
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse

    width: window.vertical ? window.slotDepth : window.slotSize
    height: window.vertical ? window.slotSize : window.slotDepth

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    property real displayedShift: window.insertIndex >= 0 ? -window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A grid of app squares reads as "all apps" in any icon theme. Drawn
    // rather than taken from a font, so its edges stay crisp on the
    // transparent dock and it fills its slot like the app icons beside it.
    Item {
      x: window.iconX
      y: window.iconY
      width: window.iconSize
      height: window.iconSize
      scale: appsSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Grid {
        readonly property int square: Math.round(window.iconSize * 0.22)

        anchors.centerIn: parent
        columns: 3
        spacing: Math.round(window.iconSize * 0.1)

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            radius: Math.max(1, Math.round(parent.square * 0.2))
            color: Commons.Color.bar.text
          }
        }
      }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    readonly property bool urgent: !!modelData && modelData.windows.some(function(w) { return w.urgent })
    readonly property color attentionColor: window.attentionColor
    property real glow: 0
    readonly property int unread: window.dock ? window.dock.badgeFor(key) : 0
    // The icon pops on hover; the badge scales from the same point so it
    // rides along with it.
    property real iconScale: lifted || hovered ? 1.15 : 1
    Behavior on iconScale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    readonly property point popPoint: window.position === "top" ? Qt.point(window.iconX + window.iconSize / 2, window.iconY)
      : window.position === "left" ? Qt.point(window.iconX, window.iconY + window.iconSize / 2)
      : window.position === "right" ? Qt.point(window.iconX + window.iconSize, window.iconY + window.iconSize / 2)
      : Qt.point(window.iconX + window.iconSize / 2, window.iconY + window.iconSize)
    property real pulse: 1

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    onHoveredChanged: window.hoverChanged(appSlot, hovered)

    mouse.onPressed: function(event) {
      window.tipSlot = null
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      if (!window.dragging) {
        if (Math.abs(delta) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
    }

    // An app asking for attention pulses until one of its windows is focused:
    // the icon itself (pulse, tint), or a backdrop behind it (glow).
    Rectangle {
      // Kept clear of the window dots below the icon.
      readonly property int pad: Math.max(2, Math.round(window.iconInset / 2))
      x: window.iconX - pad
      y: window.iconY - pad
      width: window.iconSize + pad * 2
      height: window.iconSize + pad * 2
      radius: Style.cornerRadius + Math.round(window.iconInset / 3)
      visible: appSlot.urgent && window.attentionStyle === "glow"
      color: Qt.rgba(appSlot.attentionColor.r, appSlot.attentionColor.g, appSlot.attentionColor.b, 0.25 + 0.35 * appSlot.glow)
      border.width: Math.max(1, Style.space(2))
      border.color: appSlot.attentionColor
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
    }

    SequentialAnimation {
      running: appSlot.urgent && window.attentionStyle !== "off" && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) appSlot.glow = Style.reduceMotion ? 1 : 0

      NumberAnimation { target: appSlot; property: "glow"; from: 0; to: 1; duration: Style.duration(window.attentionPeriod / 2); easing.type: Easing.InOutSine }
      NumberAnimation { target: appSlot; property: "glow"; to: 0; duration: Style.duration(window.attentionPeriod / 2); easing.type: Easing.InOutSine }
    }

    // Running apps are drawn in full, pinned ones that are not running faded,
    // and one that is starting pulses between the two.
    Image {
      id: appIcon
      x: window.iconX
      y: window.iconY
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: appSlot.launching ? appSlot.pulse : (appSlot.windowCount > 0 ? 1 : window.idleOpacity)
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
      scale: appSlot.iconScale
      transformOrigin: window.popOrigin

      readonly property bool effectOn: appSlot.urgent && (window.attentionStyle === "pulse" || window.attentionStyle === "tint")
      layer.enabled: effectOn
      layer.effect: MultiEffect {
        brightness: window.attentionStyle === "pulse" ? 0.45 * appSlot.glow : 0
        colorization: window.attentionStyle === "tint" ? 0.75 * appSlot.glow : 0
        colorizationColor: appSlot.attentionColor
      }
    }

    // One dot per open window, up to three, on the side of the icon nearest
    // the screen edge.
    Grid {
      id: windowDots

      // Even, so it centers exactly under an icon in an even-width slot.
      readonly property int dot: 2 * Math.max(2, Math.round(window.iconSize * 0.07))
      // Centered in the space between the icon and the dock's edge.
      readonly property int edge: Math.max(1, Math.round((window.iconInset + window.dotRoom - dot) / 2))

      visible: window.dotsEnabled && appSlot.windowCount > 0
      // Only as many columns as dots: an empty column still takes up spacing
      // and would pull the dots off center.
      columns: window.vertical ? 1 : Math.max(1, Math.min(window.dotsMax, appSlot.windowCount))
      spacing: Math.max(2, Math.round(dot * 0.6))
      x: window.position === "left" ? edge
        : window.position === "right" ? appSlot.width - width - edge
        : window.iconX + (window.iconSize - width) / 2
      y: window.position === "top" ? edge
        : window.position === "bottom" ? appSlot.height - height - edge
        : window.iconY + (window.iconSize - height) / 2
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }

      Repeater {
        model: Math.min(window.dotsMax, appSlot.windowCount)

        delegate: Rectangle {
          width: windowDots.dot
          height: windowDots.dot
          radius: width / 2
          color: window.dotsColor
          // Outlined, so the dot shows on light and dark wallpapers alike.
          border.width: 1
          border.color: window.dotsOutline
        }
      }
    }

    // The app's unread count, in a bubble on the icon's top corner.
    Rectangle {
      id: unreadBadge

      readonly property int size: Math.max(10, Math.round(window.iconSize * 0.42 * window.badgeSize))
      readonly property bool atRight: window.badgeCorner.indexOf("left") < 0
      readonly property bool atTop: window.badgeCorner.indexOf("bottom") < 0
      readonly property int overhang: Math.round(size * 0.35)

      visible: window.badgesEnabled && appSlot.unread > 0
      height: size
      width: Math.max(size, unreadText.implicitWidth + Math.round(size * 0.5))
      radius: size / 2
      color: window.badgeColor
      border.width: window.badgeBorderWidth
      border.color: window.badgeBorderColor
      x: atRight ? window.iconX + window.iconSize - width + overhang : window.iconX - overhang
      y: atTop ? window.iconY - overhang : window.iconY + window.iconSize - height + overhang
      z: 2
      transform: [
        Scale {
          origin.x: appSlot.popPoint.x - unreadBadge.x
          origin.y: appSlot.popPoint.y - unreadBadge.y
          xScale: appSlot.iconScale
          yScale: appSlot.iconScale
        },
        Translate {
          x: window.vertical ? 0 : appSlot.displayedShift
          y: window.vertical ? appSlot.displayedShift : 0
        }
      ]

      Text {
        id: unreadText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: appSlot.unread > window.badgeMax ? window.badgeMax + "+" : String(appSlot.unread)
        color: window.badgeTextColor
        font.family: Style.font.family
        font.pixelSize: Math.round(unreadBadge.size * 0.68)
        font.bold: true
      }
    }

    // With animations off it holds still rather than spinning through
    // zero-length steps.
    SequentialAnimation {
      running: appSlot.launching && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) appSlot.pulse = 1

      NumberAnimation { target: appSlot; property: "pulse"; from: 1; to: window.idleOpacity; duration: Style.duration(500); easing.type: Easing.InOutSine }
      NumberAnimation { target: appSlot; property: "pulse"; to: 1; duration: Style.duration(500); easing.type: Easing.InOutSine }
    }
  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execDetached("omarchy-dock position " + modelData[0])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: Commons.I18n.t("dock.autoHide")
        checked: window.autohide
        onTriggered: Util.execDetached("omarchy-dock autohide " + (window.autohide ? "off" : "on"))
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }

      MenuRow {
        visible: menu.running
        text: "Force Quit"
        onTriggered: window.dock.forceQuit(menu.item)
      }
    }
  }

  // The hovered app's name, and the title of each of its windows.
  BorderSurface {
    id: tip

    readonly property var item: window.tipSlot ? window.tipSlot.modelData : null
    readonly property var entry: item && window.dock ? window.dock.entryFor(item) : null
    readonly property string appName: entry && entry.name ? entry.name : (item ? item.key : "")
    readonly property var windows: item ? item.windows.slice(0, window.previewsMax) : []
    readonly property int maxWidth: window.width - window.gap * 2
    readonly property int textRoom: maxWidth - padding * 2 - Style.spacing.controlPaddingX * 2

    visible: window.contentShown && !!item && !window.menuOpen && !window.dragging
    width: Math.min(maxWidth, Math.max(tipName.implicitWidth, tipTitles.implicitWidth) + padding * 2 + Style.spacing.controlPaddingX * 2)
    height: tipColumn.implicitHeight + padding * 2 + Style.spacing.xs * 2
    x: window.popupX(window.tipSlot, tip, window.popClearance)
    y: window.popupY(window.tipSlot, tip, window.popClearance)
    radius: Style.cornerRadius
    color: window.popupBackground
    // A section the theme doesn't define, so the dock's own color is used.
    borderSpec: Border.surfaceSpec("dock-popup", "border", window.popupBorder, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: tipColumn
      x: tip.contentLeftInset + Style.spacing.controlPaddingX
      y: tip.contentTopInset + Style.spacing.xs
      spacing: Style.spacing.xxs

      Text {
        id: tipName
        width: Math.min(implicitWidth, tip.textRoom)
        textFormat: Text.PlainText
        text: tip.appName
        elide: Text.ElideRight
        color: window.popupTitle
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      // Previews side by side, or with previews off, titles one per line.
      Grid {
        id: tipTitles
        columns: window.previewsEnabled ? Math.max(1, tip.windows.length) : 1
        spacing: window.previewsEnabled ? Style.spacing.sm : 0

        Repeater {
          model: tip.windows

          delegate: PreviewCard {}
        }
      }
    }

    HoverHandler {
      id: tipHover
      onHoveredChanged: if (!hovered) tipHideTimer.restart()
    }
  }

  // A live thumbnail of one window and its title; clicking it brings that
  // window forward.
  component PreviewCard: Rectangle {
    id: card

    required property var modelData
    readonly property var toplevel: modelData ? modelData.toplevel : null
    readonly property real aspect: preview.sourceSize.height > 0 ? preview.sourceSize.width / preview.sourceSize.height : 16 / 10
    readonly property int thumbWidth: Math.max(Math.round(window.previewHeight * 0.6), Math.min(Math.round(window.previewHeight * 2.2), Math.round(window.previewHeight * aspect)))

    readonly property int textWidth: window.previewsEnabled ? thumbWidth : Math.min(cardTitle.implicitWidth, tip.textRoom)
    width: textWidth + Style.spacing.xs * 2
    height: cardColumn.implicitHeight + Style.spacing.xs * 2
    radius: Style.cornerRadius
    readonly property bool active: cardMouse.containsMouse || closeMouse.containsMouse
    color: active ? Qt.rgba(window.popupHover.r, window.popupHover.g, window.popupHover.b, 0.12) : "transparent"
    border.width: card.modelData && card.modelData.urgent ? Math.max(1, Style.space(2)) : 0
    border.color: window.attentionColor

    Column {
      id: cardColumn
      x: Style.spacing.xs
      y: Style.spacing.xs
      spacing: Style.spacing.xxs

      Item {
        visible: window.previewsEnabled
        width: card.thumbWidth
        height: window.previewHeight

        ScreencopyView {
          id: preview
          anchors.fill: parent
          captureSource: tip.visible && window.previewsEnabled ? card.toplevel : null
          live: tip.visible && window.previewsEnabled
          paintCursor: false
          visible: hasContent
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: -border.width
          visible: window.previewBorderWidth > 0
          color: "transparent"
          radius: Math.max(2, Style.cornerRadius / 2)
          border.width: window.previewBorderWidth
          border.color: card.active ? window.popupHover : window.previewBorderColor
          z: 1
        }

        // Minimized windows, and any the compositor won't capture, show the
        // app icon instead.
        Image {
          visible: !preview.hasContent
          anchors.centerIn: parent
          width: Math.round(window.previewHeight * 0.4)
          height: width
          sourceSize: Qt.size(width * 2, height * 2)
          source: window.dock && tip.item ? window.dock.iconFor(tip.item) : ""
          fillMode: Image.PreserveAspectFit
          opacity: 0.6
        }
      }

      Text {
        id: cardTitle
        width: card.textWidth
        textFormat: Text.PlainText
        text: card.toplevel && card.toplevel.title ? card.toplevel.title : tip.appName
        elide: Text.ElideRight
        horizontalAlignment: window.previewsEnabled ? Text.AlignHCenter : Text.AlignLeft
        color: window.popupText
        opacity: 0.8
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      onClicked: function(event) {
        var target = card.modelData
        window.tipSlot = null
        if (!target || !window.dock) return
        if (event.button === Qt.MiddleButton) target.toplevel.close()
        else window.dock.bringForward(target)
      }
    }

    // Closes this window. Sits over the preview's top right corner.
    Rectangle {
      id: closeButton

      readonly property int size: Math.max(16, Math.round(window.previewHeight * 0.16))
      readonly property bool shown: window.previewsEnabled && window.previewClose !== "off"
        && (window.previewClose === "always" || cardMouse.containsMouse || closeMouse.containsMouse)

      visible: shown
      width: size
      height: size
      radius: size / 2
      x: Style.spacing.xs + card.thumbWidth - size - Style.spacing.xs
      y: Style.spacing.xs + Style.spacing.xs
      z: 3
      color: closeMouse.containsMouse ? window.closeHoverFill : window.closeFill
      border.width: 1
      border.color: window.previewBorderColor

      // An X drawn from two bars, so it stays crisp at any size.
      Repeater {
        model: [45, -45]

        delegate: Rectangle {
          required property var modelData
          anchors.centerIn: parent
          width: Math.round(closeButton.size * 0.5)
          height: Math.max(1.5, closeButton.size * 0.1)
          radius: height / 2
          rotation: modelData
          antialiasing: true
          color: closeMouse.containsMouse ? window.closeHoverGlyph : window.closeGlyph
        }
      }

      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var target = card.modelData
          if (target && target.toplevel) target.toplevel.close()
        }
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
