# SiegeRig: a Character Studio Equivalent for SiegeMax (gmax)

Plan for adding Biped / Character Studio–style animation tools to the gmax
version of SiegeMax. Constraints come from
[gmax-capabilities.md](gmax-capabilities.md).

## Goals

- Animate Dungeon Siege characters in gmax with a Biped-like workflow:
  a center-of-mass (COM) control, Figure Mode, IK limbs with planted/sliding/free
  feet and hands, posture copy/paste and mirroring, simple footsteps, and a
  clip library.
- Use only what gmax ships with: **MAXScript, IK Limb, constraints,
  Script/Expression/List controllers, custom attributes, Skin**. No new C++;
  `DSiegeUtils.dlu` is unchanged.
- Always export through the existing pipeline: the rig **bakes** to plain
  linear position/rotation keys that `DSiegeUtils.dlu` already understands.
- In 3ds Max (`ProductIs3dsMax()`), keep the option of using real Biped; SiegeRig
  is the gmax path.

## What exists today

| Piece | Location | Relevance |
|---|---|---|
| Skeleton build from ASP (`BoneSys`, grips, `*foot_pin`) | `scripts/ASPImport.ms:760-820` | Starting point for "promote to rig" |
| Skin + weights | `scripts/ASPImport.ms:859-889` | Already the Physique equivalent |
| PRS animation import (linear keys by bone name, `$ROOT` marker) | `scripts/PRSImport.ms:273` | Clip import source |
| Root translation tools, Biped COM branch, `Link_Control` | `scripts/RootTools.ms` | Replace Biped branch with SiegeRig COM |
| Key reduction | `scripts/AnimKeyTools.ms` | Used after baking |
| Pose copy/paste (in-memory) | `scripts/Add-On Examples/PoseTools.ms` | Base for posture tools; `IsBipedBone` stub |
| List controllers on grips | `scripts/AttackTools.ms:395` | Pattern for layered control |
| Note tracks / critical events | `scripts/NoteTrackTools.ms` | Must travel with clips |
| Scripted plugin pattern | `scripts/plugins/GripMarker.ms`, `asp_mod.ms` | Pattern for rig helpers |

## Architecture

```
SiegeRig COM (scripted helper + custom attributes)
 ├─ Pelvis ─ Spine (FK, optional Transform Script "auto-bend")
 │            └─ Neck / Head (FK, optional Look-At on a head target)
 ├─ Leg L/R:  thigh → calf → foot   [IK Limb]  goal ← Link constraint
 │                                             (world / footstep / COM)
 ├─ Arm L/R:  upperarm → forearm → hand [IK Limb] goal ← Link constraint
 └─ Grips (weapon_grip / shield_grip) unchanged
Clip holders (hidden helpers carrying keys + note-track data)
Bake → plain DS skeleton with linear keys → DSiegeUtils export
```

- Constraints are applied to **IK goals and the COM**, never to bones inside
  an IK chain (a gmax rule).
- Rig state (Figure Mode, IK/FK blend, key types, mirror map, rest pose) is
  stored in **custom attributes** on the COM so it saves in the `.gmax` file.

## Phases

### Phase 1 — Rig builder and Figure Mode
Files: `scripts/RigTools/SiegeRigCOM.ms` (scripted helper),
`scripts/RigTools/RigBuilder.ms`.
- Scripted helper `SiegeRigCOM` with custom attributes: `figureMode`,
  limb link counts, height, mirror map, rest-pose storage.
- **Promote existing skeleton**: take an ASP-imported skeleton (correct DS bone
  names already), add the COM, IK goals and controls without renaming bones.
- **Create new skeleton**: build a DS-named skeleton validated against the
  Naming Key.
- Figure Mode: store/restore rest pose (RPOS) in custom attributes; editing
  in Figure Mode updates rest pose, leaving animation keys alone.

### Phase 2 — IK limbs and key types
Files: `scripts/RigTools/LimbTools.ms`.
- IK Limb on thigh→calf→foot and upperarm→forearm→hand; swivel target per
  limb (knee/elbow direction), preferred angles set from rest pose.
- Each goal gets a **Link constraint** with three possible parents:
  world anchor, footstep/prop anchor, COM.
- Buttons equivalent to Biped key types:
  - **Planted** — link goal to world/footstep anchor at this key.
  - **Sliding** — link to world anchor but allow anchor motion.
  - **Free** — link goal to COM (moves with body).
- **IK/FK blend**: IK Limb's enable/disable plus keyed swivel; for FK periods,
  keys go on the bones directly (IK Limb supports mixed FK/IK periods).
- Key all chain bones automatically when a limb key is set (avoids the known
  IK Limb "twitch").

### Phase 3 — COM, spine and root motion
Files: `scripts/RigTools/COMTools.ms`, update `scripts/RootTools.ms`.
- COM carries body translation; `$ROOT` follows COM XY so root motion stays
  correct for export. Replace the `Vertical_Horizontal_Turn` Biped branch in
  `RestoreRootTranslation` / `RemoveRootTranslation` with a SiegeRig branch
  (keep the Biped branch for 3ds Max).
- Optional spine auto-bend: Transform/Rotation Script controller that
  distributes a "spine control" rotation across spine links (like Biped
  spine links). Off by default; baked on export.
