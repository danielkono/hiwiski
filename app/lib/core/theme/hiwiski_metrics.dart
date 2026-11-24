import 'package:flutter/widgets.dart';

/// The measurements from the design, as far as they are not already in a widget theme.
///
/// Numbers without a unit are logical pixels -- identical to the design's CSS
/// pixels.
@immutable
class HiwiskiMetrics {
  const HiwiskiMetrics();

  // --- Spacing -----------------------------------------------------------------
  // The steps from the design. A spacing that is not listed here is not one.
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space28 = 28;
  static const double space32 = 32;

  // --- Corners -----------------------------------------------------------------
  // Corners are not uniform, and that is on purpose: text fields are almost square at
  // 6, cards soft at 16, sheets round at 28. That separates "you type here" from
  // "you read here" from "this lies on top".
  static const double radiusField = 6;
  static const double radiusChip = 8;
  static const double radiusMenu = 12;
  static const double radiusCard = 16;
  static const double radiusWidget = 20;
  static const double radiusSearch = 26;
  static const double radiusSheet = 28;

  /// Thin bars and strips: the calendar strip, progress bars, event bars.
  static const double radiusBar = 2;

  /// Events in the week and day timeline.
  static const double radiusEvent = 4;

  /// A stadium: the ends are half circles, whatever the height. The renderer scales
  /// a radius larger than half the side down to exactly half.
  static const double radiusPill = 999;

  // --- Lines -------------------------------------------------------------------
  /// Dividers, thin borders and the one-pixel gaps between neighbouring blocks.
  static const double hairline = 1;

  /// A selected or focused border, a spinner, a line that has to be seen.
  static const double strokeBold = 2;

  /// Color bars and progress bars.
  static const double barHeight = 4;

  // --- Icons -------------------------------------------------------------------
  // The icon sizes from the design. A size that is not listed
  // here is not one.
  /// Inline in text, small status symbols.
  static const double icon16 = 16;

  /// Chips and buttons.
  static const double icon18 = 18;

  /// List rows.
  static const double icon20 = 20;

  /// Form rows.
  static const double icon22 = 22;

  /// Navigation and icon buttons.
  static const double icon24 = 24;

  /// The checkbox in lists.
  static const double icon26 = 26;

  /// The item title.
  static const double icon28 = 28;

  /// Empty states and confirmations.
  static const double icon48 = 48;

  // --- Avatars -----------------------------------------------------------------
  // `CircleAvatar` takes a **radius**, not a diameter.
  static const double avatarSmall = 13;
  static const double avatarMedium = 18;
  static const double avatarLarge = 20;
  static const double avatarXLarge = 26;

  /// The own profile on the account page.
  static const double avatarProfile = 40;

  // --- Dots, swatches and tiles ------------------------------------------------
  /// The event dots in the month grid, the "now" marker.
  static const double dotTiny = 6;

  /// Color dots (10 / 14 / 28).
  static const double dotSmall = 10;
  static const double dotMedium = 14;
  static const double dotLarge = 28;

  /// A color to pick in a color picker.
  static const double swatchSize = 32;

  /// The square tile behind a symbol in a row: list kind, device, search hit.
  static const double tileSize = 40;

  /// The product mark on the sign-in pages.
  static const double logoSize = 56;

  // --- Elevations --------------------------------------------------------------
  /// Menus and suggestion lists.
  static const double elevationMenu = 3;

  /// A card while it is being dragged.
  static const double elevationDrag = 8;

  // --- Text --------------------------------------------------------------------
  /// The line height of the dense labels in the week timeline, as a factor of the
  /// font size.
  static const double lineHeightTight = 1.15;

  // --- Page margin -------------------------------------------------------------
  static const EdgeInsets pagePaddingCompact = EdgeInsets.symmetric(
    horizontal: space16,
  );
  static const EdgeInsets pagePaddingWide = EdgeInsets.symmetric(
    horizontal: space32,
  );

  // --- Breakpoints -------------------------------------------------------------
  // 1024 instead of Material 3's 840: from here on three columns fit side by side --
  // content up to 680 plus info bar 260 plus margins. At 840 the info bar would be a
  // strip. The deviation is deliberate.
  static const double breakpointMedium = 600;
  static const double breakpointWide = 1024;

  /// From here the navigation is the drawer; below it, down to 600, the rail. An
  /// iPad upright is 1032 wide: with the drawer's 260, the wiki's tree and the info
  /// bar beside it, its articles were left a strip of 170.
  static const double breakpointDrawer = 1200;

