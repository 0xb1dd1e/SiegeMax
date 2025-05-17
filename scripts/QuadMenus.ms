---------------------------------------------------------------------------
-- This file initializes the Quad Menus items for Siege Max
--
-- See the "Add-On Examples/CustomQuadMenus.ms" file for instructions
-- on how you can add your own custom menus to Siege Max
--
---------------------------------------------------------------------------

------------------------------------------------------------------
-- Define housekeeping tools so that the all of our macroscripts 
-- and quad menus items are are deleted when we quit gmax
------------------------------------------------------------------

global glb_CurrentHousekeepingCategories = #()

---------------------------------------------------
fn DeleteMacroScriptsInCategoryCallback cat =
(
	fn FindSubMenuItemsByName m searchname = (
		for smi = 1 to m.numItems() do
		(
			local sm = m.getItem smi
			local smt = sm.gettitle()
			if smt == searchname  then
			(
		 			return sm
			)
		)
		return undefined
	)
	
	format "Deleting macroscripts and Quad Menu items in category [%]\n" cat
	
	local dvq = menuMan.findQuadMenu "Default Viewport Quad" 
			
	-- Remove the orphaned Quad Menu entries
	for menuquadnum = 1 to 4 do
	(
		local qm = dvq.getMenu menuquadnum
		if (qm != undefined) then
		(
			local mn = FindSubMenuItemsByName qm ("Context "+cat)
			if (mn!= undefined) then qm.RemoveItem mn
		)
	)
	
	-- Remove the macroscript files
	ToolCategoryMacroscriptFiles = GetFiles (GetDir #UI + "/macroscripts/" + cat + "-*.mcr")

	for i = 1 to ToolCategoryMacroscriptFiles.count do
		deletefile ToolCategoryMacroscriptFiles[i]
)

---------------------------------------------------
fn PrepareCategoryForHousekeeping cat =
(
	catid = ("SiegeMaxHousekeeping-"+cat) as name
	
	if (findItem glb_CurrentHousekeepingCategories catid) != 0 then
	(
		msg = "The Add-On category ["
		msg += cat
		msg += "] is already set up for housekeeping!\n\n"
		msg += "Check to be sure that you don't have two Add-On files that share a category!"
		
		MessageBox msg title:"Add-On initialization error"
		
		return false
	)
	
	append glb_CurrentHousekeepingCategories catid
	
	DeleteMacroScriptsInCategoryCallback cat
	
	scripttext = stringstream ""
	format "(DeleteMacroScriptsInCategoryCallback \"%\")" cat to:scripttext 
	callbacks.addScript #preSystemShutdown  scripttext  id:catid 
	
	format "Macroscript category [%] has been set up for housekeeping\n" cat
	
)

-- Put all the macroscripts in this file under housekeeping
PrepareCategoryForHousekeeping "Siege Max Tools"

---------------------------------------------------
---------------------------------------------------
MacroScript LaunchPreview
ButtonText:"Launch Previewer"
Category:"Siege Max Tools"
Tooltip:"Launch Previewer"
(
  fn IsSelectable =
  (
    try
    (
      if ($selection.count != 1) do return false
      if $selection[1] == undefined do return false
      if dsIsDummyObject $selection[1] do return false

      if not (canConvertTo $selection[1] Editable_Mesh) do return false

      local nm = dsLowerCase $selection[1].name
      if (nm.count > 2 and (nm[1] == "t") and nm[2] == "_" ) do return dsDoesNodeViewerExist()
      if (nm.count > 2 and (nm[1] == "m") and nm[2] == "_" ) do return dsDoesAnimViewerExist()

      if ($skinmesh != undefined) and (dsLowerCase ($selection[1].name) != "skinmesh") do return false

      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and (nm[1] == "t") and nm[2] == "_" ) do return dsDoesNodeViewerExist()
      if (nm.count > 2 and (nm[1] == "a" or nm[1] == "m") and nm[2] == "_" ) do return dsDoesAnimViewerExist()
    )
    catch ()

    return false
  )

  on isVisible return true
  on isEnabled return IsSelectable()

  on Execute do
  (
    try
    (
      if ($.modifiers.count != 0) do
      (
        modPanel.setCurrentObject $.modifiers[1]
        subobjectLevel = 0
      )

      local oldtime = slidertime
      slidertime = 0  

      if ($.material == undefined) then
      (
        messageBox "The selected object has no material assigned to it!\n\nObjects must be texture mapped before you can export them" title:"Ooops!"
        dsPreviewSelected()
      )
      else if ((classOf $.material == MultiMaterial and classOf $.material[1].diffuseMap == BitmapTexture and not doesFileExist $.material[1].diffuseMap.fileName) or
               (classOf $.material == StandardMaterial and classOf $.material.diffuseMap == BitmapTexture and not doesFileExist $.material.diffuseMap.fileName)) then
      (
        messageBox "The selected object is assigned to a material with a diffuse map that points to a non-existant bitmap." title:"Ooops!"
        local mat = $.material
        $.material = undefined
        dsPreviewSelected()
        $.material = mat
      )
      else
      (
        dsPreviewSelected()
      )

      slidertime = oldtime
    )
    catch ()
  )
)


