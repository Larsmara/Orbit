# Position

## Description
The anchor graph, cross-axis size sync, position persistence, and position math for Orbit frames. Axis-parameterized: one implementation handles both orientations.

## Purpose
Owns where every movable Orbit frame lives and how anchored chains stay coherent across reloads, spec swaps, and profile switches. Orientation is a first-class primitive so anchor/sync code never forks into horizontal and vertical copies.

## Implementation
| File | Role |
|---|---|
| Axis.lua | `Engine.Axis.horizontal/vertical` primitives (edges, size/coord accessors, `rowDim`, `independentFlag`, `syncFlag`, `perpendicular`) + `Axis.ForEdge` / `Axis.SyncEnabled` |
| AnchorGraph.lua | pure-data directed graph: virtual/disabled state, cycle detection, targeted reconciliation |
| Anchor.lua | physical + logical anchor graphs, parent→child cross-axis size sync, merge-border state |
| Persistence.lua | save/restore to SavedVariables, pending queue for load-order races, per-spec routing |
| PositionUtils.lua | offset/bounds math, scale-relative icon text offsets via `baseSize` |

`CreateAnchor` / `SyncChild` / `ApplyAnchorPosition` / `BreakAnchor` derive the axis from the anchor edge via `Axis.ForEdge(edge)` and use `axis.perpendicular` for cross-axis sync — one code path, axis flows through. The graph is strictly one-directional: the parent is the source of truth; a frame is influenced only by its immediate parent (if anchored) or its own saved settings (if a root). No chain-walking, no extent aggregation, siblings never see each other.

Sync flags (per frame, per axis): `frame.orbitWidthSync` syncs width from the direct parent when T/B-anchored; `frame.orbitHeightSync` syncs height when L/R-anchored. `Axis.SyncEnabled(frame, axis)` is the single resolver. Opt-outs: `independentWidth` / `independentHeight` anchor options block an otherwise-active sync.

Load order (`EditFrame.xml`): Guard → PositionUtils → Axis → AnchorGraph → Anchor (runs `Graph:Init()`) → Persistence. Axis must load first — AnchorGraph/Anchor import `Engine.Axis` at file scope.

## Gotchas
- Never branch on hardcoded `LEFT`/`RIGHT`/`TOP`/`BOTTOM` in axis-aware code — use `axis.edges[edge]` / `axis.forward` / `axis.backward`. New axis-dependent behavior goes in the Axis table, not as a branch in a consumer.
- Sync is **immediate parent only**, by design. Two L/R-anchored siblings both flagged `orbitWidthSync` do not form a width chain that leaks into their own T/B children — each child reads its direct parent. Do not add extent aggregation.
- Preserved legacy quirk: when an independent flag is set AND `suppressApplySettings` is false, the engine still syncs the cross-axis size and writes the result back to the plugin's saved `Height`/`Width` setting — UnitFrames use it to normalize height when chaining live. Extended symmetrically to `independentWidth` → `Width`. Don't "fix" it.
- Cycle detection runs through `Graph:WouldCreateCycle` before any `CreateAnchor` — pure-data, never geometry reads.
- Attaching or detaching a child never moves the parent.
- The logical/physical graph split, rescue check, pending-anchor queue, and per-spec routing are documented in `../../README.md` — read that before touching Anchor.lua or Persistence.lua semantics.

## Secrets
`Anchor.lua` guards child alpha with `issecretvalue` before the merge-border visibility comparison (OOC-fade alpha can be curve-driven). Frame geometry of Orbit-owned frames is never secret.

## References
`../../README.md` (anchor graph semantics, persistence flows) · `../Selection/README.md` (drag → persistence handoff) · skills: `/pixel` (all offsets go through `Pixel:Snap`), `/wow-frames`.
