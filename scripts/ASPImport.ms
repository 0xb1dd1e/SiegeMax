-- Dungeon Siege ASP Import (Siege Max)
-- Lance ><>
-- 8/23/2002
-- updates Jan 2004 by Ghastley (DS LoA etc)

-------------------------------------------------------------------------------------------
-- Updates & Hacks
--
--  5/23/2025 biddle - Added support for 5.1 version (DS2BW)
--  5/24/2025 biddle - Optimize faces and add smoothing groups
--
-------------------------------------------------------------------------------------------

filein ((GetDir #scripts) +"\\TopoTools.ms")

rollout ASPImport "ASP Import"
(
  /*
  local V1_2 
  local V1_3   -- introduced WCRN section
  local V2_0   -- introduced STCH section
  local V2_1   -- introduced BBOX section
  local V2_2
  local V2_3
  local V2_4
  local V2_5
  local V4_0   -- introduced with Siege Max (DS1)
  local V4_1
  local v5_0   -- DS LoA 
  local v5_1   -- DS2 BW
*/

  struct strChunkHeader  ( mark = 0, majorVersion = 0, minorVersion = 0, extraVersion = 0 )
  struct strBoneInfo ( name, parent, flags )
  struct strBSMM ( textureIndex, numberOfFaces )
  struct strBVMP ( count, cornersInfluenced=#() )
  struct strBTRI ( cornerStart, cornerSpan, cornerIndex )
  struct strBVWL ( bones=#(), weights=#() )
  struct strSTCH ( token, vertexCount, vertexIndex )
  struct strRPOS ( invRot, invPos, rot, pos )

  struct strBCRN  ( pos=#(), nrm=#(), col=#(), spc= #(), txc=#(), opp=#() )
  struct strWCRN  ( pos=#(), weight=#(), bone=#(), nrm=#(), col=#(), txc=#(), opp=#() )

  struct strSubMesh ( id = -1, 
                      numSubTextures = 0,
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

  local textureName
  local boneInfo
  local subMesh

  local dataRPOS

  local myMesh
  local myMat
  local myBone
  local mySkin

  local dbgMeshes

  -- Keep lookup tabls of all corner attributes
  local dataBLookup
  local dataWLookup

  group "Options"
  (
    spinner spn_Scale "Scale:" range:[0.0001,1000.0,1.0] type:#float scale:0.01
    checkbox chk_Texture "Texture Mesh" checked:false
    checkbox chk_Bone "Bone Mesh" checked:false
    checkbox chk_Skin "Skin Mesh" checked:false
    checkbox chk_FlipUV "Flip UV" checked:false
    checkbox chk_BoneBall "Bones As Balls" checked:false
    checkbox chk_SeeThru "See Thru Mesh" checked:false
    checkbox chk_Debug "Show Debug Info" checked:true
    checkbox chk_DebugVertList "Debug Vert List" checked:false
  )
  button btn_ImportNow "Import..." width:100

  fn DumpData subMesh = (

    fn DumpList lst cutoff = (
      for v = 1 to lst.count do (
        if (v <= cutoff or v > lst.count-cutoff) then (
          format "  %: %\n" v lst[v]
        )
        else if (v == (cutoff+1) and lst.count > (cutoff*2)) then (
          format "     ...\n"
        )         
      )        
    )

    format "submesh[%]:\n" subMesh.id

    format " numSubTextures % \n" subMesh.numSubTextures
    format " numVertices    % \n" subMesh.numVertices
    format " numCorners     % \n" subMesh.numCorners
    format " numFaces       % \n" subMesh.numFaces
    format " numStitches    % \n" subMesh.numStitches

    format " dataBSMM:\n"
    for m in subMesh.dataBSMM do (
      format "  [%] numberOfFaces %\n" m.textureIndex m.numberOfFaces
    )

    format " dataBVTX:\n"
    DumpList subMesh.dataBVTX 3

    format " dataBCRN       % \n" subMesh.dataBCRN

    format " dataWCRN:\n"
    DumpList subMesh.dataWCRN 3 

    format " dataBVMP:\n"
    DumpList subMesh.dataBVMP 3 

    format " dataBTRI: % \n" subMesh.dataBTRI -- list of lists

    format " dataBVWL:\n"
    DumpList subMesh.dataBVWL 3   
    
    format " dataSTCH       % \n" subMesh.dataSTCH

    format " dataBLookup table sizes\n"
    format "    pos %\n" dataBLookup.pos.count
    format "    txc %\n" dataBLookup.txc.count
    format "    nrm %\n" dataBLookup.nrm.count

    format " dataWLookup table sizes\n"
    format "    pos %\n" dataWLookup.pos.count
    format "    txc %\n" dataWLookup.txc.count
    format "    nrm %\n" dataWLookup.nrm.count

  )

  fn FlipUp v =
  (
    return ([v.x,-v.z,v.y] as point3)
  )


  fn FlipUpQuat q =
  (
    return (quat q.x -q.z q.y q.w)
  )

  fn ReadQuat fin =
  (
    local x = ReadFloat fin
    local y = ReadFloat fin
    local z = ReadFloat fin
    local w = ReadFloat fin

    return (quat x y z w)
  )


  fn ReadVector fin =
  (
    local x = ReadFloat fin
    local y = ReadFloat fin
    local z = ReadFloat fin

    return ([x,y,z] as point3)
  )


  fn ReadCoord fin =
  (
    local u = ReadFloat fin
    local v = ReadFloat fin

    return ([u,v,0] as point3)
  )

  fn ReadFourCC fin =
  (
    local a = bit.intAsChar (ReadByte fin #unsigned)
    local b = bit.intAsChar (ReadByte fin #unsigned)
    local c = bit.intAsChar (ReadByte fin #unsigned)
    local d = bit.intAsChar (ReadByte fin #unsigned)
    return a+b+c+d
  )  

  fn ReadFourBB fin =
  (
    local a = ReadByte fin #unsigned
    local b = ReadByte fin #unsigned
    local c = ReadByte fin #unsigned
    local d = ReadByte fin #unsigned

    return #(a,b,c,d)
  )

   fn ReadFourBB2 fin =
  (
    local a = ReadByte fin +1 -- #unsigned
    local b = ReadByte fin +1 -- #unsigned
    local c = ReadByte fin +1 -- #unsigned
    local d = ReadByte fin +1 -- #unsigned

    return #(a,b,c,d)
  )

  fn ReadFourFF fin =
  (
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
    if i == 0 and addIfMissing then (
      append itms val
      i = itms.count
    )
    return i
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
    textureName = #()
    if (numTextures > 0) do
      for i = 1 to numTextures do
        textureName[i] = token[i]
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

    for i = 1 to numBones do
    (
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

    format "After ReadBSMM SubMesh[%]:\n" curSM
    DumpData subMesh[curSM]          
  )

  fn ReadBSUB fin = (

    if (chk_Debug.checked) do  format "debug: reading BSUB section..."

    curSM  += 1
    subMesh[curSM] = strSubMesh()
    subMesh[curSM].id = (ReadLong fin #unsigned)
    subMesh[curSM].numSubTextures = (ReadLong fin #unsigned)
    subMesh[curSM].numVertices = (ReadLong fin #unsigned)
    subMesh[curSM].numCorners = (ReadLong fin #unsigned)
    subMesh[curSM].numFaces = (ReadLong fin #unsigned)

    if (chk_Debug.checked) do format "ok!\n"    
    
    format "After ReadBSUB SubMesh[%]:\n" curSM
    DumpData subMesh[curSM]      
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

    format "After ReadBVTX SubMesh[%]:\n" curSM
    DumpData subMesh[curSM]  

    return true              
  )
  
  fn ReadBCorner fin lookup =
  (
    local p, w, b, n, c, u
    p = fetchIndex lookup.pos (ReadLong fin #unsigned)
    n = fetchIndex lookup.nrm (ReadNormal fin)
    c = fetchIndex lookup.col (ReadColour fin)
    s = fetchIndex lookup.spc (ReadColour fin)
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
/*
    subMesh[curSM].dataBCRN = #()
    for i = 1 to subMesh[curSM].numCorners do
    (
      local bvtxIndex = ReadLong fin
      local p = subMesh[curSM].dataBVTX[bvtxIndex]
      local n = ReadVector fin
      local c = ReadFourBB fin
      local unk0 = ReadLong fin
      local t = ReadCoord fin
      subMesh[curSM].dataBCRN[i] = strBCRN pos:p nrm:n col:c txc:t
    )
*/      
    if (chk_Debug.checked) do format "ok!\n"     

    format "After ReadBCRN SubMesh[%]:\n" curSM
    DumpData subMesh[curSM]           
  )

  fn ReadWCorner fin FixOffByOne lookup =
  (
    local p, w, b, n, c, u

    -- Discard the postion value in the WCRN
    (ReadVector fin)
    --p = fetchIndex lookup.pos (ReadVector fin)

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

    format "After ReadWCRN SubMesh[%]:\n" curSM
    DumpData subMesh[curSM]    
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

  fn ReadBTRI fin UseAncientLayout:false = (
    if (chk_Debug.checked) do
      format "debug: reading BTRI section..."

    if (subMesh[curSM].numFaces != ReadLong fin) do
      messageBox "error: BTRI numFaces don't match"

    subMesh[curSM].dataBTRI = strBTRI()

    -- read header
    subMesh[curSM].dataBTRI.cornerStart = #()
    subMesh[curSM].dataBTRI.cornerSpan = #()

    if not UseAncientLayout then
    (
      for i = 1 to subMesh[curSM].numSubTextures do
      (
        subMesh[curSM].dataBTRI.cornerStart[i] = ReadLong fin
        subMesh[curSM].dataBTRI.cornerSpan[i] = ReadLong fin
      )
    )    
/*    
    -- TODO: track down Ancient Triangle/Face examples

    if (version == 2.2) then
    (
      for i = 1 to subMesh[curSM].numSubTextures do
        subMesh[curSM].dataBTRI.cornerSpan[i] = ReadLong fin

      subMesh[curSM].dataBTRI.cornerStart[1] = 1

      for i = 1 to subMesh[curSM].numSubTextures - 1 do
        subMesh[curSM].dataBTRI.cornerStart[i + 1] = \
            subMesh[curSM].dataBTRI.cornerStart[i] + \
            subMesh[curSM].dataBTRI.cornerSpan[i]
    )
    else if (version > 2.2) then
    (
      for i = 1 to subMesh[curSM].numSubTextures do
      (
        subMesh[curSM].dataBTRI.cornerStart[i] = (ReadLong fin) + 1
        subMesh[curSM].dataBTRI.cornerSpan[i] = ReadLong fin
      )
    )
    else
    (
      for i = 1 to subMesh[curSM].numSubTextures do
      (
        subMesh[curSM].dataBTRI.cornerStart[i] = 1
        subMesh[curSM].dataBTRI.cornerSpan[i] = subMesh[curSM].numCorners
      )
    )
*/
    -- read data
    subMesh[curSM].dataBTRI.cornerIndex = #()
    for i = 1 to subMesh[curSM].numFaces do
    (
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

    for b = 1 to numBones do
    (
      count = ReadLong fin
      if count < 0 and b == numBones then (
        -- We could have a number of bones, only with a rigid 
        -- weight, but in most cases there was only 1 bone.
        -- TODO: The only way to tell is scan them in and see if 
        -- we reach the next section. 
        for i = v to subMesh[curSM].numVertices do (
          subMesh[curSM].dataBVWL[v].bones = #(1)
          subMesh[curSM].dataBVWL[v].weights = #(1)
        )
      )
      else (
        for j = 1 to count do (
          v = (ReadLong fin) + 1
          append subMesh[curSM].dataBVWL[v].bones b
          append subMesh[curSM].dataBVWL[v].weights (ReadFloat fin)
        )
      )
    )

    if (chk_Debug.checked) do format "ok!\n"

  )


  fn ReadSTCH fin =
  (
    if (chk_Debug.checked) do format "debug: reading STCH section..."

    subMesh[curSM].numStitches = ReadLong fin

    subMesh[curSM].dataSTCH = #()
    local i, j
    for i = 1 to subMesh[curSM].numStitches do
    (
      subMesh[curSM].dataSTCH[i] = strSTCH()
      subMesh[curSM].dataSTCH[i].token = ReadFourCC fin
      subMesh[curSM].dataSTCH[i].vertexCount = ReadLong fin
      subMesh[curSM].dataSTCH[i].vertexIndex = #()
      for j = 1 to subMesh[curSM].dataSTCH[i].vertexCount do
        subMesh[curSM].dataSTCH[i].vertexIndex[j] = (ReadLong fin)
    )
    if (chk_Debug.checked) do format "ok!\n"
  )


  fn ReadRPOS fin =
  (
    if (chk_Debug.checked) do format "debug: reading RPOS section..."

    if (numBones != ReadLong fin) do
      if (chk_Debug.checked) do
        messageBox "error: RPOS numBones don't match"

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

  fn ReadBBOX fin =
  (
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


  fn ReadBEND fin =
  (
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
      else if (header.mark == "WCRN") then (ReadWCRN fin (header.majorVersion < 5)) 
      else if (header.mark == "BTRI") then (ReadBTRI fin) -- TODO: check version for ancient tri list layouts
      else if (header.mark == "BEND") then (ReadBEND fin; exit)
      else legal = false
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
    local cornOffset = 1
    local VertFaces = #()
    local TexcFaces = #()  
    local NrmlFaces = #()  
    local MatiFaces = #() 
 
    for sm = 1 to numSubMeshes do (
      local f = 1
      WCRNs = subMesh[sm].dataWCRN
      --BVTXs = subMesh[sm].dataBVTX
      for i = 1 to subMesh[sm].numSubTextures do (
        local startIndex = subMesh[sm].dataBTRI.cornerStart[i] + cornOffset
        local matId = subMesh[sm].dataBSMM[i].textureIndex
        for j = 1 to subMesh[sm].dataBSMM[i].numberOfFaces do (
          local wa = subMesh[sm].dataBTRI.cornerIndex[j].x + startIndex
          local wb = subMesh[sm].dataBTRI.cornerIndex[j].y + startIndex
          local wc = subMesh[sm].dataBTRI.cornerIndex[j].z + startIndex
          local cA = WCRNs[wa]
          local cB = WCRNs[wb]
          local cC = WCRNs[wc]	
          --VertFaces[f] = [BVTXs[cA.pos], BVTXs[cB.pos], BVTXs[cC.pos]]
          VertFaces[f] = [cA.pos, cB.pos, cC.pos]
          TexcFaces[f] = [cA.txc, cB.txc, cC.txc]
          NrmlFaces[f] = [cA.nrm, cB.nrm, cC.nrm]
          MatiFaces[f] = matId 
/*
          if cA.pos > dataWLookup.pos.count or cB.pos > dataWLookup.pos.count or cC.pos > dataWLookup.pos.count then (
            format "bad % (%) [%,%,%] %\n"  sm f cA.pos cB.pos cC.pos dataWLookup.pos.count
          ) 
          else (
            format "% (%)  %:% %:% %:%\n" sm f  cA.pos dataWLookup.pos[cA.pos] cB.pos dataWLookup.pos[cB.pos] cC.pos dataWLookup.pos[cB.pos]
          )          
 */         
          f += 1
        )
      )
      cornOffset += subMesh[sm].numCorners
    )

    /*
    local sweetVerts = dataWLookup.pos
    format "Yer % sweeties: %n" sweetVerts.count sweetVerts
    for face in VertFaces do (
      if face.x > sweetVerts.count or face.y > sweetVerts.count or face.z > sweetVerts.count then (
        format "bad % %\n" face sweetVerts.count
      ) 
      else (
        format "% x:% y:% z:%\n" face dataWLookup.pos[face.x] dataWLookup.pos[face.y] dataWLookup.pos[face.z]
      )
    )*/

    messagebox "Let's rock!"
/*
    -- gather material ids
    local meshMids = #()
    for sm = 1 to numSubMeshes do
      for i = 1 to subMesh[sm].numSubTextures do
        for j = 1 to subMesh[sm].dataBSMM[i].numberOfFaces do
          append meshMids subMesh[sm].dataBSMM[i].textureIndex
*/

    -- create mesh
    myMesh = Mesh \
             name:        nnkName  \
             vertices:    meshVerts \ -- dataWLookup.pos \
             faces:       VertFaces \
             materialIDs: MatiFaces 

    messagebox "Got milk?"

    -- Set the texture verts and faces
    setNumTVerts myMesh dataWLookup.txc.count 
    for i = 1 to dataWLookup.txc.count do setTVert myMesh i dataWLookup.txc[i]
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

    if (chk_SeeThru.checked) do
      myMesh.xray = true

    if (chk_Debug.checked) do format "ok!\n"    
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
	
    local extensions = #(".dds", ".raw", ".psd")
    local basePath = dsGetOutputPath() + "\\" + (dsBuildContentLocation n)
    local texturepath = ""
    
    found = false
    for ext in extensions do (
      texturepath = basePath + ext
      if (doesFileExist texturepath) then (
        if (chk_Debug.checked) do format "Found: %\n" texturepath         
        found = true
        exit
      )
    )
    if not found then (
      if (chk_Debug.checked) do format "Missing: %\n" rawpath 
      texturepath = basePath
    )
    
    t.diffuseMap = BitmapTexture name:(n + "_diffuse") \
                   filename:(texturepath)
    t.opacityMap = BitmapTexture name:(n + "_opacity") \
                   filename:(texturepath) \
                   monoOutput: 1 \
                   alphaSource: 0

    return t
  )


  fn MakeMaterial =
  (
    if (chk_Debug.checked) do format "debug: creating textures..."

    -- create standard texture, or multi-material if needed
    if (numTextures > 1) then
    (
      myMat = MultiMaterial numSubs:numTextures
      for i = 1 to numTextures do
      (
        myMat.names[i] = textureName[i]
        myMat.materialList[i] = MakeTexture textureName[i]
      )
    )
    else
    (
      myMat = MakeTexture textureName[1]
    )

    -- assign material to mesh
    setMeditMaterial 1 myMat
    myMesh.material = myMat

    if (chk_Debug.checked) do format "ok!\n"    
  )


  fn QuatApply v q =
  (
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

  fn MakeBones =
  (

    local i, j

    if (chk_Debug.checked) do format "debug: creating bones..."

    -- build bones
    myBone = #()
    for i = 1 to numBones do
    (
      local parent = boneInfo[i].parent

      -- create bone
      if (parent == i or boneInfo[i].name == "leftfoot_pin" or boneInfo[i].name == "rightfoot_pin") then
      (
        myBone[i] = Sphere radius:(35 * spn_Scale.value) segs:16 \
                    name:boneInfo[i].name pos:[0,0,0] smooth:true
      )
      else if (boneInfo[i].name == "weapon_grip") then
      (
        if GripMarker == undefined then (        
          myBone[i] = Box name:boneInfo[i].name pos:[0,0,0]
        ) else (
          myBone[i] = GripMarker name:boneInfo[i].name gripType:1 pos:[0,0,0]

        )
      )
      else if (boneInfo[i].name == "shield_grip") then
      (
        if GripMarker == undefined then (
          myBone[i] = Box name:boneInfo[i].name pos:[0,0,0]
        )
        else (
          myBone[i] = GripMarker name:boneInfo[i].name gripType:2 pos:[0,0,0]
        )
      )
      else
      (
        if (chk_BoneBall.checked) then
        (
          myBone[i] = Sphere radius:(35 * spn_Scale.value) segs:16 \
                      name:boneInfo[i].name pos:[0,0,0] smooth:true
        )
        else
        (
          myBone[i] = BoneSys.createBone [0,0,0] [1,0,0] [0,0,1]
          myBone[i].name   = boneInfo[i].name
          myBone[i].width  = 40 * spn_Scale.value
          myBone[i].height = 40 * spn_Scale.value
        )
      )

      -- link to parent
      if (parent == i or parent == 0) then
        myBone[i].parent = undefined
      else
        myBone[i].parent = myBone[parent]

      -- position and orientate relative to parent
      in coordsys parent myBone[i].rotation = FlipUpQuat dataRPOS[i].rot
      in coordsys parent myBone[i].position = (FlipUp dataRPOS[i].pos) * spn_Scale.value * 1000

      -- grips must be prerotated (hack fix)
      if (myBone[i].name == "weapon_grip" or myBone[i].name == "shield_grip") do
        in coordsys parent myBone[i].rotation = (FlipUpQuat dataRPOS[i].rot) * ((angleAxis 90 [1,0,0]) as quat)

      -- set miscellaneous properties
      if (myBone[i].name != "weapon_grip" and myBone[i].name != "shield_grip" and
          myBone[i].name != "leftfoot_pin" and myBone[i].name != "rightfoot_pin") do
      (
        myBone[i].setBoneEnable on 0
        myBone[i].boneAutoAlign = true
        myBone[i].boneFreezeLength = true
        myBone[i].boneScaleType = #none
      )
      myBone[i].wireColor = (color 0 0 255)
    )

    -- set bone lengths
    for b in myBone do
    (
      if (classOf b == BoneGeometry) do
      (
        -- bone length is guessed to be the average of the distances to its children
        -- if it's a terminating bone, just guess the length
        if (b.children.count > 0) then
        (
          local distSum = 0
          for b2 in b.children do
            distSum += distance b.pos b2.pos
          b.length = distSum / b.children.count
          if IsSmallBone b then (
            b.width  = 6 * spn_Scale.value
            b.height = 6 * spn_Scale.value            
          )          
        )
        else
        (
          -- TODO: look up the bone name and figure out a good size for it
          -- Probably just want to hide it put in a facial rig and what-have-you
          if IsSmallBone b then (
            b.width  = 4 * spn_Scale.value
            b.height = 4 * spn_Scale.value 
            b.length = 15 * spn_Scale.value                
          ) else (
            b.length = 100 * spn_Scale.value      
          )
        )
      )
    )

    if (chk_Debug.checked) do format "ok!\n"    
  )


  fn MakeSkin =
  (
    local i,j,k

    if (chk_Debug.checked) do format "debug: creating skin..."

    max modify mode
    select myMesh
    subObjectLevel = 0

    -- create skin, and add bones
    mySkin = Skin()
    addModifier myMesh mySkin
    for i = 1 to numBones do
      skinOps.addBone mySkin myBone[i] 0

    -- reset all vertex weights
    subObjectLevel = 1
    allVerts = for j = 1 to myMesh.numVerts collect j
    skinOps.SelectVertices mySkin allVerts
    skinOps.resetSelectedVerts mySkin

    -- set vertex weights
    local cornOffset = 0

    with redraw off
      for sm = 1 to numSubMeshes do (
        for v = 1 to subMesh[sm].numVertices do (
          local wl = subMesh[sm].dataBVWL[v]
          --for corner in subMesh[sm].dataBVMP[v].cornersInfluenced do (
          --	skinOps.ReplaceVertexWeights mySkin corner wl.bones wl.weights
          --)    
          skinOps.ReplaceVertexWeights mySkin v wl.bones wl.weights
		    )        
      )

    subObjectLevel = 0
    deselect $
    max utility mode

    if (chk_Debug.checked) do format "ok!\n"    
  )


  fn ImportASP fin =
  (
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
      for sm = 1 to numSubMeshes do (
        format "SubMesh[%]:\n" sm
        DumpData subMesh[sm]      
      )
    ) 

    if chk_DebugVertList.checked then (
      for sm = 1 to numSubMeshes do (
        dbgMeshes = for v = 1 to subMesh[sm].dataBVTX.count collect (
          local p = (FlipUp subMesh[sm].dataBVTX[v]) * 1000 * spn_Scale.value
          Sphere radius:(5 * spn_Scale.value) segs:16 name:(v as string) pos:p smooth:true wirecolor:(color 108 0 136)       
        )
      )
    )   
    
    for sm = 1 to numSubMeshes do (
      for v = 1 to  subMesh[sm].dataBVMP.count do (
        for corner in subMesh[sm].dataBVMP[v].cornersInfluenced do (
          subMesh[sm].dataWCRN[corner+1].pos = subMesh[sm].dataBVTX[v]
        )          
      )        
    )    

    local isBrokenWorld = aspHeader.majorVersion == 5 and aspHeader.minorVersion == 1

    MakeMesh flipVcoord:(isBrokenWorld or chk_FlipUV.checked)

    if (chk_Texture.checked and numTextures > 0) do
      MakeMaterial()

    if (chk_Bone.checked and numBones > 0) do
    (
      with undo off (      
        makeBones()
        if (chk_Skin.checked) do (
            makeSkin()
          )
      )
    )

    -- add siegemax specific things
    select myMesh
    addModifier myMesh (ASPModDef())

    return true
  )


  fn GetOpenFileStream =
  (
    local fname = GetOpenFileName types:"Aspect Mesh (*.asp)|*.asp|All Files (*.*)|*.*|"
    if (fname == undefined) do
      return false

    -- figure out the node name from the filename
    local tokens = filterString fname "/\\"
    nnkName = (filterString tokens[tokens.count] ".")[1]

    aspFileIn = fopen fname "rb"
    if (aspFileIn == undefined) do
    (
      messageBox "Could not open file for binary reading!"
      return false
    )

    return true
  )


  on btn_ImportNow pressed do
  (
    local oldCoordsys

    oldCoordsys = set coordsys world

    if (GetOpenFileStream()) do
    (
      if (ImportASP aspFileIn) then
        format "ASP import successful.\n"
      else
        messageBox "ASP import failed."
      fclose aspFileIn
    )

    set coordsys oldCoordsys
  )

)


fn lanceImportASP =
(
  addRollout ASPImport (newRolloutFloater "ASP Import" 200 265)
)

/*

clearlistener(); filein ((GetDir #scripts) +"\\ASPImport.ms"); lanceImportASP(); setListenerSel #(0,0)

*/