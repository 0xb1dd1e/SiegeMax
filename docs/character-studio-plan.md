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

### Phase 0 — Data-out channel ("piggyback") — DONE
Files: `scripts/Tests/piggyback.ms`, `scripts/Tests/tools/extract_piggyback.py`,
`scripts/Tests/tools/test_extract_piggyback.py`, `scripts/RigTools/DataOut.ms`.
gmax cannot write files, so anything the rig produces (baked animation, clip data,
diagnostics) has to be smuggled out inside a file gmax *can* write. Everything later in
this plan that needs data outside gmax depends on this step.
- **Codec** (`piggyback.ms`): bytes are packed into the float data of a generated mesh, with a
  header (magic, chunk index/count, byte count, checksum), chunking, optional RLE compaction
  (kept only if it makes the payload smaller), and helpers for strings and 32-bit floats.
  The full layouts are documented in the header comment of `piggyback.ms`.
- **Route A — DSiegeUtils ASP export** (`PiggybackExport`, `Encode`/`Decode`): node name must
  start `M_`; the file lands under `%out%/art` via the Naming Key (no dialog; `dsExportSelected
  noPrompt:true canStomp:true makePath:true`). Face indices do **not** survive (the stripifier
  reorders them and corners are deduped) and positions are scaled by 0.001, so the payload rides
  in vertex positions: 16 bits per float, 4 bytes per vertex, sequence number in `x`, scale
  auto-detected by the reader. **Limit:** corner indices are 16-bit (`ASPexp.h`
  `vector<WORD>`, NvTriStrip), so about 65,535 vertices (~262 KB) per mesh. Verified byte-exact
  at 1 KB, 4 KB, 16 KB, 64 KB, 256 KB, 260 KB and 262,000 bytes (65,502 vertices);
  264,000 bytes (66,002 vertices) produced no file. Larger payloads become several files.
- **Route B — `.gmax` scene file** (`PiggybackSave`, `PB_DenseEncode`/`PB_DenseDecode`, uses
  `saveMaxFile`): no exporter, no Naming Key, no vertex cap, positions unscaled. The payload
  sits in map channel 1 (gmax only has channels -2..1) as 24-bit integers in float32, 9 bytes
  per map vertex (~75% efficient); the map vertices need no faces and survive the save. Verified
  byte-exact at 1 MB (1.4 MB file) and 5 MB (two chunks, 6.7 MB file, about 10 s). This is the
  route `DataOut.ms` uses. The earlier vertex-layout scene save (4.7 MB file for 1 MB) was
  dropped in favour of it.
- **gmax facts learned:** `saveSelected`/`saveNodes` do not exist; `holdMaxFile` /
  `fetchMaxFile` works but shows an "about to fetch" dialog, so the scene is saved whole with the
  payload meshes added and then removed; `saveMaxFile` renames the open scene to the target file
  (check File > Save As before saving real work).
- **Size limit:** MAXScript's own heap, not the format. Building a 20M-element byte array runs
  out of scripter memory even with `heapSize` at 500 MB. About 5-10 MB per call is safe; send
  bigger data as several calls (a baked clip is well under 1 MB).
- **Reader** (`extract_piggyback.py`): reads `.asp` (BVTX chunk, scale auto-detected) and `.gmax`
  (OLE `Scene` stream, dense chunks found by a float32 signature, needs `olefile`), checks magic
  and checksum, joins chunks, RLE-decompresses. `--verify` checks the deterministic pattern used
  by `LimitTest` / `LimitTestSave`; `--text`, `-o`, `--prefix`, `--report`.
- **Tests:** `python scripts/Tests/tools/test_extract_piggyback.py` (12 cases, no gmax needed:
  RLE edge cases, ASP vertex decode incl. corruption, dense-chunk scan inside a fake scene
  stream). In gmax: `TestIt()` and `TestDense()` (in-memory round trips) and the limit probes.
- **API for later phases:** `DataOutSend label bytes` (also `DataOutSendString`,
  `DataOutSendFloats`) in `scripts/RigTools/DataOut.ms` writes `<scene dir>/DataOut_<label>.gmax`;
  one extractor command gets it back. Phase 7 (bake) and Phase 5 (clip files) use it.
- **Run from the listener:** see the comment block at the end of `piggyback.ms` (or use
  Phase 0b so Claude can run them).

