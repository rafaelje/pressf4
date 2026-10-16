---
name: pressf4
description: Native macOS screenshot capture, annotation, and local export.
typography:
  sidebar-title:
    fontFamily: system-ui
    fontSize: 12px
    fontWeight: 500
  sidebar-detail:
    fontFamily: system-ui
    fontSize: 10.5px
  status:
    fontFamily: system-ui
    fontSize: 11px
  measurement:
    fontFamily: ui-monospace
    fontSize: 11px
  zoom:
    fontFamily: ui-monospace
    fontSize: 10px
    fontWeight: 500
rounded:
  thumbnail: 4px
  tool: 5px
  hud-button: 7px
  library-row: 8px
  hud-preview: 10px
  hud-panel: 16px
spacing:
  tools: 4px
  color-controls: 6px
  toolbar-rows: 8px
  toolbar-horizontal: 10px
  status-horizontal: 12px
  panel: 16px
  sheet: 24px
  canvas-inset: 32px
components:
  annotation-tool:
    rounded: "{rounded.tool}"
    width: 30px
    height: 30px
  library-row:
    rounded: "{rounded.library-row}"
    padding: 8px
  hud-button:
    rounded: "{rounded.hud-button}"
    width: 28px
    height: 24px
  hud-panel:
    rounded: "{rounded.hud-panel}"
    padding: 10px
---

# Design System: pressf4

## Overview

**Creative North Star: "The Native Screenshot Workbench"**

This is a descriptive name for the existing implementation, not a newly chosen brand identity. pressf4 uses compact SwiftUI controls and AppKit windows to keep capture history, image editing, and export close together. The image occupies the main workspace; controls use familiar macOS typography, SF Symbols, system surfaces, and the user's accent color.

This record covers the implemented local screenshot interface. It derives from `Sources/Views/EditorView.swift`, `MainWindow.swift`, `PresentationEditor.swift`, `CaptureOptions.swift`, `PinnedCapture.swift`, `ScrollingCapture.swift`, and `ThumbnailHUD.swift`. The editor was visually inspected in `.impeccable/review/mac-editor.png`; the renderer artifact `.impeccable/review/shadow-render.png` was also inspected. Other dialogs and floating panels are documented from source, not claimed as visually verified. No PRODUCT.md or previous DESIGN.md existed. Measurements below are native layout points unless explicitly identified as output-image pixels; frontmatter uses portable CSS pixel notation for those layout measurements.

**Key Characteristics:**
- Native macOS controls and appearance-aware surfaces.
- Compact, separated action, tool, and annotation-control rows.
- A large image workspace beside a narrow capture library.
- Small numerical readouts and restrained selection emphasis.
- Floating capture previews and utility panels for focused tasks.

## Colors

The application chrome uses semantic macOS colors rather than a fixed brand palette. These are intentionally not encoded as invented CSS hex tokens.

### Primary

`Color.accentColor` marks prominent actions, selected tools, selected library thumbnails, selected swatches, and the active HUD corner. Selected tool backgrounds use accent opacity (0.20); selected library rows use (0.18). Save and the empty-state capture action use native bordered-prominent buttons.

### Neutral

`NSColor.windowBackgroundColor` supplies editor chrome and the zoom rail. `NSColor.underPageBackgroundColor` supplies the canvas. The library uses `NSColor.controlBackgroundColor` at half opacity. Text uses primary and secondary foreground roles. Main editor dividers use opacity (0.40); the sidebar footer divider uses (0.30).

The floating thumbnail HUD uses ultra-thin material with white foregrounds and translucent white strokes. Its dark/light appearance is owned by the operating system rather than a forced page theme.

Annotation colors are content choices, not navigation colors. The six-swatch palette is defined by `AnnotationColor.palette` in `Sources/Models/Annotation.swift`. Presentation backgrounds likewise belong to exported images; `PresentationOptions.Background` offers None, White, Charcoal, Ocean, Sunset, and Lavender. Do not apply those output backgrounds to app chrome.

## Typography

Use the native system font and SF Symbols. Default button, menu, form, and semantic text sizes remain platform-owned. There is no custom display typeface or universal web type scale.

Sidebar capture titles use `sidebar-title`; dimensions and file size use `sidebar-detail`. The footer uses `status`. Stroke width uses `measurement`; the zoom readout uses `zoom`. The HUD dimension label uses a medium monospaced system font (10.5 points). Sheet headings use `.title2.bold()`, explanatory text uses `.caption` with secondary foreground, and the empty-state title uses `.title3`.

## Layout

The main window is a `NavigationSplitView` with minimum size (880 × 540 points). The sidebar ranges from (200–320 points), ideally (220 points). Capture rows contain a cropped thumbnail (56 × 36 points), two text lines, and a hover-revealed delete button. A full-width New Capture menu anchors the sidebar footer.

