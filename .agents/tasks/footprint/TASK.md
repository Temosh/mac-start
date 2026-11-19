---
title: Cut idle memory, its growth, and background CPU
type: bug
owner: agent+human
status: review
depends_on: []
---

## Goal

MacStart runs from login to logout, so at hold it must use no CPU and little memory, and its memory must not grow with use. Idle CPU is already zero. Memory is not small: the running app had 128 MB 9 minutes after launch and 138 MB after 50 minutes, and it grows with every show and folder open. The measured fixes bring it to about 64 MB, flat however often the overlay opens.

## Findings

Measured on 2026-11-19: macOS 27.2.1, a 3024×1964 Retina main display, a 7×5 grid, 4 pages, 95 tiles, and 115 apps. Two sources:

- The running app, read from outside with `top`, `footprint`, `vmmap`, `heap`, and `leaks`. The release app is not debuggable, so `leaks` sees only part of it.
- `harness.sh` in this folder, which runs the real `OverlayView` and `OverlayController` off every display; its header says how. With `MallocStackLogging=1`, `heap` names raw heap blocks by their allocation site.

1. **Idle CPU is zero.** 0.0% CPU, 0 idle wakeups in 15 s samples, 3 threads, and no timers or display links at hold. In 31 minutes, an FSEvents logger on the 3 roots saw no events. Nothing to fix.
2. **The show/hide zoom grows the CoreGraphics glyph cache and costs CPU.** `OverlayView` animates `.scaleEffect(isPresented ? 1 : 1.06)`. SwiftUI redraws every label at each frame's fractional scale, and CoreGraphics caches the glyph bitmaps of every size it draws (`CGGlyphBuilderLockBitmaps`, `CGGlyphBitmapCreate`).
   - Cost: 0.3–0.45 MB of live heap per show+hide, levelling off near +55 MB after about 130 shows. Each show+hide costs 135–147 ms of CPU.
   - Without the SwiftUI scale, live heap stays at 24.1 MB over 200 shows.
   - Fix, measured in the harness: animate the zoom with Core Animation as a `sublayerTransform` on the content, scaled about its center, next to the existing fade, and remove the SwiftUI scale. Live heap stays flat, and a show+hide costs 6.3 ms of CPU. In the app, put the transform on the hosting view's layer, so the blur behind it keeps its size as it does today.
3. **Each icon is stored twice.** Core Animation copies every CGImage used as layer contents into its own shared memory: 95 × 224 KB, about 21 MB. The copy stays alive as long as the CGImage does, and `IconProvider` keeps every image for the life of the app.
   - No effect: pixel format (RGBA or BGRA), 64-byte row alignment, page-aligned buffers, and `Image(nsImage:)` versus `Image(decorative:scale:)`.
   - What works: a CGImage made from an IOSurface-backed `CVPixelBuffer` with `VTCreateCGImageFromCVPixelBuffer` is used without a copy. The footprint drops by 20 MB, and the first frame takes 76 ms instead of 87 ms. The CGImage reports sRGB.
4. **The catalog scan walks every folder under the roots.** Under `/Applications/Unity` alone it walks 58,628 entries of Android SDK content.
   - Cost: each scan takes 370–460 ms of CPU and leaves 16–28 MB of freed-but-dirty heap behind. It runs at launch and on every FSEvents callback.
   - The FSEvents stream is recursive, so a write deep inside any bundle triggers a full rescan about every 2 s while it lasts. Examples: an Xcode, App Store, or Unity Hub install.
   - Every app on this Mac sits at most 5 levels below a root; Unity Hub puts editors at `/Applications/Unity/Hub/Editor/<version>/Unity.app`. Capped at 5 levels, the walk visits 149 entries, finds the same 115 apps, and the scan at launch takes 50 ms of CPU instead of 421 ms. Reading every `Info.plist` costs 13 ms, and display names 8 ms.
   - An unchanged rescan does not invalidate the tiles: on Swift 6.4, `@Observable` skips assignments of an equal value (checked with `withObservationTracking`).
   - Fix: cap the walk at 5 levels; the developer approved this change of the rule "scanned recursively" in `docs/domain-model.md`. Rescan only for FSEvents paths that can change the catalog: a folder whose entries the scan reads, a bundle itself, or a bundle's `Contents` folder. Also rescan for dropped events and a changed root. FSEvents names folders as they were watched, with a trailing slash, at any depth.
5. **The icon cache never evicts.** Its keys are path, version, and pixel size. Updated apps, a new grid size, and a new display scale each add entries, and the old ones stay. Fix: after each prewarm, drop the entries of apps that left the catalog and of sizes no longer used.
6. **The folder zoom leaks the same way as finding 2.** `FolderZoom` scales the panel, with its name field and app labels, from icon size to full size.
   - Cost, with fixes 2–4 in place: 0.48 MB of live heap and about 160 ms of CPU per open+close of a 4-app folder.
   - Isolated: without the panel scale, live heap is flat. The animated 8 pt backdrop blur does not leak; it costs about 20 ms of CPU per open+close.
   - The fix changes how the panel looks while it opens. Per the workflow rules, render the options side by side first:
     - A: only the glass shape grows out of the icon, and the name and apps fade in at full size.
     - B: the whole panel zooms through Core Animation in its own layer. It looks the same as today, but the edit bar and the dragged tile must stay above it.