  // --- Columns -----------------------------------------------------------------
  /// The reading width of a wiki article.
  static const double contentMaxWidth = 680;

  /// The info bar on desktop.
  static const double infoRailWidth = 260;

  /// The narrowest content the info bar may stand beside. With less room it goes
  /// below the content, as on the phone: a column of 190 broke "Servings" into one
  /// letter per line.
  static const double readingMinWidth = 480;

  /// The page tree in the wiki.
  static const double treeWidth = 280;

  /// The drawer from 1200. Flutter's default is 360, which is too wide.
  static const double drawerWidth = 260;

  /// The collapsed drawer.
  static const double drawerCollapsedWidth = 80;

  /// The navigation rail between 600 and 1199. Flutter's default is 72.
  static const double railWidth = 80;

  // --- Minimum widths of card grids -------------------------------------------
  // A card grid in this specification always means: equally wide columns, as many as
  // fit at the given minimum width, at least one.
  static const double gridMinTodoList = 280;
  static const double gridMinWidget = 320;
  static const double gridMinGroup = 200;
  static const double gridMinRecipe = 200;

  // --- Individual components -------------------------------------------------
  /// Text field, full height.
  static const double fieldHeight = 56;

  /// Text field in a sheet.
  static const double fieldHeightSheet = 52;

  /// Search field.
  static const double searchHeight = 52;

  /// The strip on the left of an event.
  static const double calendarStripeWidth = 4;

  /// The strip in a calendar's colour at the start of an event's row.
  static const double eventStripeHeight = 36;

  /// Loading strip below the bar. It **always** takes up its height -- an indicator
  /// that only appears while loading pushes everything below it down, and whoever is
  /// just aiming misses.
  static const double progressStripHeight = 3;

  /// Smallest tap target: 48 × 48, what Android asks for (iOS asks for 44). Material
  /// controls get it from `MaterialTapTargetSize.padded`; everything built from an
  /// `InkWell` takes it from here. `test/a11y/` measures it on every screen.
  static const double minTapTarget = 48;

  /// The width of a dialog.
  static const double dialogMaxWidth = 520;

  /// The sign-in and server pages.
  static const double authMaxWidth = 400;

  /// Lists that are not a card grid, forms and settings pages: tags, calendars, the
  /// to-dos of a list, the account. **The reading width**, the same as an item's own
  /// page ([contentMaxWidth]): with 560 for the account, 680 for a task and 720 for
  /// its list, the content's right edge moved on every step through the app.
  static const double listMaxWidth = contentMaxWidth;

  /// The space below the last row, so the floating action button covers nothing.
  static const double fabClearance = 96;

  /// A button.
  static const double buttonHeight = 48;

  /// The one button that matters on a sign-in or setup page.
  static const double buttonHeightLarge = 52;

  /// A filled icon button next to a field.
  static const double iconButtonSize = 48;

  /// A row with a symbol and a field in a form.
  static const double formRowHeight = 48;

  /// A list row (52-64).
  static const double listRowHeight = 52;

  /// A list row with a second line.
  static const double listRowHeightTall = 64;

  /// A row in a dashboard tile: an appointment, a to-do.
  static const double tileRowHeight = 36;

  /// A row in a dashboard tile on the kiosk.
  static const double tileRowHeightKiosk = 44;

  /// A chip that holds an avatar or a tag.
  static const double chipHeight = 32;

  /// The filter bar of a page, at least: a button with its touch target (44 drawn,
  /// 48 on the phone), so that the start screen's "Customize" fits as well as tag
  /// chips — and the content below starts at the same height on every page.
  static const double filterBarHeight = 48;

  /// A short number field: an interval, an amount.
  static const double shortFieldWidth = 64;

  /// A label column in front of a value: an amount, a size, a field name.
  static const double labelColumnWidth = 80;

  /// A suggestion list below a field.
  static const double suggestionWidth = 340;

  // --- Calendar ----------------------------------------------------------------
  /// The time column in an agenda row.
  static const double eventTimeColumnWidth = 44;

  /// The time column in an agenda row on the kiosk.
  static const double eventTimeColumnWidthKiosk = 64;

  /// The calendar strip in an agenda row.
  static const double calendarStripeHeight = 32;

  /// The calendar strip in an agenda row on the kiosk.
  static const double calendarStripeHeightKiosk = 40;

  /// The date column of the day list.
  static const double dateBadgeWidth = 52;

  /// The circle around the date in the day list.
  static const double dateBadgeCircle = 36;

  /// A day in the month grid.
  static const double monthCellHeight = 52;

