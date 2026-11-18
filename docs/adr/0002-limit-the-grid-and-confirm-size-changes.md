# 0002. Limit the Grid to 5–9 × 4–6 and Confirm Size Changes

- Status: Accepted
- Date: 2026-11-18

## Context

Settings offered 3–15 columns and 2–10 rows, and a new size applied at once. Most of those sizes look wrong on the screens MacStart runs on, and every change of columns shifts icons into new rows and columns, while a smaller grid also pushes apps onto later pages. Changing back does not restore the user's arrangement. Reading a file rejected any size outside the allowed ranges.

## Decision

Settings offers 5–9 columns and 4–6 rows, as one Grid size pop-up. Picking a size asks to confirm first and says what moves; Cancel keeps the old size. Reading preferences or a backup clamps a grid size outside the ranges to the nearest allowed size instead of rejecting the file.

## Alternatives Rejected

- Keep the wide ranges: they produce grids that look broken.
- Keep rejecting sizes outside the ranges: backups and saved settings from before this change, with up to 15 columns or as few as 2 rows, would fail to import or reset every setting to the defaults.
- Separate column and row controls with an Apply button: two controls and a half-applied state for one choice.

## Consequences

A backup with 12 columns imports as 9, and its pages reflow to the smaller grid. The domain model's reading rules and the Settings spec in `docs/ui.md` describe the new behavior.
