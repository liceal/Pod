# Pixel2Motion Spec: Folder Media Icon

## Source

- Source raster: `source.png`
- Size: 386 x 373 px, RGBA.
- Semantic parts: rounded blue app tile, rear paper sheet, vertical film strip, front paper sheet, translucent folder body, folder lip/highlight.
- Geometry approach: primitive composites only. The source is a soft app icon built from rounded rectangles and simple masks, so traced pixel contours were avoided. Smoothness is prioritized over reproducing the screenshot's antialiasing and checkerboard transparency artifacts.

## Motion Brief

- Personality: friendly, polished, useful.
- Preset: friendly / approachable, adjusted upward to a 1500ms splash reveal.
- Usage context: splash-style brand intro with a static final state.
- Choreography: scale-pop app tile first, then folder rises, papers cascade into place, film strip drops in last as a media accent. All parts settle back to the verified final SVG.

## Structure

- `#logo`: root shared-clock transform.
- `#icon-bg`: blue rounded app tile.
- `#paper-back`: rear sheet.
- `#film-strip`: vertical media strip clipped inside rear sheet.
- `#paper-front`: front sheet.
- `#folder`: folder body and lip group.
- `#folder-lip`, `#edge-highlight`: front edge emphasis.

## Timeline

Total duration: 1500ms.

| Phase | Time | Purpose | Principles |
|---|---:|---|---|
| Anticipation | 0-300ms | logo coils down and tile establishes silhouette | anticipation, staging |
| Action | 300-1050ms | folder and papers assemble with staggered offsets | timing, arcs, slow in/out |
| Follow-through | 1050-1500ms | overshoots settle to exact static geometry | follow through, overlapping action, appeal |

## Easing Tokens

```css
--p2m-duration: 1500ms;
--p2m-ease-enter: cubic-bezier(0.25, 0.46, 0.45, 0.94);
--p2m-ease-settle: cubic-bezier(0.22, 1, 0.36, 1);
--p2m-ease-pop: cubic-bezier(0.34, 1.56, 0.64, 1);
```

Inside `@keyframes`, easing values are written as literal `cubic-bezier(...)` declarations so Chromium does not silently fall back to linear timing.

## QA Notes

- Smoothness gate: passed visually for intended smooth shapes. Geometry uses `rect`, `path` with rounded corners, masks, gradients, and filters rather than jagged threshold traces.
- Known residuals: the raster source contains screenshot-style soft shadows and checkerboard/alpha edge context. The SVG intentionally simplifies those into editable gradients and soft shadows; this may lower silhouette IoU compared with a bitmap trace, but preserves clean vector geometry.
- Final Frame Contract: final animation keyframes end at `opacity: 1` and identity transforms for all choreographed parts, matching the static `logo.svg` geometry.

## Atomic Motions

- Hover: small scale/rotation response.
- Pulse: gentle breathing of the static mark.
- Arc: rotational spring preview.
- Press: squash/stretch micro-interaction.