----------------------------------------------------
MacroScript ExportSno
ButtonText:"Export Siege Node"
Category:"Siege Max Tools"
Tooltip:"Export Siege Node File (SNO)"
(
  fn IsSelectable =
  (
    try
    (
      if ($selection.count != 1) do return false
      if ($selection[1] == undefined) do return false
      if (dsIsDummyObject $selection[1]) do return false

      if not (SelectedHasASNOModifier()) do return false

      if ($selection[1].material == undefined) do return false

      nm = dsLowerCase $selection[1].name
      if (nm.count > 2 and nm[1] == "t" and nm[2] == "_" ) do return true
    )
    catch ()

    return false
  )

  on isVisible return true
  on isEnabled return IsSelectable()

  on Execute do
  (
    try
    (
      if ($.modifiers.count != 0) do
      (
        modPanel.setCurrentObject $.modifiers[1]
        subobjectLevel = 0
      )

      local oldtime = slidertime
      slidertime = 0

      if ($.material == undefined) then
      (
        messageBox "The selected object has no material assigned to it!\n\nObjects must be texture mapped before you can export them" title:"Ooops!"
      )
      else
      (
        dsExportSelected()
      )

      slidertime = oldtime
    )
    catch ()
  )
)

----------------------------------------------------
MacroScript ExportAnim
ButtonText:"Export Animation"
Category:"Siege Max Tools" 
Tooltip:"Export Animation File (PRS)" 
(
  fn IsSelectable= 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      nm = dsLowerCase $selection[1].name    
      
      --if (nm == "skinmesh") or (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then
      
      if (nm == "skinmesh") then
      (
        nm = dsLowerCase (getfilenamefile maxfilename)
        if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
      )
      
    )
    catch ()
    return false
  )
  
    on isVisible return true
    on isEnabled return IsSelectable()

  on Execute do
  (
    try
    (
      if $.modifiers.count != 0 then 
      (
        modPanel.setCurrentObject $.modifiers[1]
        subobjectLevel = 0
      )
      local oldtime = slidertime
      slidertime = 0
       if ($.material == undefined) then 
      (
        MessageBox "The selected object has no material assigned to it!\n\nObjects must be texture mapped before you can export them" title:"Ooops!"
      )
      else
      (
        dsExportSelected()
      )

      slidertime = oldtime
    )
    catch()
  )
)

----------------------------------------------------
MacroScript ExportMesh
ButtonText:"Export Mesh"
Category:"Siege Max Tools" 
Tooltip:"Export Mesh File (ASP)" 
(
  fn IsSelectable= 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      if ($selection[1].material == undefined) then return false      
      
      if not (canConvertTo $selection[1] Editable_Mesh) then return false

      nm = dsLowerCase $selection[1].name
      if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true
      
      if (nm == "skinmesh" ) then 
      (
        nm = dsLowerCase (getfilenamefile maxfilename)
        if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true
      )
    )
    catch ()
    return false
  )
  
    on isVisible return true
    on isEnabled return IsSelectable()

  on Execute do
  (
    try
    (
      if $.modifiers.count != 0 then        (
        modPanel.setCurrentObject $.modifiers[1]
        subobjectLevel = 0
      )
      local oldtime = slidertime
      slidertime = 0
      
      if ($.material == undefined) then 
      (
        MessageBox "The selected object has no material assigned to it!\n\nObjects must be texture mapped before you can export them" title:"Ooops!"
      )
      else
      (
        dsExportSelected()
      )

      slidertime = oldtime
    )
    catch()
  )
)

