-- Dungeon Siege ASP Import (Siege Max)
-- Lance ><>
-- 8/23/2002
-- updates Jan 2004 by Ghastley (DS LoA etc)

-------------------------------------------------------------------------------------------
-- Updates & Hacks
--
--  5/23/2025 biddle - Added support for 5.1 version (DS2BW)
--  5/24/2025 biddle - Optimize faces and add smoothing groups
--  5/25/2025 biddle - Sort out D3D indexed sub-ranges, optimization, skinning
--  6/08/2025 biddle - Unify material loading
--
-------------------------------------------------------------------------------------------

filein ((GetDir #scripts) +"\\TopoTools.ms")
filein ((GetDir #scripts) +"\\MaterialTools.ms")

rollout ASPImport "ASP Import"
(

  struct strChunkHeader  ( mark = 0, majorVersion = 0, minorVersion = 0, extraVersion = 0 )
  struct strBoneInfo ( name, parent, flags )
  struct strBSMM ( textureIndex, numberOfFaces )
  struct strBVMP ( count, cornersInfluenced=#() )
  struct strBTRI ( cornerStart, cornerSpan, cornerIndex )
  struct strBVWL ( boneIds=#(), weights=#() )
  struct strSTCH ( token, vertexCount, vertexIndex )
  struct strRPOS ( invRot, invPos, rot, pos )

  struct strBCRN  ( pos=#(), nrm=#(), col=#(), spc= #(), txc=#(), opp=#() )
  struct strWCRN  ( pos=#(), weight=#(), bone=#(), nrm=#(), col=#(), txc=#(), opp=#() )

  struct strSubMesh ( id = -1, 
                      maxSubTextures = 0,
                      numVertices = 0,
                      numCorners = 0,
                      numFaces = 0,
                      numStitches = 0,
                      dataBSMM = #(),
                      dataBVTX = #(),
                      dataBCRN = #(),
                      dataWCRN = #(),
                      dataBVMP = #(),
                      dataBTRI = #(),
                      dataBVWL = #(),
                      dataSTCH = #())
  
  struct strBoundingBox ( Name, Position, Orientation, HalfDiag )

  local aspFileIn
  local nnkName
  local numBones
  local numTextures
  local numVerticesTotal
  local numSubMeshes
  local renderFlags
  local curSM

  local textureNames
  local boneInfo
  local subMesh

  local dataRPOS

  local myBone
  local mySkin

  local dbgMeshes

  -- Keep lookup tables of all corner attributes
  local dataBLookup
  local dataWLookup

  group "Options" (
    spinner spn_Scale "Scale:" range:[0.0001,1000.0,1.0] type:#float scale:0.01
    checkbox chk_Texture "Texture Mesh" checked:true
    checkbox chk_SetSmoothingGroups "Set Smoothing Groups" checked:true   
    checkbox chk_Bone "Bone Mesh" checked:true
    checkbox chk_Skin "Skin Mesh" checked:true
    checkbox chk_FlipUV "Flip UV" checked:false
    checkbox chk_BoneBall "Bones As Balls" checked:false
    checkbox chk_SeeThru "See Thru Mesh" checked:false
    checkbox chk_Debug "Show Debug Info" checked:false
    checkbox chk_DebugVertList "Debug Vert List" checked:false
    width:200
  )
  button btn_ImportNow "Import..." width:100

  fn DumpData subMesh smi = (
    
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


    format "===========================================================\n" subMesh.id
    format "SubMesh[%]:\n" smi

    format "submesh ID      %\n" subMesh.id

    format " maxSubTextures %\n" subMesh.maxSubTextures
    format " numVertices    %\n" subMesh.numVertices
    format " numCorners     %\n" subMesh.numCorners
    format " numFaces       %\n" subMesh.numFaces
    format " numStitches    %\n" subMesh.numStitches

    format " dataBSMM:\n"
    for m in subMesh.dataBSMM do (
      format "  texture index [%] numberOfFaces %\n" m.textureIndex m.numberOfFaces

    )

    format " dataBVTX:\n"
    DumpList subMesh.dataBVTX

    format " dataBCRN       %\n" subMesh.dataBCRN

    format " dataWCRN:\n"
    DumpList subMesh.dataWCRN 

    format " dataBVMP:\n"
    DumpList subMesh.dataBVMP

    format " dataBTRI:\n" 
    format "  % submeshes\n" subMesh.dataBTRI.cornerStart.count
    local firstFace = 1
    for i = 1 to subMesh.dataBTRI.cornerStart.count do (
      format "  trilist[%]:\n"  i
      format "   cornerStart: % \n" subMesh.dataBTRI.cornerStart[i]
      format "   cornerSpan:  % \n" subMesh.dataBTRI.cornerSpan[i]
      format "   tris:\n"
      DumpList subMesh.dataBTRI.cornerIndex first:firstFace count:subMesh.dataBSMM[i].numberOfFaces
      firstFace += subMesh.dataBSMM[i].numberOfFaces
    )

    format " dataBVWL:\n"
    DumpList subMesh.dataBVWL   
    
    format " dataSTCH       %\n" subMesh.dataSTCH

    format " dataBLookup table sizes\n"
    format "    pos %\n" dataBLookup.pos.count
    format "    txc %\n" dataBLookup.txc.count
    format "    nrm %\n" dataBLookup.nrm.count

    format " dataWLookup table sizes\n"
    format "    pos %\n" dataWLookup.pos.count
    format "    txc %\n" dataWLookup.txc.count
    format "    nrm %\n" dataWLookup.nrm.count

    format "===========================================================\n" subMesh.id

  )

  fn FlipUp v = (
    return ([v.x,-v.z,v.y] as point3)
  )


  fn FlipUpQuat q = (
    return (quat q.x -q.z q.y q.w)
  )

  fn ReadQuat fin = (
    local x = ReadFloat fin
    local y = ReadFloat fin
    local z = ReadFloat fin
    local w = ReadFloat fin
    return (quat x y z w)
  )

  fn ReadVector fin = (
    local x = ReadFloat fin
    local y = ReadFloat fin
    local z = ReadFloat fin
    return ([x,y,z] as point3)
  )

  fn ReadCoord fin = (
    local u = ReadFloat fin
    local v = ReadFloat fin
    return ([u,v,0] as point3)
  )

  fn ReadFourCC fin = (
    local a = bit.intAsChar (ReadByte fin #unsigned)
    local b = bit.intAsChar (ReadByte fin #unsigned)
    local c = bit.intAsChar (ReadByte fin #unsigned)
    local d = bit.intAsChar (ReadByte fin #unsigned)
    return a+b+c+d
  )  

  fn ReadFourBB fin = (
    local a = ReadByte fin #unsigned
    local b = ReadByte fin #unsigned
    local c = ReadByte fin #unsigned
    local d = ReadByte fin #unsigned
    return #(a,b,c,d)
  )

   fn ReadFourBB2 fin = (
    local a = ReadByte fin +1
    local b = ReadByte fin +1
    local c = ReadByte fin +1
    local d = ReadByte fin +1
    return #(a,b,c,d)
  )

  fn ReadFourFF fin = (
    local a = ReadFloat fin
    local b = ReadFloat fin
    local c = ReadFloat fin
    local d = ReadFloat fin
    return #(a,b,c,d)
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

  fn ReadColour fin = (
      return #(
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned),
        (ReadByte fin #unsigned)
      )
  )   
  
  fn ReadChunkHeader fin = (
    return (strChunkHeader                      \
        mark: (ReadFourCC fin)                  \
        majorVersion: (ReadByte fin #unsigned)  \
        minorVersion: (ReadByte fin #unsigned)  \
        extraVersion: (ReadShort fin #unsigned) \
      )
  )
  
  fn fetchIndex itms val addIfMissing:true = (
    i = findItem itms val
    if i > 0 then (
      return i
    )
    else if addIfMissing then (
      append itms val
      return itms.count
    )
    else (
      format "ERROR! Can't find item % in table %" val itms
    )
    return 0
  )

  fn ReadBMSH fin = (
    if (chk_Debug.checked) do format "debug: reading BMSH section..."

    local sizeTextField = ReadLong fin

    numBones = ReadLong fin
    numTextures = ReadLong fin
    maxNumVertices = ReadLong fin
    numSubMeshes = ReadLong fin
    renderFlags = ReadLong fin

    -- read text field
    local token = #()
    while (sizeTextField > 0) do (
      append token (ReadString fin)
      local size = token[token.count].count + 1
      local padding = mod (4 - (mod size 4)) 4
      for i = 1 to padding do
        ReadByte fin -- throw away null padding
      sizeTextField -= size + padding
    )

    -- split tokens in textures names and bone names
    textureNames = #()
    if (numTextures > 0) do
      for i = 1 to numTextures do
        textureNames[i] = token[i]
    boneInfo = #()
    if (numBones > 0) do
      for i = 1 to numBones do
        boneInfo[i] = strBoneInfo name:token[i + numTextures]

    subMesh = #()
    if (chk_Debug.checked) do format "ok!\n"    

    return true
  )


  fn ReadBONH fin = (
    if (chk_Debug.checked) do format "debug: reading BONH section..."

    for i = 1 to numBones do (
      local j = ReadLong fin
      local p = ReadLong fin
      local f = ReadLong fin
      boneInfo[j + 1].parent = p + 1
      boneInfo[j + 1].flags = f
    )

    if (chk_Debug.checked) do format "ok!\n"       
  )

  fn ReadBSMM fin = (
    if (chk_Debug.checked) do format "debug: reading BSMM section..."    
    local materials = #()
    local numOfMaterials = (ReadLong fin #unsigned)
    for i = 1 to numOfMaterials do (
      append materials (strBSMM  textureIndex: (ReadLong fin) numberOfFaces: (ReadLong fin) )
    )
    subMesh[curSM].dataBSMM = materials
    if (chk_Debug.checked) do format "ok!\n"         
  )

  fn ReadBSUB fin = (
    
    curSM  += 1

    if (chk_Debug.checked) do  format "debug: reading BSUB section for % ..." curSM

    subMesh[curSM] = strSubMesh()
    subMesh[curSM].id = (ReadLong fin #unsigned)
    subMesh[curSM].maxSubTextures = (ReadLong fin #unsigned)
    subMesh[curSM].numVertices = (ReadLong fin #unsigned)
    subMesh[curSM].numCorners = (ReadLong fin #unsigned)
    subMesh[curSM].numFaces = (ReadLong fin #unsigned)

    if (chk_Debug.checked) do format "ok!\n"     
  )

  fn ReadBVTX fin = (
    if (chk_Debug.checked) do format "debug: reading BVTX section..."

    if (subMesh[curSM].numVertices != ReadLong fin) do (
      if (chk_Debug.checked) do messageBox "error: BVTX numVertices don't match"
      format "\nERROR: BVTX numVertices don't match\n"
      return false
    )

    subMesh[curSM].dataBVTX = #()
    for i = 1 to subMesh[curSM].numVertices do (
      append subMesh[curSM].dataBVTX (fetchIndex dataWLookup.pos (ReadVector fin))
    )

    if (chk_Debug.checked) do format "ok!\n"

    return true              
  )
  
  fn ReadBCorner fin lookup =
  (
    local p, w, b, n, c, u
    p = fetchIndex lookup.pos (ReadLong fin #unsigned)
    n = fetchIndex lookup.nrm (ReadNormal fin)
    c = fetchIndex lookup.col (ReadColour fin)
    s = fetchIndex lookup.spc (ReadColour fin) -- specular colour
    u = fetchIndex lookup.txc (ReadUVee fin)
    return (strBCRN pos:p nrm:n col:c spc:s txc:u)
  )

  fn ReadBCRN fin = (
    if (chk_Debug.checked) do  format "debug: reading BCRN section..."

    if (subMesh[curSM].numCorners != ReadLong fin) do
      if (chk_Debug.checked) do (
        messageBox "error: BCRN numCorners don't match"
      )

    subMesh[curSM].dataBCRN = #()
    for i = 1 to subMesh[curSM].numCorners do (
      append subMesh[curSM].dataBCRN (ReadBCorner fin dataBLookup)
    )
    
    if (chk_Debug.checked) do format "ok!\n"           
  )

  fn ReadWCorner fin FixOffByOne lookup = (
    local p, w, b, n, c, u
    p = fetchIndex lookup.pos (ReadVector fin)
    w = (ReadFourFF fin)
    b = ((if FixOffByOne then ReadFourBB else ReadFourBB2) fin)   
    n = fetchIndex lookup.nrm (ReadNormal fin)
    c = fetchIndex lookup.col (ReadColour fin)
    u = fetchIndex lookup.txc (ReadUVee fin)
    return (strWCRN pos:p weight:w bone:b nrm:n col:c txc:u)
  )

  fn ReadWCRN fin FixOffByOne = (
    if (chk_Debug.checked) do format "debug: reading WCRN section..."
 
    if (subMesh[curSM].numCorners != ReadLong fin) do (
      messageBox "error: WCRN numCorners don't match"
    )

    subMesh[curSM].dataWCRN = #()
    for i = 1 to subMesh[curSM].numCorners do (
      append subMesh[curSM].dataWCRN (ReadWCorner fin FixOffByOne dataWLookup)
    )

    if (chk_Debug.checked) do format "ok!\n" 
  )


  fn ReadBVMP fin = (
    if (chk_Debug.checked) do format "debug: reading BVMP section..."

    subMesh[curSM].dataBVMP = #()
    local v, c
    local maxCorn = -1
    for v = 1 to subMesh[curSM].numVertices do
    (
      newbie = strBVMP count:(ReadLong fin)
      for c = 1 to newbie.count do (
        ci = (ReadLong fin)
        if maxCorn < ci then maxCorn = ci
        newbie.cornersInfluenced[c] = ci
      )
      subMesh[curSM].dataBVMP[v] = newbie
    )
    if (maxCorn+1 != subMesh[curSM].numCorners) then (
      messageBox "Error The max corner index we encountered was % (should be %)\n" maxCorn subMesh[curSM].numCorners
    )
    if (chk_Debug.checked) do format "ok!\n" 
  )

  fn ReadBTRI fin SupportSubMeshRanges MayHaveSpanLenBug = (
    if (chk_Debug.checked) do format "debug: reading BTRI section..."

    if (subMesh[curSM].numFaces != ReadLong fin) do (
      messageBox "error: BTRI numFaces don't match"
    )

    subMesh[curSM].dataBTRI = strBTRI()

    subMesh[curSM].dataBTRI.cornerStart = #()
    subMesh[curSM].dataBTRI.cornerSpan = #()

    -- Read indexed vertex spans if available
    for i = 1 to subMesh[curSM].dataBSMM.count do (
      if SupportSubMeshRanges then (
        subMesh[curSM].dataBTRI.cornerStart[i] = ReadLong fin
        if (MayHaveSpanLenBug and (subMesh[curSM].dataBSMM.count == 1) and (subMesh[curSM].dataBTRI.cornerStart[i] == 0)) then (
          -- A bug in the 2.2 exporter may have omitted the span length? --biddle
          subMesh[curSM].dataBTRI.cornerSpan[i] = 0
        )
        else (
          subMesh[curSM].dataBTRI.cornerSpan[i] = ReadLong fin
        )
      )
      else (
        subMesh[curSM].dataBTRI.cornerStart[i] = 0
        subMesh[curSM].dataBTRI.cornerSpan[i] = subMesh[curSM].numCorners
      )
    )

    -- read data
    subMesh[curSM].dataBTRI.cornerIndex = #()
    for i = 1 to subMesh[curSM].numFaces do (
      local a = (ReadLong fin)
      local b = (ReadLong fin)
      local c = (ReadLong fin)
      subMesh[curSM].dataBTRI.cornerIndex[i] = [a,b,c] as point3
    )

    if (chk_Debug.checked) do format "ok!\n"
  )

  fn ReadBVWL fin = (
    if (chk_Debug.checked) do format "debug: reading BVWL section..."

    local v, b, i, j, count    

    for v = 1 to subMesh[curSM].numVertices do (
      subMesh[curSM].dataBVWL[v] = strBVWL() 
    )

    for b = 1 to numBones do (
      count = ReadLong fin
      if (count < 0) and (b == numBones) then (
        -- We could have a number of boneIds, only with a rigid 
        -- weight, but in most (all?) cases there was only 1 bone.
        -- There may be some oddballs in the  front end gui animation.
        -- TODO: The only way to tell is scan them in and see if 
        -- we reach the next section. 
        for v = 1 to subMesh[curSM].numVertices do (
          subMesh[curSM].dataBVWL[v].boneIds = #(1)
          subMesh[curSM].dataBVWL[v].weights = #(1)
        )
      )
      else (
        for j = 1 to count do (
          v = (ReadLong fin) + 1
          append subMesh[curSM].dataBVWL[v].boneIds b
          append subMesh[curSM].dataBVWL[v].weights (ReadFloat fin)
        )
      )
    )

    if (chk_Debug.checked) do format "ok!\n"
  )


  fn ReadSTCH fin = (
    if (chk_Debug.checked) do format "debug: reading STCH section..."

    subMesh[curSM].numStitches = ReadLong fin

    subMesh[curSM].dataSTCH = #()
    local i, j
    for i = 1 to subMesh[curSM].numStitches do (
      subMesh[curSM].dataSTCH[i] = strSTCH()
      subMesh[curSM].dataSTCH[i].token = ReadFourCC fin
      subMesh[curSM].dataSTCH[i].vertexCount = ReadLong fin
      subMesh[curSM].dataSTCH[i].vertexIndex = #()
      for j = 1 to subMesh[curSM].dataSTCH[i].vertexCount do (
        subMesh[curSM].dataSTCH[i].vertexIndex[j] = (ReadLong fin)
      )
    )
    if (chk_Debug.checked) do format "ok!\n"
  )


  fn ReadRPOS fin = (
    if (chk_Debug.checked) do format "debug: reading RPOS section..."

    if (numBones != ReadLong fin) do (
      messageBox "error: RPOS numBones don't match"
    )

    dataRPOS = #()
    local i
    for i = 1 to numBones do (
        local ir = ReadQuat fin
        local ip = ReadVector fin
        local r = ReadQuat fin
        local p = ReadVector fin
        dataRPOS[i] = strRPOS invRot:ir invPos:ip rot:r pos:p
    )

    if (chk_Debug.checked) do format "ok!\n"
  )

  fn ReadBBOX fin = (
    if (chk_Debug.checked) do  format "debug: reading BBOX section..."

    local numBoxes = ReadLong fin 
    local boxes = #()
    for i = 1 to numBoxes do (
      local n = ReadFourCC fin
      local p = ReadVector fin
      local r = ReadQuat fin
      local hd = ReadVector fin
      append boxes (strBoundingBox Name:n Position:p Orientation:r HalfDiag:hd)
    )

    if (chk_Debug.checked) do format "ok!\n"

    return boxes
  )

  fn ReadBEND fin = (
    if (chk_Debug.checked) do
      format "debug: reading BEND section...\n"

    -- INFO section
    if (chk_Debug.checked) do
      format "debug: reading INFO section...\n"

    local numInfoEntries = ReadLong fin
    for i = 1 to numInfoEntries do
    (
      local SiegeMaxMark =  (ReadFourCC fin) + (ReadFourCC fin)
      if (chk_Debug.checked) do
        format "debug: info [%]\n" SiegeMaxMark
    )
  )


  fn ReadASP fin = (
    curSM = 0
    legal = ReadBMSH fin
    while legal do
    (
      local header = ReadChunkHeader fin
           if (header.mark == "BONH") then (ReadBONH fin)
      else if (header.mark == "BSUB") then (ReadBSUB fin)
      else if (header.mark == "BSMM") then (ReadBSMM fin)
      else if (header.mark == "BVTX") then (ReadBVTX fin)
      else if (header.mark == "BCRN") then (ReadBCRN fin)
      else if (header.mark == "BVMP") then (ReadBVMP fin)
      else if (header.mark == "BVWL") then (ReadBVWL fin)
      else if (header.mark == "STCH") then (ReadSTCH fin)
      else if (header.mark == "RPOS") then (ReadRPOS fin)
      else if (header.mark == "BBOX") then (ReadBBOX fin)
      else if (header.mark == "WCRN") then (
        ReadWCRN fin (header.majorVersion < 5)
      ) 
      else if (header.mark == "BTRI") then (
        useRanges = ((header.majorVersion > 2) or (header.majorVersion == 2 and header.minorVersion >= 2))
        checkForBug = ((header.majorVersion < 2) or (header.majorVersion == 2 and header.minorVersion == 2))
        ReadBTRI fin useRanges checkForBug
      )    
      else if (header.mark == "BEND") then (ReadBEND fin; exit)
      else (
        format "Unexpected header mark '%'\n" header
        messagebox ("Unexpected header mark: " + (header as string))
        legal = false
      ) 
    )
    return legal
  )


  fn MakeMesh flipVcoord:false =
  (
    local sm, i, j, p

    if (chk_Debug.checked) do format "debug: creating mesh..."

    -- gather verts    
    local meshVerts = for p in dataWLookup.pos collect ((FlipUp p) * 1000 * spn_Scale.value)

    -- gather faces
    local VertFaces = #()
    local TexcFaces = #()  
    local NrmlFaces = #()  
    local MatiFaces = #() 
    for subm in subMesh do (
      WCRNs = subm.dataWCRN
      local startIndex = 0;
      for i = 1 to subm.dataBSMM.count do (
        local subMeshMat = subm.dataBSMM[i]
        local matId = subMeshMat.textureIndex + 1
        local cornerStart = subm.dataBTRI.cornerStart[i] + 1
        for j = 1 to subMeshMat.numberOfFaces do (
          local face = subm.dataBTRI.cornerIndex[startIndex + j]
          local cA = WCRNs[face.x + cornerStart]
          local cB = WCRNs[face.y + cornerStart]
          local cC = WCRNs[face.z + cornerStart]	
          append VertFaces [cA.pos, cB.pos, cC.pos]
          append TexcFaces [cA.txc, cB.txc, cC.txc]
          append NrmlFaces [cA.nrm, cB.nrm, cC.nrm]
          append MatiFaces matId 
        )
        startIndex += subMeshMat.numberOfFaces
      )
    )

    -- create mesh
    local newMesh = Mesh \
             name:        nnkName  \
             vertices:    meshVerts \
             faces:       VertFaces \
             materialIDs: MatiFaces 

    -- Set the texture verts and faces
    setNumTVerts newMesh dataWLookup.txc.count 
    for i = 1 to dataWLookup.txc.count do (
      uv = dataWLookup.txc[i]
      if (flipVcoord) then (
        uv.y = 1-uv.y
      )
      setTVert newMesh i uv
    )
    buildTVFaces newMesh
    for i = 1 to TexcFaces.count do setTVFace newMesh i TexcFaces[i]             

    update newMesh  

    -- Build up smoothing groups from incoming normals
    if chk_SetSmoothingGroups.checked then (
      local tools = (TopoTools      \
        triObj:newMesh               \
        faceCornerNormals:NrmlFaces \
        faceCornerVerts:VertFaces
      ) 
      select newMesh
      tools.RebuildSmoothing() 
      update newMesh
    )

    if (chk_SeeThru.checked) do
      newMesh.xray = true

    if (chk_Debug.checked) do format "ok!\n"  
    
    return newMesh
  )

  fn QuatApply v q = (
    m = q as Matrix3
    x = dot m.row1 v
    y = dot m.row2 v
    z = dot m.row3 v

    return ([x, y, z] as Point3)
  )

  local fiddlybits = #(
    "_cheek",
    "_chin",
    "_eye",
    "_forehead",
    "_finger",
    "_lowerlip",
    "_upperlip"
  )

  fn IsSmallBone bone = (
    for f in fiddlybits do (
      if (findString bone.name f) != undefined then (
        return true
      )
    )
    return false
  )

  fn MakeBones = (

    local i, j

    if (chk_Debug.checked) do format "debug: creating bones..."

    -- build bones
    myBone = #()
    for i = 1 to numBones do (
      local parent = boneInfo[i].parent

      -- create bone
      if (parent == i or boneInfo[i].name == "leftfoot_pin" or boneInfo[i].name == "rightfoot_pin") then (
        myBone[i] = Sphere radius:(35 * spn_Scale.value) segs:16 \
                    name:boneInfo[i].name pos:[0,0,0] smooth:true
      )
      else if (boneInfo[i].name == "weapon_grip") then (
        if GripMarker == undefined then (        
          myBone[i] = Box name:boneInfo[i].name pos:[0,0,0]
        ) else (
          myBone[i] = GripMarker name:boneInfo[i].name gripType:1 pos:[0,0,0]

        )
      )
      else if (boneInfo[i].name == "shield_grip") then (
        if GripMarker == undefined then (
          myBone[i] = Box name:boneInfo[i].name pos:[0,0,0]
        )
        else (
          myBone[i] = GripMarker name:boneInfo[i].name gripType:2 pos:[0,0,0]
        )
      )
      else (
        if (chk_BoneBall.checked) then (
          myBone[i] = Sphere radius:(35 * spn_Scale.value) segs:16 \
                      name:boneInfo[i].name pos:[0,0,0] smooth:true
        )
        else (
          myBone[i] = BoneSys.createBone [0,0,0] [1,0,0] [0,0,1]
          myBone[i].name   = boneInfo[i].name
          myBone[i].width  = 40 * spn_Scale.value
          myBone[i].height = 40 * spn_Scale.value
        )
      )

      -- link to parent
      if (parent == i or parent == 0) then (
        myBone[i].parent = undefined
      )
      else (
        myBone[i].parent = myBone[parent]
      )

      -- position and orientate relative to parent
      in coordsys parent myBone[i].rotation = FlipUpQuat dataRPOS[i].rot
      in coordsys parent myBone[i].position = (FlipUp dataRPOS[i].pos) * spn_Scale.value * 1000

      -- grips must be prerotated (hack fix)
      if (myBone[i].name == "weapon_grip" or myBone[i].name == "shield_grip") do (
        in coordsys parent myBone[i].rotation = (FlipUpQuat dataRPOS[i].rot) * ((angleAxis 90 [1,0,0]) as quat)
      )

      -- set miscellaneous properties
      if (myBone[i].name != "weapon_grip" and myBone[i].name != "shield_grip" and
          myBone[i].name != "leftfoot_pin" and myBone[i].name != "rightfoot_pin") do (
        myBone[i].setBoneEnable on 0
        myBone[i].boneAutoAlign = true
        myBone[i].boneFreezeLength = true
        myBone[i].boneScaleType = #none
      )
      myBone[i].wireColor = (color 0 0 255)
    )

    -- set bone lengths
    for b in myBone do (
      if (classOf b == BoneGeometry) do (
        -- bone length is guessed to be the average of the distances to its children
        -- if it's a terminating bone, just guess the length
        if (b.children.count > 0) then (
          local distSum = 0
          for b2 in b.children do
            distSum += distance b.pos b2.pos
          b.length = distSum / b.children.count
          if IsSmallBone b then (
            b.width  = 6 * spn_Scale.value
            b.height = 6 * spn_Scale.value            
          )          
        )
        else (
          -- TODO: look up the bone name and figure out a good size for it
          -- Probably just want to hide it put in a facial rig and what-have-you
          if IsSmallBone b then (
            b.width  = 4 * spn_Scale.value
            b.height = 4 * spn_Scale.value 
            b.length = 15 * spn_Scale.value                
          ) 
          else (
            b.length = 100 * spn_Scale.value      
          )
        )
      )
    )

    if (chk_Debug.checked) do format "ok!\n"    
  )


  fn MakeSkin newMesh = (
    local i,j,k

    if (chk_Debug.checked) do format "debug: creating skin..."

    max modify mode
    select newMesh
    subObjectLevel = 0

    -- create skin, and add bones
    mySkin = Skin()
    addModifier newMesh mySkin
    for i = 1 to numBones do
      skinOps.addBone mySkin myBone[i] 0

    -- reset all vertex weights
    subObjectLevel = 1
    allVerts = for j = 1 to newMesh.numVerts collect j
    skinOps.SelectVertices mySkin allVerts
    skinOps.resetSelectedVerts mySkin

    -- set vertex weights
    weighted = #{}
    with redraw off (
      for sm in subMesh do (
        for v = 1 to sm.dataBVWL.count do (
          local posIdx = sm.dataBVTX[v]
          if not weighted[posIdx] then (
            local wl = sm.dataBVWL[v]
            skinOps.ReplaceVertexWeights mySkin posIdx wl.boneIds wl.weights      
            weighted[posIdx] = true
          )
        )
      )
    )

    subObjectLevel = 0
    deselect $
    max utility mode

    if (chk_Debug.checked) do format "ok!\n"    
  )


  fn ImportASP fin = (
    local aspHeader = ReadChunkHeader fin

    if (aspHeader.mark != "BMSH") then (
      messageBox "This is not an ASP with a mesh"
      return false
    )  
    
    -- Create a lookup table for indexed corner data
    dataBLookup = strBCRN()
    dataWLookup = strWCRN()

    if not (ReadASP fin) then (
      return false
    )

    if (chk_Debug.checked) do (
      for smi = 1 to numSubMeshes do (
        DumpData subMesh[smi] smi
      )
    ) 

    if chk_DebugVertList.checked then (
      for sm in subMesh do (
        dbgMeshes = for v = 1 to sm.dataBVTX.count collect (
          local p = (FlipUp dataWLookup.pos[sm.dataBVTX[v]]) * 1000 * spn_Scale.value
          Sphere radius:(5 * spn_Scale.value) segs:16 name:(v as string) pos:p smooth:true wirecolor:(color 108 0 136)       
        )
      )
    )   
    
    for sm in subMesh do (
      for v = 1 to  sm.dataBVMP.count do (
        for corner in sm.dataBVMP[v].cornersInfluenced do (
          sm.dataWCRN[corner+1].pos = sm.dataBVTX[v]
        )          
      )        
    )    

    local isBrokenWorld = aspHeader.majorVersion == 5 and aspHeader.minorVersion == 1

    local newbie = MakeMesh flipVcoord:(isBrokenWorld or chk_FlipUV.checked)

    if (chk_Texture.checked and numTextures > 0) do (
      local mtools = MaterialTools()
      newbie.material = mtools.MakeMaterials textureNames debug:chk_Debug.checked
      if (newbie.material != undefined) then (
        setMeditMaterial 1 newbie.material
      )      
    )

    if (chk_Bone.checked and numBones > 0) do (
      with undo off (      
        makeBones()
        if (chk_Skin.checked) do (
          newSkin = MakeSkin newbie  
        )
      )
    )

    -- add siegemax specific things 
    select newbie
    addModifier newbie (ASPModDef())

    return true
  )


  fn GetOpenFileStream = (
    local fname = GetOpenFileName types:"Aspect Mesh (*.asp)|*.asp|All Files (*.*)|*.*|"
    if (fname == undefined) do
      return false

    -- figure out the node name from the filename
    local tokens = filterString fname "/\\"
    nnkName = (filterString tokens[tokens.count] ".")[1]

    aspFileIn = fopen fname "rb"
    if (aspFileIn == undefined) do (
      messageBox "Could not open file for binary reading!"
      return false
    )

    return true
  )


  on btn_ImportNow pressed do (
    local oldCoordsys

    oldCoordsys = set coordsys world

    if (GetOpenFileStream()) do (
      if (ImportASP aspFileIn) then
        format "ASP import successful.\n"
      else
        messageBox "ASP import failed."
      fclose aspFileIn
    )

    set coordsys oldCoordsys
  )

)


fn lanceImportASP = (
  addRollout ASPImport (newRolloutFloater "ASP Import" 200 350)
)

/*

clearlistener(); filein ((GetDir #scripts) +"\\ASPImport.ms"); lanceImportASP(); setListenerSel #(0,0)

*/