- Optional head Look-At target via Look-At constraint in a Rotation List.

### Phase 4 — Posture tools
Files: `scripts/RigTools/PostureTools.ms`, update
`scripts/Add-On Examples/PoseTools.ms`.
- Copy/Paste **Posture / Pose / Track**, **Paste Opposite** (mirror via
  left/right name map in COM attributes).
- Symmetrical / opposite selection; select by track (body, limbs, spine).
- Buffers are in-memory globals plus an optional "Pose library" stored as
  custom-attribute arrays on the COM (no file writes in gmax).
- `IsBipedBone` / `AnimInterpUtil` recognise SiegeRig nodes.

### Phase 5 — Clips (Motion Mixer equivalent, simplified)
Files: `scripts/RigTools/ClipTools.ms`.
- **In-scene clip library**: each clip is a hidden holder node per bone set,
  carrying the keys and note-track events; a clip list lives on the COM.
- **External clip files**: save a clip by `holdMaxFile` → delete all but the
  clip holders → `saveMaxFile "<name>.gmax"` → `fetchMaxFile`; load with
  `mergeMAXFile`. (gmax allows ≤1000 saves per session.)
- Import a **PRS** directly as a clip by reusing `PRSImport.ms` parsing.
- Apply clip to rig with time offset / scale; simple **crossfade** between two
  clips over N frames (per-bone quaternion slerp + position lerp, written as
  keys).
- Any string data kept under the 15,000-character limit (chunk if needed).

### Phase 6 — Footsteps (limited)
Files: `scripts/RigTools/FootstepTools.ms`.
- Place footprint helpers (scripted helper) in the viewport or generate them
  from stride length / count.
- Generate walk/run: planted keys at each footstep (Phase 2 anchors), COM
  path between steps with pelvis bob and sway parameters.
- No Biped dynamics/balance solver.

### Phase 7 — Bake for export (required for any export)
Files: `scripts/RigTools/RigBake.ms`.
- Sample every DS bone per frame in world space, write `linear_position` /
  `linear_rotation` keys (matching `PRSImport.ms` conventions, grips pre-rotated
  as today), remove IK/constraint/script controllers on the baked result.
- Run `dscb_ReducePosKeyList` / `dscb_ReduceRotKeyList` from
  `AnimKeyTools.ms`.
- Work on the live scene inside `holdMaxFile`/`fetchMaxFile` so the rig is
  restored after export; one-click "Bake & Export" wraps `dsExportSelected`.

### Phase 8 — Integration
- `fileIn` the RigTools scripts from `scripts/startup.ms`.
- "SiegeRig" quad-menu section in `scripts/QuadMenus.ms`; dockable panel via
  `cui.registerDialogBar`.
- Help pages in `scripts/HelpTools.ms`.
- Bump `SIEGEMAX_TOOLKIT_MINOR_VERSION` (2.21 → 2.22).

## Status

| Step | State |
|---|---|
| Phase 1: COM helper, promote skeleton, role detection, rest pose, Figure Mode | **Written, not yet run in gmax.** `scripts/plugins/SiegeRigCOM.ms`, `scripts/RigTools/RigBuilder.ms`, `scripts/Add-Ons/InstallSiegeRig.ms` |
| Phase 2 onward | Not started |

Phase 1 is installed as an Add-On (no core file is modified): copy the three
files into the matching folders under `gmax/gamepacks/SiegeMax/Scripts/` and
restart gmax. Then use Customize > Customize User Interface, category
"Siege Rig Tools", action "SiegeRig".

Phase 1 limits worth knowing:
- Figure Mode edits with Animate off, which shifts all keys of an animated
  bone (standard Max behaviour). Animated bones keep their stored rest pose.
- Promoting a skeleton never relinks, renames or re-controls a bone, so
  export is unchanged.
- Roles are detected from bone names; unrecognised bones get no role and can
  be assigned in the panel.

## Order and milestones

1. **M1 (usable):** Phases 1, 2, 7 → rig a DS character, animate limbs with IK,
   bake, export.
2. **M2:** Phases 3, 4 → COM/root motion, mirroring and posture tools.
3. **M3:** Phase 5 → clip library and PRS-as-clip.
4. **M4:** Phase 6 → footsteps; Phase 8 polish throughout.

## Testing

- Round-trip: import stock DS character (ASP + PRS) → promote to rig →
  re-key an idle → bake → export → re-import PRS; compare per-bone transforms
  within the key-reducer tolerances.
- Mirror test: Paste Opposite twice returns the original pose.
- Clip test: save clip to `.gmax`, open a fresh scene with the same skeleton,
  merge and apply; compare keys.
- Run each new tool in both gmax and 3ds Max (`ProductIs3dsMax()` branches).

## Risks

| Risk | Mitigation |
|---|---|
| IK Limb + animated Link constraint on goals behaves badly | Verify first in M1; fallback is keyed goal positions with "snap to anchor" tools |
| Script controllers slow on full skeleton | Keep optional; bake before export |
| Exporter doesn't handle constrained/scripted nodes | Always bake (Phase 7) |
| No file writes | All data in scene; clip files via `saveMaxFile` |
| 1000-save session limit | Warn when clip-saving many files in one session |