  /// The circle around the date in the month grid.
  static const double dayCircle = 32;

  /// The circle around the date in the week header.
  static const double dayCircleCompact = 22;

  /// The hour labels left of the week timeline.
  static const double weekGutter = 34;

  /// The day names above the week timeline.
  static const double weekHeaderHeight = 40;

  /// The day names above the week timeline on the kiosk.
  static const double weekHeaderHeightKiosk = 46;

  /// An all-day bar in the week view, and the "more" row below them.
  static const double weekBarHeight = 18;

  /// The week timeline in a dashboard tile: a working day.
  static const double weekTimelineHeight = 260;

  /// The week timeline in a dashboard tile on the kiosk.
  static const double weekTimelineHeightKiosk = 380;

  /// The card an event opens into in the week view — on hover, or a long press.
  static const double weekPreviewWidth = 340;
  static const double weekPreviewMaxHeight = 420;

  // --- Board, lists, wiki ------------------------------------------------------
  /// A column of the kanban board.
  static const double kanbanColumnWidth = 280;

  /// How close to the left or right edge a held card moves the kanban board.
  static const double kanbanEdgeZone = 48;

  /// How far the wide kanban board scrolls per frame while a card is held at its edge.
  static const double kanbanEdgeScrollStep = 12;

  /// Where a dragged kanban card sits under the pointer: held a little inside its top
  /// left corner.
  static const Offset kanbanDragOffset = Offset(-24, -20);

  /// A shopping row while it is dragged into another category.
  static const double dragFeedbackWidth = 320;

  /// How close to the edge of a list a dragged row starts scrolling it.
  static const double dragAutoScrollEdge = 72;

  /// The narrowest column of the kanban preview in a dashboard tile.
  static const double kanbanMiniColumnWidth = 132;

  /// The drop target in a kanban column.
  static const double kanbanDropHeight = 56;

  /// A tile while it is being dragged on the dashboard.
  static const Size dragFeedbackSize = Size(200, 120);

  /// The narrowest cell of the board grid: below it the tiles stack in reading order,
  /// on the dashboard and the kiosk alike.
  static const double boardMinCell = 150;

  /// One level of the wiki tree.
  static const double wikiIndent = 22;

  /// The recipe image in the grid.
  static const double recipeImageHeightGrid = 130;

  /// The recipe image on the recipe page.
  static const double recipeImageHeight = 200;

  /// The recipe image on the recipe page, wide layout.
  static const double recipeImageHeightWide = 240;

  /// An image or a stack of images in a page's text, at most this wide.
  static const double pageImageMaxWidth = 440;

  // --- The formatted editor ---------------------------------------------------
  /// The font size Markdown syntax is drawn at where it is hidden: small enough to take
  /// no room, not zero — a glyph of size 0 has no position for the cursor.
  static const double editorHiddenGlyph = 0.01;

  /// What each space in front of a list item adds to its width — two spaces nest an
  /// item, and drawn as plain spaces they hardly showed.
  static const double editorIndentSpacing = 8;

  /// The column a list item's bullet stands in.
  static const double editorBulletWidth = 18;

  /// An image in the text while it is edited: a thumbnail on its line, not the stack.
  /// Its width follows the image, so that it is neither cut nor framed by empty space.
  static const double editorImageHeight = 96;

  /// The widest a thumbnail gets — a panorama is cut to this. Narrower than the field
  /// on the smallest phone: an image wider than its line would push the rest of its
  /// Markdown onto a line of its own.
  static const double editorImageMaxWidth = 240;

  /// The narrowest a thumbnail gets — a tall screenshot is cut to this, rather than
  /// shrinking to a sliver.
  static const double editorImageMinWidth = 48;

  /// How far each image behind the front one in a stack peeks out.
  static const double imageStackStep = 8;

  /// From this width on a recipe shows its image and ingredients side by side.
  static const double recipeTwoColumnWidth = 660;

  // --- Mind maps ---------------------------------------------------------------
  // Canvas measurements are in the map's own units, a logical pixel at a zoom of 1.

  /// A new note, as it is dropped on the canvas.
  static const Size mindmapNoteSize = Size(220, 120);

  /// A snippet of plain text is as large as its text; it wraps from this width on,
  /// or from the width it is resized to.
  static const double mindmapPlainWrap = 320;

  /// A new picture fits into this, in the picture's own shape.
  static const Size mindmapImageSize = Size(240, 240);

  /// Between elements placed together — pictures chosen at once, side by side.
  static const double mindmapRowGap = space24;