The editor toolbar has three separate rows: capture and output actions; a horizontally scrollable annotation-tool strip; then color, stroke, and undo/redo controls. Preserve these groups when adding controls. The action row begins with Capture and ends with Save. The tool strip scrolls instead of requiring every tool to fit in a single fixed-width row. The stroke slider is hidden for the filled-rectangle tool.

The canvas centers an aspect-fitted image with `canvas-inset` on each side, initially avoiding enlargement above source size. Zooming grows a scrollable document. A right rail (44 points wide) holds zoom controls, a vertical slider, and reset readout. The status footer shows tool, width, annotation count, optional crop reset, and image dimensions.

Style & Export uses `sheet` padding, a controls column (240 points), a preview region (350 × 330 points), and a gap (24 points). Capture Options uses a native form (400 points wide). Recognition results reserve (500 × 300 points) for selectable text. Pinned captures and scrolling capture use resizable utility panels; scrolling starts at (420 × 620 points), with a minimum of (380 × 500 points).

The thumbnail HUD panel is (252 × 208 points) and sits (22 points) from the selected visible-screen corner, clamped within that screen. Its preview keeps a (16:10) aspect ratio so wide captures cannot displace the action bar. This native desktop app has no web or mobile breakpoints.

## Elevation & Depth

Depth combines system window chrome, tonal separation, fine dividers, and deliberate image shadows. The canvas preview uses a black shadow at opacity (0.35), radius (18), vertical offset (6). The floating HUD uses black opacity (0.40), radius (22), vertical offset (10), with the AppKit panel's own shadow disabled.

Exported presentation images have a separate renderer shadow: black opacity (0.28), blur (20), offset (0, 8). The renderer paints the rounded image backing before clipping and drawing its content. That shadow is output styling, independent of the editor canvas shadow. Native shadow values and coordinates are recorded in the sidecar; CSS previews are illustrative only.

## Shapes

The interface uses small rounded rectangles for tools and library rows, larger continuous corners for the HUD, and circles for color swatches, close, and corner anchors. Use the corresponding frontmatter radii without imposing them on system buttons or fields.

Color swatches are circles (20 points) with an accent selection stroke (2 points). Selected library thumbnails use an accent stroke (2 points). The New Capture footer uses a secondary dashed outline (1.5-point stroke, 4/4 dash). The HUD panel has a translucent white border (1 point); its preview has a finer border (0.5 points).

## Components

### Native buttons and menus

Use platform button styles: bordered-prominent for the main committing action, standard native buttons for adjacent actions, plain buttons for tools, and borderless buttons for zoom icons. Retain system focus and disabled states. Capture and New Capture share `CaptureCommands`. Busy recognition reads “Reading…” and disables its action. Icon tools have help text and accessibility labels.

### Annotation tools and controls

Each tool uses an SF Symbol in an `annotation-tool` frame. Selection changes both accent foreground and translucent accent background. Color selection uses the circular swatch stroke. Stroke width has a native slider over (1–10 image pixels) and a monospaced readout. Undo and redo remain at the end of the controls row with their keyboard shortcuts.

### Library rows and empty state

Rows use the `library-row` shape and padding. Selection highlights both row and thumbnail. Hover reveals the circular trash action with a short ease-in-out fade (0.12 seconds); the trash icon and background turn red on its own hover. The empty state centers a large camera-viewfinder symbol, title, brief F4 instruction, and Take Capture action.

### Sheets and forms

Style & Export uses pickers, sliders, toggles, a rounded width field, preset actions, preview, and image/project export actions. Background-dependent controls appear only when a background is selected. Invalid width disables Apply size. Recognition results use selectable text, secondary local-processing context, Copy all/Copied, and Done. Capture Options groups ratio, fixed-size settings, pointer, and desktop visibility using native form controls and dividers.

### Floating preview and utility panels

The thumbnail HUD combines material, fixed-aspect image preview, dimensions, and Pin/Edit/Copy icon buttons. Buttons brighten on hover; close and inactive corner controls become clearer on hover. Entry fades over (0.22 seconds), dismissal over (0.15 seconds), and corner relocation over (0.28 seconds). Pin uses a standard utility window with an image, opacity slider, and Copy action. Scrolling capture presents frame count, instructions, preview, status, and either capture/finish or overlap/discard/add controls; busy capture disables the capture/finish row.

## Do's and Don'ts

- **Do** inherit native semantic colors, typography, controls, and focus behavior.
- **Do** preserve the editor's separate action, tool, and annotation-control rows.
- **Do** distinguish interface styling from exported-image styling.
- **Do** keep numerical metadata compact and secondary.
- **Don't** hardcode the screenshot's dark appearance or blue accent as universal brand colors.
- **Don't** replace the native interface with web navigation, marketing cards, or a new visual identity for a local feature addition.
- **Don't** treat source-inspected dialogs as visually verified screens.
