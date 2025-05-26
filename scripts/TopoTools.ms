struct TopoTools (

  triObj = undefined,
  faceCornerNormals = #(), -- the normal indices each face corner
  faceCornerVerts = #(), -- the vertex indices each face corner

  fn EdgeIsSmooth curE oppE = (

    -- shorthand aliases
    local VI = faceCornerVerts 
    local RN = faceCornerNormals

    -- get the pair of corner indices P,Q that make up the two edges

    curF = ((curE-1) / 3) + 1    
    curP = (mod (curE-1) 3) + 1
    curQ = (mod (curE  ) 3) + 1
    
    oppF = ((oppE-1) / 3) + 1
    oppP = (mod (oppE-1) 3) + 1
    oppQ = (mod (oppE  ) 3) + 1
    
    -- does curE align with oppE or are they reversed PQ->QP
    if (VI[curF][curP] == VI[oppF][oppQ] and  VI[curF][curQ] == VI[oppF][oppP]) then (
      -- the edges are head-to-tail so swap the direction of the opp 
      temp = oppP; oppP = oppQ; oppQ = temp;
    )

    -- The positions at the ends of the edges had better match!
    if (VI[curF][curP] != VI[oppF][oppP] or VI[curF][curQ] != VI[oppF][oppQ]) then (
      format "ERROR: opposite edges aren't co-incidental! %:%:(%,%) %:%:(%,%)\n" curF curE curP curQ oppF oppE oppP oppQ
      return false
    )

    if (RN[curF][curP] != RN[oppF][oppP] or RN[curF][curQ] != RN[oppF][oppQ]) then (
      -- At least one of the render normals are not shared,
      -- TBD: what if only one pair matches? is that sigificant?
      return false
    )

    -- TBD: Render norms all match up but what if they and their face norms are all the same?
    -- Does that imply that they may not be explicitly smooth, and yet things just happen
    -- to 'work out'? Perhaps they are all from a sub-section of planar faces? 
    -- For now we will set them explicitly smooth.
    return true
    
  ),

  fn RebuildSmoothing = (

    for curF = 1 to (getNumFaces triObj) do (
      setFaceSmoothGroup triObj curF 0
    )

    for curF = 1 to (getNumFaces triObj) do (

      -- Visit the opposite faces, collecting their smoothing
      inUse = 0
      for i = 1 to 3 do (

        curE = ((curF-1)*3+i)
        revE = meshop.getEdgesReverseEdge triObj curE
        if revE.numberset > 1 then (
          format "WARNING: curE % has % reverse edges\n" curE revE.numberset
        )

        if revE.numberset > 0 then (
          oppE = (revE as array)[1]
          oppF = (oppE-1)/3 + 1
          inUse = bit.or inUse (getFaceSmoothGroup triObj oppF)
        )
      )
      
      -- Find three unused smoothing bits amongst the opposite faces
      next3free = #()
      for b = 0 to 31 do (
        if (bit.and inuse (bit.shift 1 b)) == 0 then (
          append next3free b
          if next3free.count == 3 then (
            exit
          )
        )
      ) 

      if next3free.count != 3 then (
        format "ERROR: Can't find three available bits around face %. Throw a fit!\n" curF
        return()
      )

      -- visit the opposite faces updating their smoothing and
      -- collecting the smoothing for the current face
      curSmoothBits = 0
 
      for j = 1 to 3 do (  

        nextSmoothBit = bit.shift 1 next3free[next3free.count]
        
        curE = (curF-1)*3+j
        revE = meshop.getEdgesReverseEdge triObj curE
        if revE.numberset > 1 then (
          format "WARNING: curE % has % reverse edges\n" curE revE.numberset
        )

        if revE.numberset > 0 then (
          oppE = (revE as array)[1]                  
          oppF = (oppE-1)/3 + 1
          
          -- Update smoothing if opposite face is ahead of current face OR the mesh is
          -- non-manifold and we need to check this 'extra' attached face (opposite edge
          -- does not point back to the current edge) 
          if (oppF > curF) or (curE != (meshop.getEdgesReverseEdge triObj oppE)) then (
            
            oppSmoothBits = getFaceSmoothGroup triObj oppF
            
            if (EdgeIsSmooth curE oppE) then (
              -- currF and oppF are smooth, so set a bit for them
              oppSmoothBits = bit.or oppSmoothBits nextSmoothBit
              curSmoothBits = bit.or curSmoothBits nextSmoothBit
              setFaceSmoothGroup triObj oppF oppSmoothBits
              next3free.count = next3free.count-1
            )
            else (
              -- Not smooth so must have no bits in common with opp             
              curSmoothBits = bit.and curSmoothBits (bit.not oppSmoothBits)
            )

          )
        )      
      )
      -- The smoothing bits for the current face are now known
      -- format "set % to %\n" curF curSmoothBits
      setFaceSmoothGroup triObj curF curSmoothBits
   
    )

  ),
    
  fn DumpStuff = (

	  local numVerts = getNumVerts triObj

    format "smoothing out % faces around %\n" numVerts (getNumFaces triObj)

    local discontinuities = #()

    fn dumpf fcn fcv o f disco = (

        fn checkIfSmooth fcn fcv o a b = (
            local averts = #(fcv[a].x, fcv[a].y, fcv[a].z)
            local anorms = #(fcn[a].x, fcn[a].y, fcn[a].z)
            local bverts = #(fcv[b].x, fcv[b].y, fcv[b].z)
            local bnorms = #(fcn[b].x, fcn[b].y, fcn[b].z)
            format "aface: %\t" a
            format "averts %\t" averts
            format "anorms %\n" anorms
            format "bface: %\t" b
            format "bverts %\t" bverts            
            format "bnorms %\n" bnorms
            local smoothies = (anorms as BitArray) * (bnorms as BitArray)
            if smoothies.isEmpty then (
              format "MISS -- This is NOT SMOOTH\n"
            ) 
            else if smoothies.numberset == 1 then (
              format "HIT only 1! %\n" smoothies
            ) 
            else if smoothies.numberset == 2 then (
              format "HIT exactly 2 %\n" smoothies
            ) 
            else (
              format "HIT more? % %\n" smoothies.numberset smoothies
            )
            return smoothies.isEmpty
        )        
    
        local inner = meshop.getEdgesUsingFace o f 
        local outer = meshop.getEdgesReverseEdge o inner
        local adjfs = meshop.getFacesUsingEdge o outer
        format "face: % inner %\n" f inner
        format "face: % outer %\n" f outer
        format "face: % opposites %\n" f adjfs
        for adjf in adjfs do (
            if not (checkIfSmooth fcn fcv o f adjf) then (
                append disco #(f, adjf)
            )
        )
    )

    for vtx = 1 to numVerts by 3 do (     
        dumpf faceCornerNormals faceCornerVerts triObj (vtx/3+1) discontinuities
        format "\n"
    ) 

    format "found % discos" discontinuities.count
    for d in discontinuities do (     
        format "%\n" d
    )
  )
)
