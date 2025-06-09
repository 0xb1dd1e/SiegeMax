struct MaterialTools (

  fn MakeStdMat matName debug:false = (

    local t = StandardMaterial          \
              name:             matName \
              shaderByName:     "blinn" \
              adTextureLock:    true    \
              adLock:           true    \
              showInViewport:   true    \
              diffuseMapEnable: true    \
              opacityMapEnable: true
	
    -- look for the bitmap in the output path.

    -- The original SiegeMax did not have DDS support, but you can
    -- install the NetImmerse/Gamebryo gmax plugin that does have it.
    -- https://www.moddb.com/addons/dds-and-nif-support-for-gmax

    local extensions = #(".dds", ".raw", ".psd")

    -- Look in the user's bits, and any bitmap paths they've configured
    local bitmapFolders = join #(dsGetOutputPath()) (for m in #{1..mapPaths.count()} collect (mapPaths.get m))    
    local texturepath = ""
    
    local found = false
    if (debug) do format "locate: %\n"  (dsBuildContentLocation matName)         
    for folder in bitmapFolders do (
        if (debug) do format "search: %\n" folder             
        local basePath = folder + "\\" + (dsBuildContentLocation matName)
        for ext in extensions do (
            texturepath = basePath + ext  
            if (debug) do format "Check: %\n" texturepath         
            found = (getFiles texturepath).count == 1
            if found then (
                if (debug) do format "Found: %\n" texturepath         
                exit
            )
        )
        if found then (
            exit
        ) else (
            texturepath = ""            
        )
    )

    if not found then (
        if (debug) do format "Missing: %\n"  (dsBuildContentLocation matName) 
        texturepath = matName
    )
    
    t.diffuseMap = BitmapTexture name:(matName + "_diffuse") \
                   filename:(texturepath)
    t.opacityMap = BitmapTexture name:(matName + "_opacity") \
                   filename:(texturepath) \
                   monoOutput: 1 \
                   alphaSource: 0

    return t
  ),

  fn MakeMaterials matList debug:false = (

    -- create standard material, or multi-material if needed
    local myMat = undefined
     
    if (debug) do format "debug: creating materials% \n" matList
      
    if matList.count > 1 then (
        myMat = MultiMaterial numSubs:(matList.count)
        for m in #{1..matList.count} do (
            myMat.names[m] = matList[m]
            myMat.materialList[m]= MakeStdMat matList[m] debug:debug
        )
    )
    else if matList.count == 1 then (
        myMat = MakeStdMat matList[1] debug:debug
    )

    return myMat

    /*    
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
    */
  )

)