----------------------------------------------------
MacroScript AddRefEquipment
ButtonText:"Add Reference Equipment"
Category:"Siege Max Tools" 
Tooltip:"Add reference equipment" 
(
  fn IsSelectable = 
  (
    try (
      -- $$$ Need to make sure the grips are associated with this skinmesh!
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      if not (canConvertTo $selection[1] Editable_Mesh) then return false
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count <= 2 or nm[1] != "a" or nm[2] != "_" ) then return false
      
      if $weapon_grip == undefined then return false
      if $shield_grip == undefined then return false
      if $grip_reference_*.count == 1 then return false
      return true
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    try (
      UnEquipEverything false 
      
      EquipWeaponUsingStance $selection[1] false 
      EquipShieldUsingStance $selection[1] false
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript RemoveRefEquipment
ButtonText:"Remove Reference Equipment"
Category:"Siege Max Tools" 
Tooltip:"Remove reference equipment" 
(
  fn IsSelectable= 
  (
    try (
      -- $$$ Need to make sure the grips are associated with this skinmesh!
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      if not (canConvertTo $selection[1] Editable_Mesh) then return false
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count <= 2 or nm[1] != "a" or nm[2] != "_" ) then return false
      
      if $weapon_grip == undefined then return false
      if $shield_grip == undefined then return false
      if ($grip_reference_*).count == 0 then return false
      return true
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    try (
      UnEquipEverything false 
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript ShowTracers
ButtonText:"Show Tracers"
Category:"Siege Max Tools" 
Tooltip:"Add tracer boxes to the scene" 
(
  fn IsSelectable = 
  (
    try (
      -- $$$ Need to make sure the grips are associated with this skinmesh!
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      if not (canConvertTo $selection[1] Editable_Mesh) then return false
      
      if (aspmoddef == undefined) or ((classof aspmoddef) != modifier) then return false
      if $selection[1].modifiers["Siege Max ASP"] == undefined then return false
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count < 2 or nm[1] != "a" or nm[2] != "_" ) then return false
      
      return ($__tracerbox__*).count == 0
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    try (
      dsglb_tracers = #()
      dscb_CalculateTracers()
      for s in dsglb_tracers do
      (
        b = box  pos:s[2] name:"__tracerbox__"
        in coordsys local b.rotation = s[3  ]
      )       dsglb_tracers = #()
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript RemoveTracers
ButtonText:"Remove Tracers"
Category:"Siege Max Tools" 
Tooltip:"Delete tracer boxes from the scene" 
(
    on isVisible return ($__tracerbox__*).count > 0
    on isEnabled return true

  on Execute do
  (
    delete $__tracerbox__*
  )
  
)

----------------------------------------------------
MacroScript AddLoopEvents
ButtonText:"Add Loop Events"
Category:"Siege Max Tools" 
Tooltip:"Add Begin/End events to looping anim" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name
      if (nm != "skinmesh") and (nm.count < 2 or nm[1] != "m" or nm[2] != "_" ) then
      (
        return false
      )
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count < 2 or nm[1] != "a" or nm[2] != "_" ) then return false
            
      return not (HasLoopEventAtAnimEnd $selection[1])
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    try (
      AddBegEndEvents()
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript RemoveLoopEvents
ButtonText:"Remove Loop Events"
Category:"Siege Max Tools" 
Tooltip:"Remove Begin/End events from anim" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name
      if (nm != "skinmesh") and (nm.count < 2 or nm[1] != "m" or nm[2] != "_" ) then
      (
        return false
      )
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count < 2 or nm[1] != "a" or nm[2] != "_" ) then return false
      
      return HasLoopEventAtAnimEnd $selection[1]
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    try (
      DeleteBegEndEvents()
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript OpenAnimEventTool
ButtonText:"Open Anim Event Tool"
Category:"Siege Max Tools" 
Tooltip:"Open the anim event editing tool" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name
      if (nm != "skinmesh") and (nm.count < 2 or nm[1] != "m" or nm[2] != "_" ) then
      (
        return false
      )
        
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
    )
    catch()
    return false
  )
  
    on isVisible return true
    on isEnabled return IsSelectable()

  on Execute do
  (
    try (      
      if (critpointfloat != undefined) then closerolloutfloater critpointfloat
      critpointfloat = newRolloutFloater ("Events")  220 582 
      addrollout CriticalEventsFloater critpointfloat 
    )
    catch()
  )
  
)
----------------------------------------------------
MacroScript ListAnimEvents
ButtonText:"List Anim Events"
Category:"Siege Max Tools" 
Tooltip:"Show dialog with current anim event list" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name
      if (nm != "skinmesh") and (nm.count < 2 or nm[1] != "m" or nm[2] != "_" ) then
      (
        return false
      )
      
      if (aspmoddef == undefined) or ((classof aspmoddef) != Modifier) then return false
      if ($selection[1].Modifiers["Siege Max ASP"]) == undefined then return false  
    
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
    )
    catch()
    return false
  )
  
    on isVisible return true
    on isEnabled return IsSelectable()

  on Execute do
  (
    try (
      ListCriticalEvents() 
    )
    catch()
  )
  
)

----------------------------------------------------
MacroScript AddRootPosMarker
ButtonText:"Add/Reset Root Marker" 
Category:"Siege Max Tools" 
Tooltip:"Adds or resets the root position marker" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name
      if (nm != "skinmesh") and (nm.count < 2 or nm[1] != "m" or nm[2] != "_" ) then
      (
        return false
      )
      
      local itm = selection[1]
      
      if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and (nm[1] == "a" or nm[1] == "m") and nm[2] == "_" ) then return true
    )
    catch()
    return false
  )
  
    on isVisible return true
    on isEnabled return IsSelectable()

  on Execute do
  (
    try
    (
		if $root != undefined and $root.isFrozen and $root.position.keys.count >= 2 then
		(
			local msg = "It appears that you are currently in 'Animate-In-Place' mode\n\n"
			msg += "If you reset the root now, any translation of the model in the\n"
			msg += "original animation will be lost!\n\n"
			msg += "To preserve the original translation, first cancel 'Animate-In-Place'\n"
			msg += "and then reset the root marker\n\n" 
			msg += "Are you SURE to want to reset the root now?\n"
			msg += "(possibly losing translation information)" 
			if not dsQueryBox msg default:false title:"Warning!" then
			(
				return false
			)
		)
		ResetRootPosMarker()
    )
    catch
    (
      format "Unable to load new ROOT object from Reference_Scenes\GPG_RefObjs"
    )
  )
  
)