7. **Smaller cases of the same cause, not measured.** These are animated scales over text or SF Symbols: a folder drop target grows its whole tile to 1.15, and the hover raise scales the edit badge's `checkmark` symbol in edit mode. Each should add only one tile's glyphs per event to the same capped cache.
8. **SwiftUI's context menu has a retain cycle.** `ContextMenuResponder` and `ContextMenuResponder.AppKitMenuDelegate` keep each other alive, about 20 KB per context menu shown. It is a framework bug, and no fix is planned.

Measured and rejected:

- Releasing the overlay's views on hide. Live heap drops by 17 MB, but the memory stays dirty in malloc, so the footprint barely moves (91.6 → 91.2 MB). Each show then rebuilds the views in about 60 ms instead of reshowing them in 18 ms.
- `malloc_zone_pressure_relief`: it returned nothing.
- Autorelease pools around the scan and the icon rendering: they saved 0.9 MB.

Harness, as shipped and with fixes 2–4:

| | As shipped | Fixes 2–4 |
|---|---|---|
| Scan at launch | 421 ms CPU | 50 ms CPU |
| Footprint after 30 shows | 109.6 MB | 63.5 MB |
| Footprint after 130 shows | 154.5 MB | 63.5 MB |
| Live heap after 130 shows | 81.7 MB | 24.1 MB |
| CPU per show+hide | 135–147 ms | 6.3 ms |

## Scope

Done, waiting for the developer's check by hand:

- `OverlayController`, `OverlayPanel`, and `OverlayView`: the show/hide zoom runs in Core Animation, with the same 1.06 scale, 0.2 s ease-out, and Reduce Motion behavior.
- `IconProvider`: IOSurface-backed bitmaps, and a prune in every prewarm.
- `CatalogScanner`: a depth cap of 5 levels, with a fixture test for 5 and 6 levels.
- `CatalogWatcher`: rescans only for the paths that `CatalogChangeFilter` in `MacStartCore` lets through. The filter has unit tests.
- Docs: `docs/architecture.md` (the show and hide animation, app discovery, icons, source layout, testing) and `docs/domain-model.md` (the catalog scan).

Left, after the developer picks an option: the folder zoom (finding 6) and the smaller cases (finding 7).

## Acceptance Criteria

- `harness.sh controller 200`: the footprint stays within 2 MB of its value after the warm-up, and live heap does not grow.
- `harness.sh folders 100`, once finding 6 is done: live heap does not grow.
- A rescan costs under 30 ms of CPU, and an FSEvents path inside a bundle below `Contents/` triggers no rescan.
- The developer sees the same zoom and fade as before, and the same icons.

## Verification

- `swift build`, `swift test`, and `scripts/build-app.sh`.
- `.agents/tasks/footprint/harness.sh controller 200`, `.agents/tasks/footprint/harness.sh folders 100`, and `.agents/tasks/footprint/harness.sh zoom`, which checks the zoom's center and end values. Nothing shows on screen.
- The running app at hold: `footprint <pid>`, `vmmap --summary <pid>`, and `top -l 2 -s 15 -pid <pid> -stats pid,cpu,idlew,mem`. Read them right after launch and again after a day of normal use.
- By hand, done by the developer: the show/hide animation, icons on every page, in search, in folders, and in Settings → Hidden Apps.

## Notes

- `harness-main.swift` is the harness entry point. `harness.sh` copies `Sources/` to `$TMPDIR/macstart-footprint-harness`, patches the copy of `OverlayController` to stay off-screen, and builds it there. The script refuses to run when that patch does not apply.
- The findings' numbers came from extra switches that patched the copied sources: IOSurface icons, Core Animation zoom, the depth cap, and no folder scale. Those switches are not kept. Now that the fixes are in `Sources/`, the plain harness measures them.
- Fixes 2–5 landed on 2026-11-19; nothing is committed yet. Harness results on the fixed sources:
  - `controller 200`: footprint 63.4 MB after the warm-up and 63.6 MB after 200 more shows, with live heap flat at 24.0 MB. A show+hide costs 5.4–7.6 ms of CPU.
  - `zoom`: the zoom is centered (1.06, offset −54, −35.07 on an 1800×1169 pt display), runs through 1.042 mid-hide, and ends at identity after SwiftUI updates.
  - `watch`: a write inside a bundle's `Resources` reports no change, and a new app reports one.
  - `rescan`: a rescan costs 27–32 ms of CPU.
  - Not covered by the harness: the folder zoom still leaks (finding 6).
- FSEvents can deliver changes made just before a stream starts, and it names a root reached through a symbolic link by its real path. `CatalogChangeFilter` knows each root by both paths, and it uses `realpath`, because `URL.resolvingSymlinksInPath()` drops the `/private` in front of `/var`.
- Running app when this note was written: PID 2301, 0.0% CPU at hold, 14.1 s CPU in 50 minutes, 138 MB footprint. Of that: Malloc Small 70 MB (33 MB live), CoreAnimation 23 MB, CG Raster Data 21 MB.
