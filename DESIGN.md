---
name: Cubby
description: A quiet, fast Finder replacement where files come first.
colors:
  workbench-content: "#FCFCFB"
  workbench-content-dark: "#1E1F21"
  workbench-sidebar: "#F1F1EF"
  workbench-sidebar-dark: "#17181A"
  workbench-card: "#FFFFFF"
  workbench-card-dark: "#28292B"
  hairline: "rgba(0, 0, 0, 0.07)"
  hairline-dark: "rgba(255, 255, 255, 0.07)"
  resting-selection: "rgba(0, 0, 0, 0.07)"
  resting-selection-dark: "rgba(255, 255, 255, 0.09)"
  accent: "#007AFF"
typography:
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 400
  body-strong:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 500
  secondary:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 500
  column-header:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 500
  section-title:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 600
rounded:
  row: "6px"
  tile: "8px"
  card: "10px"
spacing:
  hairline: "1px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  gutter: "16px"
  indent: "14px"
  row: "28px"
components:
  file-row:
    height: "{spacing.row}"
    typography: "{typography.body}"
  file-row-selected:
    backgroundColor: "{colors.accent}"
    rounded: "{rounded.row}"
  file-row-selected-resting:
    backgroundColor: "{colors.resting-selection}"
    rounded: "{rounded.row}"
  sidebar-folder:
    backgroundColor: "{colors.workbench-sidebar}"
    typography: "{typography.body}"
    height: "{spacing.row}"
  sidebar-group:
    typography: "{typography.label}"
    height: "{spacing.row}"
  icon-tile-selected:
    backgroundColor: "{colors.resting-selection}"
    rounded: "{rounded.tile}"
  icon-tile-name-selected:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    rounded: "4px"
  icon-button:
    width: "26px"
    height: "24px"
  settings-card:
    backgroundColor: "{colors.workbench-card}"
    rounded: "{rounded.card}"
    padding: "12px 16px"
---

# Design System: Cubby

## Overview

**Creative North Star: "The Quiet Workbench"**

Cubby is a calm, well-lit desk where the files are the work. Surfaces are flat and softly tinted, chrome is thin, and every control waits at the edge until it is needed. Density is the Mac's: 13 pt names in 28 pt rows, a 16 pt gutter, and nothing that pulls the eye away from file names, icons, and thumbnails.

The look comes from tone, not ornament. A slightly darker sidebar sits beside a near-white (or near-black) content plane; hairlines separate only where structure needs it; selection is a soft rounded wash of the accent color. There is no glass, no gradient, no shadow, and no bezel on any control. Everything is native AppKit, drawn with system type and SF Symbols.

The system is built for themes. A theme is a small set of tinted neutrals plus one accent, each defined for light and dark, and every view reads colors only through `Theme` roles, so a new theme never touches layout or components.

**Key Characteristics:**
- Flat, tonal surfaces: sidebar darker than content; cards lighter than the page.
- One accent, used for selection and focus only.
- Borderless, muted controls (secondary label color, 14 pt symbols).
- Rounded selection washes (6 pt rows, 10 pt tiles) that merge across adjacent rows.
- Light and dark are equal citizens; every role has both values.

## Colors

The default "Workbench" theme is a barely warm paper neutral with the macOS accent color as its only hue.