----------------------------------------------------
MacroScript AnimateRootPosMarker
ButtonText:"Animate Root Marker"
Category:"Siege Max Tools"
Tooltip:"Set first and last keys for root position marker" 
(
	on isVisible do
	(
		
		try (
			if $root == undefined then return false
			if $root.isfrozen then return false
			if $root.position.keys.count >= 2 then return false
			
			if ($selection.count != 1) then return false
			if $selection[1] == undefined then return false
			if dsIsDummyObject $selection[1] then return false
	      
			local nm = dsLowerCase $selection[1].name
			if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
			
		    nm = dsLowerCase (getfilenamefile maxfilename)
     	 	if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
	     
		)
		catch()
		return false
	)

 	on Execute do
	(
 		AddFirstLastRootPosMarkerKeys $
	)
  
)

----------------------------------------------------
MacroScript RemoveRootPosTranslation
ButtonText:"Enable Animate-In-Place"
Category:"Siege Max Tools" 
Tooltip:"Remove translation of a character so that it animates in place" 
(
	on isVisible do
	(
		try 
		(
			if $root == undefined then return false
			if $root.isFrozen then return false
			if $root.position.keys.count < 2 then return false
		
			if ($selection.count != 1) then return false
		    if $selection[1] == undefined then return false
		    if dsIsDummyObject $selection[1] then return false
	      
			local nm = dsLowerCase $selection[1].name
			if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
			
		    nm = dsLowerCase (getfilenamefile maxfilename)
     	 	if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
		)
	    catch()
		return false
	)
  
	on Execute do
	(
		RemoveRootTranslation $
	)
  
)

