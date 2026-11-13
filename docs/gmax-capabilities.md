# gmax 1.2 Capabilities for Character Animation

What gmax 1.2 provides (and withholds) for building a Character Studio–style
animation system in SiegeMax.

## Sources

- **gmax 1.2 help** (`gmax12_help.exe` → `help/gmax.chm`, `help/maxscript.chm`).
  The MAXScript reference has a gmax-specific chapter, *"Globals, Classes,
  Methods, and Interfaces Not Supported in gmax"*, plus *"Additional Classes and
  Globals Defined in gmax"*. The help files are Autodesk material and are not
  stored in this repo.
- **SiegeMax scripts in this repo** — features already used by working code are
  marked ✅ *used*.

## Summary table

| Area | Available in gmax | Not available in gmax |
|---|---|---|
| **IK solvers** | **IK Limb solver only** — *"In gmax, the only IK Solver available is the IK Limb Solver."* Legacy Hierarchy-panel IK (Interactive IK, Applied IK). `iksys` interface. `IK_Chain_Object` ✅ *used* (`RootTools.ms`) | HI solver (`IKHISolver`), HD solver (`HDIKSys`), Spline IK |
| **Constraints** | Position, Orientation, Look-At, Path, Link ✅ *used* (`Link_Control`, `RootTools.ms`), Attachment, Surface | — |
| **Controllers** | Bezier ✅, Linear ✅, TCB, Euler XYZ, Smooth Rotation, Position XYZ, Scale XYZ, PRS, List ✅ (`AttackTools.ms`), Expression, Script (Float / Position / Point3 / Rotation / Scale / **Transform**), Noise, On/Off, Block, Master Point, Barycentric Morph, Color RGB | Reactor (Float/Point3/Position/Rotation/Scale), Spring (Position/Point3), Motion Capture, Waveform, Audio, LOD, Dynamics |
| **Rig plumbing** | Custom attributes (UI + scripted `attributes`), wire parameters (`paramWire`), scripted plugins: helper, simpleObject ✅ (`GripMarker.ms`), modifier ✅ (`asp_mod.ms`), simpleMod, **simpleManipulator**, scripted controllers, mouse tools, right-click menus, utilities | — |
| **Bones / skinning** | Bones system (`BoneSys`) ✅, Skin modifier + `skinOps` ✅ (`ASPImport.ms`) | `skinOps.saveEnvelope`, Physique, Flex (`flexOps`) |
| **Character Studio** | — | Biped, Physique, Motion Mixer, Footsteps (appear only in the trademark list) |
| **File reading** | `openFile` (read), `fopen "rb"` + `ReadFloat`/`ReadLong` ✅ (`PRSImport.ms`), `getFiles`, `getFileSize` (new), `memStreamMgr` / `memStream` fast parser (new) | — |
| **File writing** | `saveMaxFile` (≤1000 saves per session), `holdMaxFile`/`fetchMaxFile`, `mergeMAXFile`, `colorMan.SaveIconFile` (one ≤260-char string — not practical) | Opening files for **write or append**, `createFile`, `makeDir`, `copyFile`, `renameFile`, `setFileAttribute`, `setINISetting`, `openLog`, `saveNodes`, `encryptFile` |
| **OS / misc** | `cui.registerDialogBar` (dockable rollouts, new), `SubRollout` (new), `callbacks` ✅ | `DOSCommand`, `ShellLaunch`, `createOLEObject`, `render`, `CreatePreview`, `schematicView` |
| **Limits** | — | Strings ≤ **15,000 characters**; `memStream.readToken`/`readBlock` ≤ 5,120 characters |

## Rules that shape the design

1. **IK Limb is a two-bone analytic solver.** It needs a three-bone chain
   (goal sits on the third bone's pivot); the first joint must be spherical
   (3 DOF) and the second revolute (1 DOF). It supports a swivel angle and
   preferred angles, and allows mixing FK and IK periods in one animation.
2. **Constraints vs. IK:** *"Constraints can be applied to bones as long as an
   IK controller is not controlling the bones. If the bones have an assigned IK
   controller, you can only constrain the root of the hierarchy or chain."*
   Drive IK **goals** with constraints instead of the bones themselves.
3. **Script controllers** can use the full MAXScript language and read any
   scene property at any time — the main tool for spine/neck automation that
   Biped normally provides.
4. **No script-written data files.** Anything persistent (clips, poses, rig
   settings, weight presets) must live inside a `.gmax` scene: custom
   attributes, user properties, note tracks, or keys on hidden holder nodes.
   Separate clip files are possible only as small `.gmax` scenes written with
   `saveMaxFile` and brought back with `mergeMAXFile`.
5. **Exporting is done by `DSiegeUtils.dlu`**, which reads node transforms,
   so every rig must be bakeable to plain position/rotation keys.

## Still to verify inside gmax

- IK Limb goals driven by animated Link constraints (planted/sliding feet).
- Cost of Transform Script controllers on a full DS skeleton at playback.
- `saveMaxFile` on a held, stripped-down scene followed by `fetchMaxFile`
  (clip-file workflow) without losing the working scene.
- Whether `DSiegeUtils.dlu` exports correctly from nodes with constraint or
  script controllers, or whether a bake is always needed (assume bake).
