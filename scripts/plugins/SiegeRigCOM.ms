----------------------------------------------------
--
-- FILE: SiegeRigCOM.ms
--
-- SiegeRig center-of-mass helper. This object does not take part in the
-- Dungeon Siege hierarchy (it is never linked to a bone), so it has no
-- effect on export. It only carries the rig's saved state, which is
-- stored in the .gmax file with the node:
--
--   figureMode : true while the rig is being edited in Figure Mode
--   rigVersion : SiegeRig data version
--   boneNames  : every bone of the rig, parents before children
--   boneRoles  : role of each bone ("L_thigh", "pelvis", ...) or ""
--   restData   : rest pose, 7 floats per bone (parent-space pos xyz,
--                then rotation quat xyzw), in boneNames order
--
-- Bones are stored by name (not as node references) so that no
-- circular dependency can form between this helper and the skeleton.
--
----------------------------------------------------

plugin simpleObject SiegeRigCOM
  name: "SiegeRigCOM"
  category: "Standard Primitives"
  classID: #(0x5a7c1e21, 0x3b8d4f02)
(
  parameters main rollout:mainParams
  (
    comSize    type:#worldUnits ui:spnSize default:60
    figureMode type:#boolean default:false
    rigVersion type:#integer default:1
    boneNames  type:#stringTab tabSize:0 tabSizeVariable:true
    boneRoles  type:#stringTab tabSize:0 tabSizeVariable:true
    restData   type:#floatTab  tabSize:0 tabSizeVariable:true
  )

  rollout mainParams "SiegeRig COM"
  (
    spinner spnSize "Size:" range:[1,1000,60] type:#worldunits
  )

  on buildMesh do
  (
    -- a simple octahedron marker
    local r = comSize / 2.0
    local v = #([r,0,0], [-r,0,0], [0,r,0], [0,-r,0], [0,0,r], [0,0,-r])
    local f = #([1,3,5], [3,2,5], [2,4,5], [4,1,5], [3,1,6], [2,3,6], [4,2,6], [1,4,6])
    setMesh mesh vertices:v faces:f
  )

  on attachedToNode n do
  (
    n.renderable = false
    n.wireColor = (color 255 170 0)
  )

  tool create
  (
    on mousePoint click do
      case click of
      (
        1: nodeTM.translation = gridPoint
        2: #stop
      )
  )
)