----------------------------------------------------
MacroScript RestoreRootPosTranslation
ButtonText:"Cancel Animate-In-Place"
Category:"Siege Max Tools" 
Tooltip:"Restore translation of a character so that it follows ROOT" 
(
	on isVisible do
	(
		try 
		(
			if $root == undefined then return false
			if not $root.isFrozen then return false
			if $root.position.keys.count < 2 then return false
		
			if ($selection.count != 1) then return false
		    if $selection[1] == undefined then return false
		    if dsIsDummyObject $selection[1] then return false
	      
			local nm = dsLowerCase $selection[1].name
			if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
			
		    nm = dsLowerCase (getfilenamefile maxfilename)
     	 	if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true
			
		)
	    catch()
		return true
	)
  
	on Execute do
	(
		RestoreRootTranslation $
	)
  
)

----------------------------------------------------
MacroScript OpenItemToolkit
ButtonText:"Open Item Tool Kit"
Category:"Siege Max Tools" 
Tooltip:"Open Item Tool Kit" 
(
  fn IsSelectable = 
  (
    try (
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
            
      if not (canConvertTo $selection[1] Editable_Mesh) then return false

      nm = dsLowerCase $selection[1].name
      if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true
      
      if (nm == "skinmesh" ) then 
      (
        nm = dsLowerCase (getfilenamefile maxfilename)
        if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true
      )
    )
    catch()
    return false
  )
  
    on isVisible return IsSelectable()
    on isEnabled return true

  on Execute do
  (
    OpenHelpTools()
  )
  
)

----------------------------------------------------
MacroScript OpenASPToolkit
ButtonText:"Open Aspect Tool Kit"
Category:"Siege Max Tools" 
Tooltip:"Open Aspect Tool Kit" 
(
  fn SelectedIsAnASPorPRS = 
  (
    try
    (    
      if (aspmoddef == undefined) or ((classof aspmoddef) != modifier) then return false
      if (snomoddef == undefined) or ((classof snomoddef) != modifier) then return false
      
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      nm = dsLowerCase $selection[1].name 
      if (nm.count > 2 and (nm[1] == "m") and nm[2] == "_" ) then return true  
      if (nm != "skinmesh" ) then return false
      
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and (nm[1] == "m") and nm[2] == "_" ) then return true  
    )
    catch ()
    return false
  )

  On isVisible return SelectedIsAnASPorPRS() 
  On isEnabled return true
  
  On execute Do  
  (    
    if SelectedHasASNOModifier() then 
    (
      MessageBox("Can't open ASP Tool Kit with a SNO modifier on stack")
      return false
    )

    if ($selection[1].modifiers["Siege Max ASP"]) == undefined then 
    (
      try 
      (
        AddModifier $selection[1] (ASPModDef())
      )
      catch( return false )
    )

    gASPPopUp()
    
    return true

  )
  
)

----------------------------------------------------
MacroScript OpenNeckStitchToolkit
ButtonText:"Open Neck Stitch Tool Kit"
Category:"Siege Max Tools" 
Tooltip:"Open Neck Stitch Tool Kit" 
(
  fn SelectedIsAnASP = 
  (
    try
    (    
      if (aspmoddef == undefined) or ((classof aspmoddef) != Modifier) then return false
      if (snomoddef == undefined) or ((classof snomoddef) != Modifier) then return false
      
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name 
      if (nm.count > 2 and (nm[1] == "m") and nm[2] == "_" ) then return true  
      
      if (nm != "skinmesh" ) then return false
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true  
    )
    catch ()
    return false
  )

  On isVisible return SelectedIsAnASP() 
  On isEnabled return true
    
  On execute Do  
  (    
    if SelectedHasASNOModifier() then 
    (
      MessageBox("Can't open Neck Stitch Tool Kit with a SNO modifier on stack")
      return false
    )
    
    if ($selection[1].Modifiers["Siege Max ASP"]) == undefined then 
    (
      max modify mode
      
      try 
      (
        AddModifier $selection[1] (ASPModDef())              
      )
      catch( return false )
      
      -- Switch over to modify mode, so we can adjust the ASP parameters
    )
    
    OpenNeckToolkit()     
    return true
  )
  
)