  /// A new member: their picture in a circle.
  static const Size mindmapMemberSize = Size(120, 120);

  /// A new link: the target's symbol and title on one line.
  static const Size mindmapLinkSize = Size(240, 56);

  /// A link element showing its target's content grows to at least this — room to
  /// read the preview in.
  static const Size mindmapLinkContentSize = Size(360, 420);

  /// The editing controls in the corner, on rings around the screen's corner: the
  /// button in the middle [mindmapCornerMargin] clear of the safe area, the buttons'
  /// ring [mindmapCornerRingGap] further out, on a larger screen the choices' ring
  /// [mindmapCornerRingStep] beyond that.
  static const double mindmapCornerMargin = 4;

  /// How far above an element the knob to turn it stands, on screen.
  static const double mindmapRotateReach = 28;

  /// A mind map's grid: its spacing in the map's units, its dots' radius and the
  /// least room between them on screen (more zoomed out, every other is left out);
  /// and how long the mark at each end of an equal gap is, on screen.
  static const double mindmapGrid = 24;
  static const double mindmapGridDot = 1.2;
  static const double mindmapGridMinGap = 8;
  static const double mindmapGapTick = 5;

  /// How near on screen a moved or resized element snaps to another's line.
  static const double mindmapSnapReach = 6;

  /// An arrow head on a connection, at least, on screen.
  static const double mindmapArrowHead = 10;
  static const double mindmapCornerRingGap = 64;
  static const double mindmapCornerRingStep = 56;

  /// One choice on a ring, the room between two, and the room the quarter leaves
  /// around them.
  static const double mindmapCornerOption = 44;
  static const double mindmapCornerSpacing = 6;
  static const double mindmapCornerPadding = 10;

  /// How far around the finger the eraser takes a stroke, on screen.
  static const double mindmapEraser = 12;

  /// The pen's widths to choose from, on screen, and the widest of its own.
  static const List<double> mindmapPenWidths = [2, 4, 8, 16];
  static const double mindmapPenMaxWidth = 100;

  /// A line's or a stroke's thickness to choose from, on the map.
  static const List<int> mindmapLineWidths = [1, 2, 4, 8, 16];

  /// The room between an element and the frame around it while it is selected or
  /// found — on screen, at every zoom.
  static const double mindmapFrameGap = 6;

  /// The smallest an element is resized to — still large enough to grab again.
  static const double mindmapMinElement = 32;

  /// The free room around the drawn elements, in which the connection handles and the
  /// selection's frame still take taps.
  static const double mindmapSceneMargin = 96;

  /// A mind map as a picture: the room around it, how sharp — pixels per unit —
  /// and its longest edge at most, in pixels.
  static const double mindmapPictureMargin = 24;
  static const double mindmapPictureScale = 2;
  static const double mindmapPictureMaxEdge = 4096;

  /// The dot on an element that a connection is drawn from — small on screen; its tap
  /// area is a full target around it.
  static const double mindmapHandle = 14;

  /// How far apart lines between the same two elements bend.
  static const double mindmapEdgeSpread = 36;

  /// The widest a connection's label grows before it wraps.
  static const double mindmapLabelMaxWidth = 180;

  /// The preview on the page: never taller than this, however tall the map.
  static const double mindmapPreviewMaxHeight = 360;

  /// And never flatter than this, however wide.
  static const double mindmapPreviewMinHeight = 180;

  /// The field a colour of one's own is picked in: saturation across, brightness up.
  static const double colorFieldHeight = 180;

  /// The strip of hues below it.
  static const double hueStripHeight = 28;

  /// The ring that marks the picked point on either.
  static const double colorThumb = 22;

  /// The search results beside the canvas, from the medium width on.
  static const double mindmapResultsWidth = 320;

  /// The page's title in the header over the canvas while the search fills the rest
  /// of the line: never wider than this.
  static const double mindmapTitleWhileSearching = 280;

  /// The room the bar deciding a conflict takes at the canvas's foot, for the camera
  /// to show the two versions above it.
  static const double mindmapConflictBarHeight = 220;

  /// How far this device's version of an element in conflict stands beside the map's
  /// when the two differ only in their look.
  static const double mindmapConflictGap = 24;

  // --- Invitations -------------------------------------------------------------
  /// The QR code of a new invitation.
  static const double qrCode = 160;

  /// The QR code of a board's address, scanned from across a room.
  static const double qrCodeLarge = 240;

  /// One character of the invite code.
  static const Size codeCellSize = Size(40, 52);
}
