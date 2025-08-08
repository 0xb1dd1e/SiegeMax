-- Dungeon Siege SNO Import (Siege Max)
-- Lance ><>
-- 8/20/2002

-------------------------------------------------------------------------------------------
-- Updates & Hacks
--
--  4/30/2025 biddle - parse BSP info, try to locate the diffuse map
--  5/01/2025 biddle - build up indexed corner data, avoid need to weld edges
--  5/11/2025 biddle - re-establish smoothing groups from incoming corner normals (maybe)
--  5/11/2025 biddle - quantize the normals and uvees to avoid sliver triangles
--  5/17/2025 biddle - recreate simple doors
--  5/17/2025 biddle - search for DDS textures
--  6/07/2025 biddle - handle doors with redundant edges
--  6/08/2025 biddle - handle doors with illegal verts, unify material loading
--  6/21/2025 biddle - recover shortest path on doors that have been damaged
--  8/03/2025 biddle - don't crash when 'see through' is on
--
-------------------------------------------------------------------------------------------


filein ((GetDir #scripts) +"\\TopoTools.ms")
filein ((GetDir #scripts) +"\\SearchTools.ms")
filein ((GetDir #scripts) +"\\MaterialTools.ms")

rollout SNOImport "SNO Import"
(
  local SNOD = 1146048083
  local V7_0 = 7

  struct strHeader  ( 
    magic, 
    majorVersion, 
    minorVersion, 
    numDoors, 
    numSpots, 
    numCorners, 
    numFaces, 
    numSurfaces, 
    minBBox, maxBBox, centroid, 
    isTiled,
    pad0, pad1, pad2,
    reserved0, reserved1, reserved1, reserved2,
    checkSum
  )    

  struct strSpot    ( xform, name )
  struct strDoor    ( index, xform, numVerts, verts )
  struct strCorner  ( pos=#(), nrm=#(), col=#(), txc=#(), opp=#() )

  local snoFileIn
  local dataHeader
  local dataSpots
  local dataDoors
  local dataCorners
  local dataSurfaces
  local dataLookup

  local dataNumLogicalNodes
  local dataLogicalNodes

  local myMesh
  local myMat
  local myDoor

  local nnkName
  
  group "Options"
  (
    spinner spn_Scale "Scale:" range:[0.0001,1000.0,1.0] type:#float scale:0.01
    checkbox chk_Texture "Texture Mesh" checked:true
    checkbox chk_SeeThru "See Thru Mesh" checked:false
    checkbox chk_Debug "Show Debug Info" checked:false
  )
  button btn_ImportNow "Import..." width:100

  fn DumpList lst cutoff:3 first:1 count:undefined = ( 
    if count == undefined then (
      count = lst.count
    ) 
    for v = 0 to count-1 do (
      if (v < cutoff or v >= count-cutoff) then (
        format "    %: %\n" (first+v) lst[first+v]
      )
      else if (v == (cutoff+1) and count > (cutoff*2)) then (
        format "        ...\n"
      )         
    )        
  )

  fn FlipUp v =
  (
    return ([v.x,-v.z,v.y] as point3)
  )

  fn ReadVector fin = (
    return point3 (ReadFloat fin) (ReadFloat fin) (ReadFloat fin) 
  )

  fn Quantize v tol = (
    s = if v < 0 then ceil( (v * tol) - 0.5) else floor( (v * tol) + 0.5)
    return s / tol
  )

  fn ReadUVee fin = (
    -- Sub-texel accuracy is suspect in a lot 
    -- of the uv mapping that is encountered
    u = Quantize (ReadFloat fin) 1024
    v = Quantize (ReadFloat fin) 1024
    return point3 u v 0 
  )

  fn ReadNormal fin = (
    -- Actual per corner normal values aren't re-used. 
    -- They matched to generate the smoothing groups.
    x = Quantize (ReadFloat fin) 256
    y = Quantize (ReadFloat fin) 256
    z = Quantize (ReadFloat fin) 256
    return point3 x y z 
  )

  fn ReadPosThenRot fin = (
    local px = ReadFloat fin
    local py = ReadFloat fin
    local pz = ReadFloat fin
    local r0 = ReadFloat fin
    local r1 = ReadFloat fin
    local r2 = ReadFloat fin
    local r3 = ReadFloat fin
    local r4 = ReadFloat fin
    local r5 = ReadFloat fin
    local r6 = ReadFloat fin
    local r7 = ReadFloat fin
    local r8 = ReadFloat fin

    return (matrix3 [r0,r1,r2] [r3,r4,r5] [r6,r7,r8] [px,py,pz])
  )

  fn ReadRotThenPos fin = (
    local r0 = ReadFloat fin
    local r1 = ReadFloat fin
    local r2 = ReadFloat fin
    local r3 = ReadFloat fin
    local r4 = ReadFloat fin
    local r5 = ReadFloat fin
    local r6 = ReadFloat fin
    local r7 = ReadFloat fin
    local r8 = ReadFloat fin
    local px = ReadFloat fin
    local py = ReadFloat fin
    local pz = ReadFloat fin

    return (matrix3 [r0,r1,r2] [r3,r4,r5] [r6,r7,r8] [px,py,pz])
  )


  fn ReadHeader fin = (
    local h = strHeader()

    h.magic         = ReadLong fin #unsigned

    h.majorVersion  = ReadLong fin #unsigned
    h.minorVersion  = ReadLong fin #unsigned

    h.numDoors      = ReadLong fin #unsigned
    h.numSpots      = ReadLong fin #unsigned

    h.numCorners    = ReadLong fin
    h.numFaces  		= ReadLong fin
    h.numSurfaces   = ReadLong fin

    h.minBBox       = ReadVector fin
    h.maxBBox       = ReadVector fin
    h.centroid      = ReadVector fin

    h.isTiled       = ReadByte fin #unsigned
    h.pad0          = ReadByte fin #unsigned
    h.pad1          = ReadByte fin #unsigned
    h.pad2          = ReadByte fin #unsigned

    h.reserved0     = ReadLong fin #unsigned
    h.reserved1     = ReadLong fin #unsigned 
    h.reserved2     = ReadLong fin #unsigned 

    h.checkSum    = ReadLong fin #unsigned

    if (h.magic != SNOD) do
    (
      messageBox "file is not a valid siege node"
      return undefined
    )

    return h
  )


  fn ReadDoor fin = (
    local i
    local d = ReadLong fin
    local m = ReadPosThenRot fin
    local n = ReadLong fin
    local h = #()
    for i = 1 to n do (
      append h (ReadLong fin)
    )

    return (strDoor index:d xform:m numVerts:n verts:h)
  )


  fn ReadSpot fin = (
    local m = ReadRotThenPos fin
    local n = ReadString fin

    return (strSpot xform:m name:n)
  )

  fn ReadColour fin = (
      return #(
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned)
      )
  ) 
  
  fn fetchIndex itms val addIfMissing:true = (
    i = findItem itms val
    if i == 0 then (
      if addIfMissing then (
        append itms val
        i = itms.count
      ) else (
        format "FATAL: % is missing in %\n" v itms
        throw ("FATAL: " + (v as string) + " is missing in " + (itms as string) + "\n")
      )
    )
    return i
  )


  fn ResetLookup = (
    return strCorner()
  )

  fn ReadCorner fin = (
    local p = fetchIndex dataLookup.pos (ReadVector fin)
    local n = fetchIndex dataLookup.nrm (ReadNormal fin)
    local c = fetchIndex dataLookup.col (ReadColour fin)
    local u = fetchIndex dataLookup.txc (ReadUVee fin)
    return (strCorner pos:p nrm:n col:c txc:u)
  )

  struct strSurface ( 
  	textureName,
	  startCorner,
	  spanCorner,
	  numCorners, 
	  faces 
  )

  fn ReadSurface fin = (
    local s = strSurface()
    local i

    s.textureName = ReadString fin
    s.startCorner = ReadLong fin
    s.spanCorner  = ReadLong fin
    s.numCorners  = ReadLong fin
    s.faces       = #()

    for i = 1 to (s.numCorners / 3) do
    (
      local a = ReadShort fin
      local b = ReadShort fin
      local c = ReadShort fin
      append s.faces ([a,b,c] as point3)
    )

    return s
  )

  struct strLeafInfo (
    id,
    minBox,
    maxBox,
    center,
    numTriangleIndices,
    triangleIndices,
    numLocalConnections,
    localConnections
  )

  fn ReadLeafInfo fin = (
    local n = strLeafInfo()

    n.id = ReadShort fin

    n.minBox = ReadVector fin
    n.maxBox = ReadVector fin
    n.center = ReadVector fin

    n.numTriangleIndices = ReadShort fin
    n.triangleIndices = #()
    for i = 1 to n.numTriangleIndices do
      append n.triangleIndices (ReadShort fin)

    n.numLocalConnections = ReadLong fin
    n.localConnections = #()   
    for j = 1 to n.numLocalConnections do
      append n.localConnections (ReadShort fin)

    return n
  )
  
  struct strNodeLeafConnect (
    nearLeafId,
    farLeafId
  )

  fn ReadNodeLeafConnect fin = (
    local n = strNodeLeafConnect()

    n.nearLeafId = ReadShort fin
    n.farLeafId = ReadShort fin

    return n
  )  

  struct strNodalConnectInfo (
    farId,
    numNodalLeafConnections,
    nodeLinks
  )

  fn ReadNodalConnectInfo fin = (
    local n = strNodalConnectInfo()

    n.farId = ReadByte fin #unsigned

    n.numNodalLeafConnections = ReadLong fin #unsigned
    n.nodeLinks = #()
    for i = 1 to n.numNodalLeafConnections do
      append n.nodeLinks (ReadNodeLeafConnect fin)

    return n
  )

  struct strTriNorm (
    verts,
    faceNorm,
    faceVerts,
    face
  )

  fn ReadTriNorm fin = (
    local n = strTriNorm face:undefined

    n.verts = #()
    append n.verts (ReadVector fin)
    append n.verts (ReadVector fin)
    append n.verts (ReadVector fin)

    n.faceNorm = ReadVector fin

    /*
    local A = fetchIndex dataLookup.pos n.verts[1] addIfMissing:false
    local B = fetchIndex dataLookup.pos n.verts[2] addIfMissing:false
    local C = fetchIndex dataLookup.pos n.verts[3] addIfMissing:false
    
    n.faceVerts = #{A,B,C}
    */

    -- Face will be set later from faceVerts, once the mesh is constructed

    return n
  )

  struct strBSPNode (
    minBox,
    maxBox,
    isLeaf,
    numTriangleIndices,
    triangleIndices,
    children,
    left,
    right
  )

  fn ReadBSPNode fin = (
    local n = strBSPNode()

    n.minBox = ReadVector fin
    n.maxBox = ReadVector fin

    n.isLeaf = ReadByte fin #unsigned

    n.numTriangleIndices = ReadShort fin #unsigned
	  n.triangleIndices = #()
    for i = 1 to n.numTriangleIndices do 
      append n.triangleIndices (ReadShort fin #unsigned)

    n.children = ReadByte fin #unsigned
    if n.children == 2 then (
      n.left = (ReadBSPNode fin)    
      n.right = (ReadBSPNode fin)    
    )

    return n
  )

  struct strLogicalNode ( 
    id, 
    minBox, 
    maxBox, 
    flags, 
    numLeafConnections,
    leafConnections,
    numNodeConnections,
    nodeConnections,
    numTriangles,
    triangles,
    bspNode
  )
  
  fn ReadLogicalNode fin = (
    local n = strLogicalNode()

    n.id = ReadByte fin #unsigned
    n.minBox = ReadVector fin
    n.maxBox = ReadVector fin
    n.flags = ReadLong fin #unsigned

    n.numLeafConnections = ReadLong fin #unsigned
    n.leafConnections = #()
    for i = 1 to n.numLeafConnections do
      append n.leafConnections (ReadLeafInfo fin)

    n.numNodeConnections = ReadLong fin #unsigned
    n.nodeConnections = #()
    for j = 1 to n.numNodeConnections do
      append n.nodeConnections (ReadNodalConnectInfo fin)
    
    n.numTriangles = ReadLong fin #unsigned
    n.triangles = #()
    for k = 1 to n.numTriangles do
      append n.triangles (ReadTriNorm fin)

    n.bspNode = (ReadBSPNode fin)

    return n
  )

  fn ReadSNO fin = (
    
    if (chk_Debug.checked) do format "debug: reading sno...\n"

    -- read header
    dataHeader = ReadHeader fin
    if (dataHeader == undefined) do
      return false

    -- read spots
    dataSpots = #()
    for i = 1 to dataHeader.numSpots do
      append dataSpots (ReadSpot fin)

    -- read doors
    dataDoors = #()
    for i = 1 to dataHeader.numDoors do
      append dataDoors (ReadDoor fin)

    -- read corners
    dataCorners = #()
    dataLookup = strCorner()
    for i = 1 to dataHeader.numCorners do (
      append dataCorners (ReadCorner fin)
    )

    -- read surfaces
    dataSurfaces = #()
    for i = 1 to dataHeader.numSurfaces do
      append dataSurfaces (ReadSurface fin)

	  if dataHeader.majorVersion >= 7 then (
      -- read BSP and Node info
      dataNumLogicalNodes = ReadLong fin
      dataLogicalNodes = #()
      for i = 1 to dataNumLogicalNodes do
        append dataLogicalNodes (ReadLogicalNode fin)
      if (chk_Debug.checked) do format "Read in % logical nodes\n" dataNumLogicalNodes
    )
    else (
      format "This version %.% SNO is too old to scan for BSP nodes\n" dataHeader.majorVersion dataHeader.minorVersion
      messageBox "This SNO is too old to scan for BSP nodes"
    )
    
      return true
  )  

  fn MakeDoors snomod = (
    local i, j

    if (chk_Debug.checked) do format "debug: creating doors...\n"

    snomod.tDoorList = #()    
    for d = 1 to dataHeader.numDoors do
    (
      local door = dataDoors[d]
      local doorVertSet = #{}
      for j = 1 to door.numVerts do (
        if (door.verts[j] < 0) then (
          if (chk_Debug.checked) do format "Ignoring illegal door vert %! % (of %)\n" j door.verts[j] dataCorners.count
          continue
        )
        local p = dataCorners[door.verts[j]+1].pos
        doorVertSet[p] = true
      ) 

      if (chk_Debug.checked) do format "Collecting edge for door vert set %\n" doorVertSet

      local doorEdges = snomod.collectDoorEdgesForVerts myMesh doorVertSet
 
      if (doorEdges.count == 0) then (
        if (doorVertSet.numberset == 2) then (
          dva = (doorVertset as array)
          format "Door verts are too sparse! We need the shortest boundary path between two verts: %\n" dva
          local helper = SearchTools()
          pathVerts = helper.FindShortestOpenPath myMesh dva[1] dva[2]
          doorEdges = snomod.collectDoorEdgesForVerts myMesh (pathVerts as BitArray)
        ) 
        else (
          format "Door verts are mangled %\n" doorVertSet
        )
      )

      if (chk_Debug.checked) do (      
        format "Door #% has these verts % (%)\n" d doorVertSet doorVertSet.numberset
        format "$.selectedverts = % ; gw.enlargeUpdateRect #whole ; gw.updateScreen()\n" doorVertSet      
        format "and these edges %\n" doorEdges
        format "$.selectededges = % ; gw.enlargeUpdateRect #whole ; gw.updateScreen()\n" doorEdges
      )  

      local newDoor = SiegeDoor verts:#() edges:#()

      if not (ExtractDoorFromEdgeList myMesh doorEdges newDoor AllowLoopyDoors:true) then (
        if (chk_Debug.checked) do format "Door #% could not be extracted correctly\n" d
      )

      append snomod.tDoorList newDoor

    )

    BuildDoorDirections myMesh snomod

    -- Check to make sure the door directions match what the SNO data says should be there
    for d = 1 to dataHeader.numDoors do (

      local checkZ = (FlipUp dataDoors[d].xform[3])
      local isFlipped = snomod.DoorDirectionList[d] == -(FlipUp dataDoors[d].xform[3])

      -- TODO acclimated doors with fixed directions -- these will likely be reported as 'loopy doors' too.

      if (chk_Debug.checked) do (   
        format " ==============================\n"   
          format " Door #% ddir    %\n" d snomod.DoorDirectionList[d]
          format "         dAcc    %\n" snomod.DoorDirectionListAcclimated[d]
          if isFlipped then (
            format "FLIPPED! checkZ  %\n" checkZ     
          ) 
          else (
            format "         checkZ  %\n" checkZ     
          )
          format "         xform   %\n" dataDoors[d].xform
          format " ------------------------------\n"
      )

      if (isFlipped) then (
        if (chk_Debug.checked) do format  "Flip door %\n" d
        FlipDoor myMesh snomod.tDoorList[d]
      )

    )  
    

  )

  fn MakeFaceFlags obj snomod = (
    
    fn DecodeFlags flg = (
      local HUMANOID_WALKABLE	= bit.shift 1 0
      local IS_WALL						= bit.shift 1 29
      local IS_FLOOR					= bit.shift 1 30
      local IS_WATER					= bit.shift 1 31
      fn bitset f b = return bit.and f b == b
      out = #()
      if (bitset flg HUMANOID_WALKABLE) do append out #HUMANOID_WALKABLE
      if (bitset flg IS_WALL) do append out #IS_WALL
      if (bitset flg IS_FLOOR) do append out #IS_FLOOR
      if (bitset flg IS_WATER) do append out #IS_WATER
      return out
    )

    fn faceFromTriNorm obj lookup tn = (
        fn orSets a b c = (
          local result = #{}
          for i in a do result[i] = (b[i] and c[i])
          return result
        )
        -- Now we can figure out what face this trinorm was constructed from
        local pts = for v = 1 to 3 collect ((FlipUp tn.verts[v]) * spn_Scale.value * 1000)
        local idx = for p in pts collect (fetchIndex lookup p addIfMissing:false)
        local facesA = meshop.getFacesUsingVert obj idx[1]          
        local facesB = meshop.getFacesUsingVert obj idx[2]          
        local facesC = meshop.getFacesUsingVert obj idx[3]          
        return (orSets facesA facesB facesC)
    )

    snoMod.tFloorBits = #{}
    snoMod.tWaterBits = #{}
    
    for ln = 1 to dataLogicalNodes.count do (
      lno = dataLogicalNodes[ln]
      flags = (DecodeFlags lno.flags)
      if (findItem flags #IS_FLOOR) > 0 then (
        for tn in lno.triangles do (
          snoMod.tFloorBits += faceFromTriNorm obj dataLookup.pos tn
        )
      )
      if (findItem flags #IS_WATER) > 0 then (
        for tn in lno.triangles do (
          snoMod.tWaterBits += faceFromTriNorm obj dataLookup.pos tn
        )
      )      
    )

    if (chk_Debug.checked) do (
      format "floor faces %\n" snoMod.tFloorBits 
      format "water faces %\n" snoMod.tWaterBits 
    )

  )

  fn MakeMesh = (
    local i, j

    if (chk_Debug.checked) do format "debug: creating mesh...\n"

    for i = 1 to dataLookup.pos.count do (
        dataLookup.pos[i] = ((FlipUp dataLookup.pos[i]) * spn_Scale.value * 1000)
    )

    -- create array of faces
    local VertFaces = #()
    local TexcFaces = #()  
    local NrmlFaces = #()  
    local MatiFaces = #() 
    local f = 1
	  local s = 1

    for surface in dataSurfaces do (
      for j = 1 to (surface.numCorners / 3) do (
        local cA = dataCorners[surface.faces[j].x + surface.startCorner + 1]
        local cB = dataCorners[surface.faces[j].y + surface.startCorner + 1]
        local cC = dataCorners[surface.faces[j].z + surface.startCorner + 1]	
        VertFaces[f] = [cA.pos, cB.pos, cC.pos]
        TexcFaces[f] = [cA.txc, cB.txc, cC.txc]
        NrmlFaces[f] = [cA.nrm, cB.nrm, cC.nrm]
        MatiFaces[f] = s        
        f += 1
      )
	    s += 1
    )

    if (chk_Debug.checked) do format "We are expecting % faces\n" VertFaces.count

    myMesh = Mesh \
             name:        nnkName \
             vertices:    dataLookup.pos \
             faces:       VertFaces \             
             materialIDs: MatiFaces    

    -- Set the texture verts and faces

    if (dataHeader.majorVersion >= 8) then (
      -- For DS2, texture format was changed from RAW to DDS
      for i = 1 to dataLookup.txc.count do dataLookup.txc[i].y = (1.0 - dataLookup.txc[i].y)
    )
  
    setNumTVerts myMesh dataLookup.txc.count 
    for i = 1 to dataLookup.txc.count do setTVert myMesh i dataLookup.txc[i]
    buildTVFaces myMesh
    for i = 1 to TexcFaces.count do setTVFace myMesh i TexcFaces[i]

    update myMesh    

    local tools = (TopoTools      \
      triObj:myMesh               \
      faceCornerNormals:NrmlFaces \
      faceCornerVerts:VertFaces
    )

    tools.RebuildSmoothing()

    update myMesh

    -- and miscellaneous stuff
    myMesh.wirecolor = (color 0 0 153)
    if (chk_SeeThru.checked) do
      myMesh.xray = true

    return myMesh
  )

  fn ImportSNO fin = (

    if (chk_Debug.checked) do format "debug: importing sno...\n"

    if not (ReadSNO fin) do
      return false

    MakeMesh()
    
    if (chk_Texture.checked and dataHeader.numSurfaces > 0) do (
      --if (chk_Debug.checked) do format "Will look for bitmaps in your output path: %\n" (dsGetOutputPath())
      matNames = for ds in dataSurfaces collect ds.textureName
      local mtools = MaterialTools()
      myMesh.material = mtools.MakeMaterials matNames debug:chk_Debug.checked
      if (myMesh.material != undefined) then (        
        setMeditMaterial 1 myMesh.material
      )
    )

    -- add siegemax specific things
    select myMesh

    max modify mode 
    addmodifier myMesh (SNOModDef())    
    local newmod = (myMesh.'Siege Max SNO')    

    MakeDoors newmod

    newmod.SaveDoorVertMapping newmod

    MakeFaceFlags myMesh newmod
    
    return true
  )


  fn GetOpenFileStream = (
    local fname = GetOpenFileName types:"Siege Node Terrain (*.sno)|*.sno|All Files (*.*)|*.*|"
    if (fname == undefined) do
      return false

    -- figure out the node name from the filename
    local tokens = filterString fname "/\\"
    nnkName = (filterString tokens[tokens.count] ".")[1]

    snoFileIn = fopen fname "rb"
    if (snoFileIn == undefined) do
    (
      messageBox "Could not open file for binary reading!"
      return false
    )

    return true
  )


  on btn_ImportNow pressed do (
    local oldCoordsys

    oldCoordsys = set coordsys world

    if (GetOpenFileStream()) do
    (
      if (ImportSNO snoFileIn) then
        format "SNO import successful.\n"
      else
        messageBox "SNO import failed."
      fclose snoFileIn
    )

    set coordsys oldCoordsys

    -- release all the storage we allocated
    snoFileIn = undefined
    dataHeader = undefined
    dataSpots = undefined
    dataDoors = undefined
    dataCorners = undefined
    dataSurfaces = undefined
    dataLookup = undefined
    dataNumLogicalNodes = undefined
    dataLogicalNodes = undefined
    myMesh = undefined
    myMat = undefined
    myDoor = undefined
    nnkName  = undefined  

  )

)


fn lanceImportSNO =
(
  addRollout SNOImport (newRolloutFloater "SNO Import" 200 205)
)

/*
listener one-liner to reload the WIP

clearlistener(); filein ((GetDir #scripts) +"\\plugins\\sno_mod.ms"); filein ((GetDir #scripts) +"\\SNOTools.ms"); filein ((GetDir #scripts) +"\\SNOImport.ms"); lanceImportSNO(); setListenerSel #(0,0)

Problem files:
t_0Agallan01_main-path-01
t_0Agallan01_main-path-02
*/