----------------------------------------------------
MacroScript OpenSNOToolkit
ButtonText:"Open Siege Node Tool Kit"
Category:"Siege Max Tools" 
Tooltip:"Open Siege Node Tool Kit" 
(
  fn SelectedIsASNO = 
  (
    try
    (
      if (snomoddef == undefined) or ((classof snomoddef) != Modifier) then return false
      
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false  
      
      local nm = dsLowerCase $selection[1].name
      if (nm.count > 2 and (nm[1] == "t") and nm[2] == "_" ) then return true  
    )
    catch ()
    return false
  )

  On isVisible do
  (
    if ( SelectedIsASNO() ) then
    (
      return true
    )
    else
    (
      return false
    )
  )    
  
  On isEnabled return true;
  
  On execute Do  
  (    
    if $selection[1].modifiers["Siege Max ASP"] != undefined then 
    (
      MessageBox("Can't open Siege Node Tool Kit with an ASP modifier on stack")
      return false
    )

    if not SelectedHasASNOModifier() then 
    (
      max modify mode
      
      try 
      (
        AddModifier $selection[1] (SNOModDef())              
      )
      catch( return false )       )
    
    gSNOPopUp()
    
    return true
  )
  
)

----------------------------------------------------
MacroScript SelectAllSNOs
ButtonText:"Select All Siege Nodes"
Category:"Siege Max Tools" 
Tooltip:"Select All Siege Nodes" 
(
  fn HasASNOmod n = 
  (
    try
    (
      if ($selection[1].modifiers["Siege Max SNO"]) != undefined then return true
    )
    catch ()
    return false
  )

  On isEnabled return true;
  On isEnabled return true;
  
  On execute Do  
  (    
    if (snomoddef == undefined) or ((classof snomoddef) != Modifier) then return false     
    snonodes = for n in $T_* where (HasASNOmod n) collect n
    
    select snonodes
    
    return true
  )
  
)

----------------------------------------------------
MacroScript SelectAllNonSNOs
ButtonText:"Select All Without Siege Nodes"
Category:"Siege Max Tools" 
Tooltip:"Select All Without Siege Nodes" 
(
  fn HasASNOmod n = 
  (
    try
    (
      if ($selection[1].modifiers["Siege Max SNO"]) != undefined then return true
    )
    catch ()
    return false
  )

  On isEnabled return true;
  On isEnabled return true;
  
  On execute Do  
  (    
    if (snomoddef == undefined) or ((classof snomoddef) != Modifier) then return false
    
    snonodes = for n in $T_* where (not HasASNOmod n) collect n
    
    select snonodes
    
    return true
  )
  
)

----------------------------------------------------
MacroScript OpenRefDropperToolkit
ButtonText:"Open RefObj Dropper"
Category:"Siege Max Tools" 
Tooltip:"Open Reference Object Dropper" 
(
  On isVisible return true 
  On isEnabled return true
    
  On execute Do  
  (    
    try
    (
      OpenRefObjDropper()
    )
    catch()
    
    return true
  )
  
)