### Primary
- **Accent** (#007AFF, the system accent by default): selection washes at 20% opacity for the focused list or sidebar row, the solid pill behind a focused selected tile name; focus and links ("Open config.json"). The token value is the default blue; at runtime the Workbench theme uses `NSColor.controlAccentColor`, and other themes set their own.

### Neutral
- **Workbench Content** (#FCFCFB light / #1E1F21 dark): the main pane, top bar, list header, and pane headers. The largest surface; files sit directly on it.
- **Workbench Sidebar** (#F1F1EF light / #17181A dark): the full-height sidebar; one step darker than content so the two planes separate without a line.
- **Workbench Card** (#FFFFFF light / #28292B dark): settings cards; one step lighter than content.
- **Hairline** (black 7% light / white 7% dark): the list header's bottom rule, split pane header rules, settings card borders and row dividers.
- **Resting Selection** (black 7% light / white 9% dark): selection when its view is not focused, so the selection stays visible without competing.
- **Text** uses system label colors: label for names, secondary label for dates, sizes, kinds and icons, tertiary label for group headers, separators in the breadcrumb, and inactive pane titles.

### Named Rules
**The One Accent Rule.** The accent appears only as selection, focus, and the rare link. Folder icons, group headers, and toolbar icons are never tinted with it.

**The Theme Contract Rule.** A theme defines exactly these roles, each with a light and dark value: content, sidebar, card, hairline, resting selection, and accent. Views read `Theme` roles only; no view hardcodes a color.

**The Tone Not Line Rule.** Separate planes by tone first. Add a hairline only where tone cannot do the job (list header, card rows, split panes).

## Typography

**Body Font:** SF Pro (system font)
**Label/Mono Font:** SF Pro with monospaced digits for numeric readouts

**Character:** One family at small, even sizes; hierarchy comes from weight and label color, not size jumps.

### Hierarchy
- **Section Title** (600, 13 pt): settings section headings in secondary label color.
- **Body Strong** (500, 13 pt): the current folder in the breadcrumb, settings row titles, the settings header.
- **Body** (400, 13 pt): file names in lists and columns, sidebar folders, breadcrumb ancestors (secondary label).
- **Secondary** (400, 12 pt): list columns other than Name, settings descriptions, icon tile labels.
- **Label** (500, 12 pt): sidebar group headers (tertiary label) and split pane titles.
- **Column Header** (500, 11 pt): list column titles in secondary label; the sorted column uses label color plus an 8 pt chevron.

### Named Rules
**The Small Steps Rule.** Sizes stay within 11-13 pt in the browser. Emphasis is weight (400 to 500) or label color, never a bigger size.

## Layout

The window is a full-height sidebar beside a main pane, with no toolbar and no status bar. The sidebar runs under the traffic lights. The main pane's top bar shares the title bar's height, with the path breadcrumb at the left and three icon buttons (filter, view mode, layout) at the right. Splits (side by side, stacked, three, four) divide the pane area below the top bar; windows have no tabs.

Spacing rhythm: a 16 pt gutter aligns the breadcrumb, the list's first disclosure chevron, list column titles with their cell text, and icon view insets. Rows are 28 pt in the list and sidebar, 26 pt in columns. Sidebar items indent 14 pt per level from an 18 pt start. Selection washes inset 6 pt from list edges and 8 pt in the sidebar. Settings is a centered column up to 640 pt wide, cards with 12/16 pt row padding and 28 pt between sections.

## Elevation & Depth

Flat. There are no shadows, materials, or vibrancy anywhere in the browser. Depth comes from three tonal steps (sidebar, content, card) and the hairline. Menus and the Quick Look panel are system-drawn and keep their system appearance.

### Named Rules
**The No Glass Rule.** No glass buttons, blurred backdrops, or translucency in Cubby's own views. If something needs to stand out, it gets a tone step, not a material.

## Shapes

Soft, small radii that only appear where something is selectable or grouped: 6 pt for row selection washes, 10 pt for icon tile selection, 4 pt for a selected tile name, 10 pt for settings cards. Adjacent selected rows merge into one continuous wash with square inner corners. Thumbnails (not icons) get corners scaled to their size (4 to 12 pt) and a hairline border so white pages stay visible. Nothing else has corners or borders.

## Components

### Icon Buttons
- **Character:** present but silent.
- **Shape:** no border, no background, 26 x 24 pt hit area.
- **Style:** 14 pt SF Symbol in secondary label color. Used for top bar controls (filter, view mode, layout), sidebar footer (settings, new group), and the settings close button.
- **Menus:** view mode and layout open a plain menu from the button with a checkmark on the current choice.

### File Rows (list, columns, sidebar)
- **Style:** no alternating stripes, no grid lines; 13 pt name with a 16 pt file icon.
- **Selected:** a rounded accent wash at 20% (6 pt radius) while focused, resting selection when not; text keeps its normal color.
- **Sidebar:** monochrome folder symbols in secondary label color; missing folders show an orange warning symbol at 60% opacity. Groups have no disclosure triangle: the name in tertiary label is followed by a small chevron and toggles on click.

### Icon Tiles
- **Style:** thumbnail or icon centered above a two-line 12 pt label, Finder-style: the name wraps once and a longer remainder truncates in the middle of the second line. Columns stretch so the grid fills the pane evenly. Icon sizes run from 32 to 512 pt.
- **Selected:** a neutral resting-selection wash (10 pt radius) behind the icon, and a pill behind the name: solid accent with white text while focused, resting selection when not.
- **Gallery:** the preview fills the pane above a strip of thumbnails up to 96 pt.

### Navigation
- **Breadcrumb:** ancestors from home (or Macintosh HD) in secondary label, separated by tertiary "/", the current folder in label color at weight 500. Each part is clickable.
- **Filter:** a small search field that appears beside the filter icon on demand and hides again when empty.

### Cards / Containers
- **Corner Style:** 10 pt.
- **Background:** card role, one step lighter than the page.
- **Border:** 1 pt hairline.
- **Internal Padding:** rows of title plus description on the left, a native control on the right, 12 pt vertical and 16 pt horizontal, hairline dividers inset 16 pt.

### Settings Page
Settings replaces the pane area in the window (never a separate window). Its header shares the top bar's height and position with a close button at the right. Controls are native: switches, borderless pop-ups, and a small slider.

## Do's and Don'ts

### Do:
- **Do** add new colors as `Theme` roles with both light and dark values, and use them from every view through `Theme`.
- **Do** keep the browser within 11-13 pt type and create emphasis with weight or label color.
- **Do** align new content to the 16 pt gutter and 28 pt row rhythm.
- **Do** use native AppKit controls and SF Symbols, made borderless and muted where they sit in chrome.
- **Do** check light and dark, Increase Contrast, and a 100k+ item folder before calling a visual change done.

### Don't:
- **Don't** use glass, blur, vibrancy, gradients, or shadows in Cubby's own views.
- **Don't** tint folder icons, headers, or chrome with the accent.
- **Don't** bring back alternating row stripes, full-width blue selection bars, toolbar glass buttons, or a bottom status bar.
- **Don't** add per-row drawing that costs time on huge folders.
- **Don't** fill a translucent color over a view's whole dirty rect; clip fills to the view's bounds.