### Phase 0b — Claude Link (talking to a running gmax) — DONE
Files: `scripts/ClaudeLink/ClaudeLink.ms`, `scripts/ClaudeLink/gmax_run.ps1`,
`scripts/ClaudeLink/MEMORY.md` (working notes: commands, rules of engagement, gmax traps; read first).
Phase 0 gets data *out*; this lets Claude *drive* gmax and read the answer, so tests no longer
need the user to paste lines and paste output back, while the user keeps control.
- **Dialog ("Claude Link", in gmax):** a top strip with a `STATE: RUNNING|PAUSED|STOPPED`
  label and three small buttons: `II` pause (becomes `>` to resume), `X` emergency stop, and
  `-` / `+` to shrink to a compact strip (175 x 125 px) or expand. Below it a "Conversation"
  rollup (collapsed in compact mode) with the log (`[Claude]` / `[You]` lines) and a "To
  Claude" box with Send. Open it with
  `filein ((GetDir #scripts) + "/ClaudeLink/ClaudeLink.ms")` or let the helper do it (`-Open`).
  A button cannot interrupt a script that is already running; use Esc in gmax for that.
- **Helper (outside gmax, PowerShell):** uses window messages only, no focus changes.
  It reads the dialog's state label first and sends **nothing** unless the state is RUNNING
  (PAUSED, STOPPED, a missing dialog, or an unreadable state all block, exit code 2).
  - `-Status` / `-Read` — state, which listeners are open, the conversation log
  - `-Open` — load the dialog (through the mini-listener)
  - `-Say "text"` — message to the user, shown in the dialog log
  - `-Eval 'code'` — run code and return its value through the log (works with either listener)
  - `-Cmd 'line'` — run a raw line; output is read from the full Listener's output pane
  - `-Full` — target the full Listener's top pane instead of the mini-listener
  - `-ShowListener` / `-HideListener` — open (posted F11) / close (WM_CLOSE) the full Listener
  - `-Watch [-Since N]` — follow the user's on-screen actions: with the Macro Recorder enabled the
    Listener's upper pane receives the MAXScript equivalent of every UI action (object creation,
    `actionMan.executeAction 0 "<id>"` for menu commands)
  - `-Restore` — bring the dialog back if it was minimized (title-bar minimize hides it) and
    strip the minimize/maximize buttons from its frame (`-Open` does the same, so only Close is left)
  - `-Eval 'ClaudeLinkFix()'` — put the window back to its intended size if it drifts
- **How it works (verified in gmax 4.2 build 128):**
  - the Listener's two RICHEDIT panes have control IDs 1002 (input) and 1001 (output) in both the
    full window and the bottom-panel mini-listener; text is read with `WM_GETTEXT`
  - a line is evaluated by posting a **numpad Enter** (VK_RETURN with the extended-key flag);
    plain Enter only inserts a newline
  - the mini-listener's output control only holds its last line, so `-Eval` returns results
    through the dialog log instead
  - Edit > Clear All is `WM_COMMAND 40043` on the full Listener
- **Gotchas found while building it:** a floater's `.title` cannot be set in gmax (silently
  ignored), so state lives in a label; `newRolloutFloater` clamps a new floater to a narrow
  width (136 px for a requested 310, which clips the controls and cannot be widened by hand), so
  `.size` is set again after `addRollout` (`ClaudeLinkFix()`); a rollup panel keeps the
  width it was created with, so controls in the compact strip use fixed `pos:` (flowing
  `across:` controls spread past the compact window's edge); functions used by rollout handlers must be
  forward-declared `global` before the rollout; top pane lines the helper adds are removed
  afterwards so the user's saved one-liners are untouched.
- **Verified:** Say, Eval, Status/Read, both listeners (including the full Listener closed),
  Pause, Resume and Emergency Stop each blocking and unblocking the helper, the user typing in
  the "To Claude" box and Claude reading it, compact/expanded layouts, and the full Listener
  minimized (the helper looks at hidden windows too, so `-Cmd` still reads its output pane).

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
| Phase 0: data-out channel. ASP route verified byte-exact up to 262,000 bytes (the 16-bit corner cap is about 65,535 vertices); scene-file route verified byte-exact at 1 MB (1.4 MB file) and 5 MB (6.7 MB file, ~10 s); `DataOutSend` verified with a text round trip; extractor self-test (12 cases) passes. Practical limit about 5-10 MB per call (MAXScript heap) | **Done.** `scripts/Tests/piggyback.ms`, `scripts/Tests/tools/extract_piggyback.py`, `scripts/Tests/tools/test_extract_piggyback.py`, `scripts/RigTools/DataOut.ms` |
| Phase 0b: Claude Link (dialog + `gmax_run.ps1` helper): run code in gmax, read replies, Pause / Resume / Emergency Stop and the compact layout verified, works with the Listener open, closed or minimized | **Done.** `scripts/ClaudeLink/ClaudeLink.ms`, `scripts/ClaudeLink/gmax_run.ps1` |
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

0. **M0 (prerequisite):** Phase 0 → get data out of gmax so rig results can be inspected.
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
| No file writes | All data in scene; clip files via `saveMaxFile`; data out via the Phase 0 piggyback (ASP export or `.gmax` scene save) |
| 1000-save session limit | Warn when clip-saving many files in one session |