----------------------------------------------------
MacroScript NamingKeyLookup
ButtonText:"Check Siege Max Name"
Category:"Siege Max Tools" 
Tooltip:"Check Siege Max Name" 
(
  On isVisible return true 
  On isEnabled return $selection.count == 1
    
  On execute Do  
  (    
    try
    (
      local lookname = dsLowerCase $selection[1].name
      local isskinmesh = false
      
      if lookname == "skinmesh" then
      (
        lookname = dolowercase (getfilenamefile maxfilename)
        isskinmesh = true
      )
              
      if lookname[1] == "m" or lookname[1] == "t" or lookname[1] == "a" then
      (
        addr = dsBuildContentLocation lookname
      )
      else
      (
        addr = undefined
      )
      
      local msg = stringstream ""
      if (addr == undefined) then
      (
        format "The selected object:\n\n\t%\n\nhas an invalid export name\n\nYou will not be able export it!" lookname to:msg
      )
      else
      (
        local lookdesc
        
        if lookname[1] == "m" then
        (
          type = "aspect mesh"
          addr = addr + ".ASP"
        )
        else if lookname[1] == "t" then
        (
          type = "terrain node"
          addr = addr + ".SNO"
        )
        else if lookname[1] == "a" then
        (
          type = "animation"
          addr = addr + ".PRS"
        )    
        
        if (isskinmesh) then
        (
          lookdesc = lookname + "   (objects named \"SkinMesh\" use filename)"
        )
        else
        (
          lookdesc = lookname
        )
        
        format "The selected %:\n\n\t%\n\ncan be exported as:\n\n\t%" type lookdesc addr to:msg 
      )
      MessageBox msg title:"Naming Key Lookup"
    )
    catch()
    
    return true
  )
  
)

----------------------------------------------------
MacroScript NothingToOperateOn
ButtonText:"*No Valid Mesh Selected*"
Category:"Siege Max Tools" 
Tooltip:"Why can't I use any Siege Max tools" 
(
   fn SelectedIsAnASPorSNO = 
  (
    try
    (    
      if (aspmoddef == undefined) or ((classof aspmoddef) != Modifier) then return false
      if (snomoddef == undefined) or ((classof snomoddef) != Modifier) then return false
      
      if ($selection.count != 1) then return false
      if $selection[1] == undefined then return false
      if dsIsDummyObject $selection[1] then return false
      
      local nm = dsLowerCase $selection[1].name 
      if (nm.count > 2 and (nm[1] == "m") and nm[2] == "_" ) then return true  
	  
      if (nm.count > 2 and (nm[1] == "t") and nm[2] == "_" ) then return true  
    
      if (nm != "skinmesh" ) then return false
      nm = dsLowerCase (getfilenamefile maxfilename)
      if (nm.count > 2 and nm[1] == "m" and nm[2] == "_" ) then return true  
      if (nm.count > 2 and nm[1] == "a" and nm[2] == "_" ) then return true  
    )
    catch ()
    return false
  )
 
  On isVisible return not SelectedIsAnASPorSNO()
  On isEnabled return true
    
  On execute Do  
  (    
    try
    (
		msg = "Siege Max only recognizes meshes with a valid name. Improperly named objects are ignored!\n\n"
		msg += "Meshes used for models and animations must have a name that starts with 'm_' (or be named 'SkinMesh')\n\n"
		msg += "Meshes used for terrain must have names that start with 't_'\n\n"
		msg += "NOTE: Models with the placeholder name 'SkinMesh' are assigned the current filename when they are exported\n\n"
		MessageBox msg title:"Remember..."
    )
    catch()
    
    return true
  )
  
)

----------------------------------------------------
MacroScript ChangeOutputPath
ButtonText:"Change Output Path"
Category:"Siege Max Tools" 
Tooltip:"Change the output path" 
(
	
	msg =  "The output directory is currently set to\n\n\t["
	msg +=  dsGetOutputPath()
	msg +=  "]\n\nChanging the output path allows you to export files to any writable directory\n\n"
	msg += "Restarting Siege Max will automatically reset the output path to the default value\n\n"
	msg += "Are you sure you want to continue?"
	
	ret = (dsQueryBox msg title:"" default:false)
	if ret then 
	(
		outdir = getsavepath caption:"Select a directory for Siege Max to use as an output path"
		if outdir != undefined then
		(
			if dsSetOutputPath outdir then
			(
				msg =  "Now using ["
				msg += outdir
				msg += "] as the output path\n\n"
				messagebox msg title:"Output path changed"
			)
			else
			(
				msg =  "Unable to set ["
				msg += outdir
				msg += "] as the output path\n\n"
				msg += "Check to make sure that you can write to that directory\n\n"
				msg += "Output will still be sent to ["
				msg += dsGetOutputPath()
				msg += "]"
				messagebox msg title:"Failed to change output path"
			)
		)
	)
)

----------------------------------------------------
----------------------------------------------------

