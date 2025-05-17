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
--
-------------------------------------------------------------------------------------------


filein ((GetDir #scripts) +"\\TopoTools.ms")

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

  fn ReadUVee fin =
  (
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

  fn ReadPosThenRot fin =
  (
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

  fn ReadRotThenPos fin =
  (
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


  fn ReadHeader fin =
  (
    local h = strHeader()

    h.magic         = ReadLong fin #unsigned

    h.majorVersion  = ReadLong fin #unsigned
    h.minorVersion  = ReadLong fin #unsigned

    h.numDoors      = ReadLong fin #unsigned
    h.numSpots      = ReadLong fin #unsigned

    h.numCorners    = ReadLong fin
    h.numFaces		= ReadLong fin
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


  fn ReadDoor fin =
  (
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


  fn ReadSpot fin =
  (
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
  
  fn fetchIndex itms val = (
    i = findItem itms val
    if i == 0 then (
      append itms val
      i = itms.count
    )
    return i
  )


  fn ResetLookup = (
    return strCorner()
  )

  fn ReadCorner fin =
  (
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
    faceNorm
  )

  fn ReadTriNorm fin = (
    local n = strTriNorm()

    n.verts = #()
    append n.verts (ReadVector fin)
    append n.verts (ReadVector fin)
    append n.verts (ReadVector fin)

    n.faceNorm = ReadVector fin

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
    
    if (chk_Debug.checked) do
      format "debug: reading sno...\n"

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
      format "Read in % logical nodes\n" dataNumLogicalNodes
    )
    else (
      format "This version %.% SNO is too old to scan for BSP nodes\n" dataHeader.majorVersion dataHeader.minorVersion
    )
    
      return true
  )  

  fn selectDoorEdgesForVerts obj doorVertSet =
  (
      local edgeList = #()
      local edgeMap = #() -- prevent duplicates

      format "Look for edges in % (%)\n" doorVertSet doorVertSet.numberset
      -- Build a list of all edges from faces
      for f = 1 to getNumFaces obj do
      (
        local ff = getFace obj f
        local faceEdges = #((if ff.x < ff.y then #{ff.x, ff.y} else #{ff.y, ff.x}),
                            (if ff.y < ff.z then #{ff.y, ff.z} else #{ff.z, ff.y}),
                            (if ff.z < ff.x then #{ff.z, ff.x} else #{ff.x, ff.z}))
        for ee in 1 to 3 do
        (
          if ((faceEdges[ee] * doorVertSet).numberset == 2) do (         
            local key = (faceEdges[ee] as string) as name
            if (findItem edgeMap key) == 0 then (
              format "We have an edge on face % v % (%)\n" f ee faceEdges[ee]            
              local edgeIndex = 3 * (f-1) + ee
              append edgeList edgeIndex
              append edgeMap key
            ) 
            else (
              format "We have a DUPE!! %\n" faceEdges[ee]            
            )
          )
        )
      )
  
      return edgeList
  )   

  fn MakeDoors snomod = (
    local i, j

    if (chk_Debug.checked) do (
      format "debug: creating doors...\n"
    )

    snomod.tDoorList = #()    
    for d = 1 to dataHeader.numDoors do
    (
      local door = dataDoors[d]
      local doorVertSet = #{}
      for j = 1 to door.numVerts do (
        p = dataCorners[door.verts[j]+1].pos
        doorVertSet[p] = true
      ) 
      local doorEdges = selectDoorEdgesForVerts myMesh doorVertSet

      if (chk_Debug.checked) do (      
        format "Door #% has these verts % (%)\n" d doorVertSet doorVertSet.numberset
        format "$.selectedverts = % ; gw.enlargeUpdateRect #whole ; gw.updateScreen()\n" doorVertSet      
        format "and these edges %\n" doorEdges
        format "$.selectededges = % ; gw.enlargeUpdateRect #whole ; gw.updateScreen()\n" doorEdges
      )  

      local newDoor = SiegeDoor verts:#() edges:#()

      if not (ExtractDoorFromEdgeList myMesh doorEdges newDoor AllowLoopyDoors:true) then (
        format "Door #% could not be extracted correctly\n" d
      ) else (
        format "Door #% was extracted: %\n" d newDoor
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
        format  "Flip door %\n" d
        FlipDoor myMesh snomod.tDoorList[d]
      )

    )  
    

  )

  fn MakeMesh = (
    local i, j

    if (chk_Debug.checked) do
      format "debug: creating mesh...\n"

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

    format "We are expecting % faces\n" VertFaces.count

    myMesh = Mesh \
             name:        nnkName \
             vertices:    dataLookup.pos \
             faces:       VertFaces \             
             materialIDs: MatiFaces    
			 
    -- Set the texture verts and faces
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

    --assignSmoothingGroupsFromVertexNormals myMesh NrmlFaces VertFaces
    --tools.DumpStuff obj
    tools.RebuildSmoothing()

    update myMesh

    -- and miscellaneous stuff
    myMesh.wirecolor = (color 0 0 153)
    if (chk_SeeThru.checked) do
      myMesh[sm].xray = true

    return myMesh
  )
  
  fn MakeTexture n = (
    local t = StandardMaterial \
              name:           n \
              shaderByName:   "blinn" \
              adTextureLock:  true \
              adLock:         true \
              showInViewport: true
    t.diffuseMapEnable = true
    t.opacityMapEnable = true
	
    -- look for the bitmap in the output path.\	
    rawpath = dsGetOutputPath() + "\\" + (dsBuildContentLocation n) + ".raw"
    
    if not (doesFileExist rawpath) then (
      format "Missing: %\n" rawpath 
      rawpath = n + ".raw"
      -- TODO:
      --   search other potential paths, or PSD files		
    ) else (
      format "Found: %\n" rawpath 
    )
    
    t.diffuseMap = BitmapTexture name:(n + "_diffuse") \
                   filename:(rawpath)
    t.opacityMap = BitmapTexture name:(n + "_opacity") \
                   filename:(rawpath) \
                   monoOutput: 1 \
                   alphaSource: 0

    return t
  )

  fn MakeMaterial = (
	local i

    if (chk_Debug.checked) do
      format "debug: creating material...\n"

    -- create standard texture, or multi-material if needed
    if (dataHeader.numSurfaces > 1) then
    (
      myMat = MultiMaterial numSubs:dataHeader.numSurfaces
      for i = 1 to dataHeader.numSurfaces do
      (
        myMat.names[i] = dataSurfaces[i].textureName
        myMat.materialList[i] = (MakeTexture dataSurfaces[i].textureName)
      )
    )
    else
    (
      myMat = (MakeTexture dataSurfaces[1].textureName)
    )

    -- add material to first slot in material editor
    setMeditMaterial 1 myMat

    -- assign material to mesh
    myMesh.material = myMat
  )


  fn ImportSNO fin = (

    if (chk_Debug.checked) do
      format "debug: importing sno...\n"

    if not (ReadSNO fin) do
      return false

    MakeMesh()
    
    if (chk_Texture.checked and dataHeader.numSurfaces > 0) do (
      format "Will look for bitmaps in your output path: %\n" (dsGetOutputPath())
        MakeMaterial()
    )

    -- add siegemax specific things
    select myMesh

    max modify mode 
    addmodifier myMesh (SNOModDef())    
    local newmod = (myMesh.'Siege Max SNO')    

    MakeDoors newmod

    -- restoreFloors()

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
  )

)


fn lanceImportSNO =
(
  addRollout SNOImport (newRolloutFloater "SNO Import" 200 205)
)

/*
listener one-liners

clearlistener(); filein ((GetDir #scripts) +"\\SNOTools.ms"); filein ((GetDir #scripts) +"\\SNOImport.door.ms"); lanceImportSNO(); setListenerSel #(0,0)

Known problems:
Non-contiguous edges: $t_gi_gad_wal_nook-04-a


*/