fn UpdateSiegeMaxQuadMenus = 
(
	local dvq ,qm, mn, smi, nsm, nmi
	
	fn FindSubMenuItemsByName m searchname = (
		for smi = 1 to m.numItems() do
		(
			local sm = m.getItem smi
			local smt = sm.gettitle()
			if smt == searchname  then
			(
	 			return sm
			)
		)
		return undefined
	)
	
	
	dvq = menuMan.findQuadMenu "Default Viewport Quad" 
	
	qm= dvq.getMenu 3
	mn= FindSubMenuItemsByName qm "Context SiegeMax Tools 1"
	
	if (mn!= undefined) then
	(
		-- Print "Removing SiegeMaxTools1 menu"
		qm.RemoveItem mn
	)

	mn = menuMan.createMenu "Context SiegeMax Tools 1" 
	smi = menuMan.createSubMenuItem "" mn -- Create a sub menu item, so that we can add it
	smi.setDisplayFlat true
	qm.AddItem smi -1

		nmi = menuMan.createSeparatorItem()
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "OpenRefDropperToolkit" "Siege Max Tools"
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "OpenItemToolkit" "Siege Max Tools"
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "OpenNeckStitchToolkit" "Siege Max Tools"
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "OpenASPToolkit" "Siege Max Tools"
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "OpenSNOToolkit" "Siege Max Tools"
		mn.AddItem nmi -1

		nsm = menuMan.createMenu "Siege Max Equip Tools" 
		nsmi = menuMan.createSubMenuItem "" nsm -- Create a sub menu item, so that we can add it
		mn.AddItem nsmi -1
			nmi = menuMan.createActionItem "RemoveTracers" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "ShowTracers" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "RemoveRefEquipment" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "AddRefEquipment" "Siege Max Tools"
			nsm.AddItem nmi -1

		nsm = menuMan.createMenu "Siege Max Event Tools" 
		nsmi = menuMan.createSubMenuItem "" nsm -- Create a sub menu item, so that we can add it
		mn.AddItem nsmi -1
			nmi = menuMan.createActionItem "RemoveLoopEvents" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "AddLoopEvents" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "ListAnimEvents" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "OpenAnimEventTool" "Siege Max Tools"
			nsm.AddItem nmi -1

		nsm = menuMan.createMenu "Siege Max Root Tools" 
		nsmi = menuMan.createSubMenuItem "" nsm -- Create a sub menu item, so that we can add it
		mn.AddItem nsmi 0
			nmi = menuMan.createActionItem "AddRootPosMarker" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "AnimateRootPosMarker" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "RemoveRootPosTranslation" "Siege Max Tools"
			nsm.AddItem nmi -1
			nmi = menuMan.createActionItem "RestoreRootPosTranslation" "Siege Max Tools"
			nsm.AddItem nmi -1
			
		nmi = menuMan.createActionItem "NothingToOperateOn" "Siege Max Tools"
		mn.AddItem nmi -1
			
	qm= dvq.getMenu 4
	mn= FindSubMenuItemsByName qm "Context SiegeMax Tools 2"
	if (mn!= undefined) then
	(
		-- Print "Removing SiegeMaxTools2 menu"
		qm.RemoveItem mn
	)

	mn = menuMan.createMenu "Context SiegeMax Tools 2" 
	smi = menuMan.createSubMenuItem "" mn -- Create a sub menu item, so that we can add it
	smi.setDisplayFlat true
	qm.AddItem smi -1
	
		nmi = menuMan.createSeparatorItem()
		mn.AddItem nmi -1
	 	nmi = menuMan.createActionItem "LaunchPreview" "Siege Max Tools"
		mn.AddItem nmi -1
	 	nmi = menuMan.createActionItem "ExportAnim" "Siege Max Tools"
		mn.AddItem nmi -1
	 	nmi = menuMan.createActionItem "ExportMesh" "Siege Max Tools"
		mn.AddItem nmi -1
	 	nmi = menuMan.createActionItem "ExportSno" "Siege Max Tools"
		mn.AddItem nmi -1
	 	nmi = menuMan.createActionItem "ChangeOutputPath" "Siege Max Tools"
		mn.AddItem nmi -1
)

UpdateSiegeMaxQuadMenus()