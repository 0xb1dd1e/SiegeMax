----------------------------------------------------------------------------------------
fn SafeSetSubObjectLevel lvl =
(
	
	max modify mode 
	
	try
	(
		if ($.modifiers["Siege Max ASP"] != undefined) then
		(
			modpanel.SetCurrentObject $.modifiers["Siege Max ASP"]
			dsSetMeshSelectSubLevel $.modifiers["Siege Max ASP"] lvl
		)
		else if ($.modifiers["Siege Max SNO"] != undefined) then
		(
			modpanel.SetCurrentObject $.modifiers["Siege Max SNO"]
			dsSetMeshSelectSubLevel $.modifiers["Siege Max SNO"] lvl
		)
	)	
	catch
	(
		MessageBox "Your preferences are set to display the Topology Dependance Warning" 
	)
)

-----------------------------------------------------------------------------------------------------
fn FetchNodeByName s = 
(
	-- Hide some of the clumsiness involved in fetching a node
	return execute ("$'"+s+"'")
)

-----------------------------------------------------------------------------------------------------
fn ValidateUniqueName r apname = (
	
	for c in r.children do (
		if not ( ValidateUniqueName c apname ) then (
			return false
		)
	)
	
	if r.name == apname then (
		return false
	)
	
	return true
	
)

-----------------------------------------------------------------------------------------------------
fn LoadReferenceObject refobjname = 
(
	local newobj = undefined
	
	local refobjmaterialname = dsUpperCase (refobjname+"_MATERIAL")
	for s in $* do
	(
		if (s.material != undefined) then
		(			
			local smatname = dsUpperCase s.material.name
						
			if (smatname == refobjmaterialname) then
			(
				newobj = snapshot s
				newobj.wirecolor = s.wirecolor
				newobj.name = refobjname
				exit
			)
		)
	)
	
	if (newobj == undefined) then
	(
		local staleobj = FetchNodeByName refobjname
		if (staleobj != undefined) then 
		(
			delete staleobj
		)

		local refobjfile = if ProductIs3dsmax()  then 
			(
				(getdir #scene) + "/Reference_Scenes/GPG_RefObjs.max" 
			)
			else
			(
				(getdir #maxroot) + "gamepacks/SiegeMAX/Scenes/Reference_Scenes/GPG_RefObjs.gmax"
			)
		
		mergeMAXfile refobjfile  #(refobjname) #deleteOldDups
		newobj = FetchNodeByName refobjname
	)
	
	return newobj
)		

-----------------------------------------------------------------------------------------------------
fn AddAttachPoint p apname = (
	
	local newobj = undefined
	
	try 
	(
	
		if p == undefined or isdeleted p then return false
		
		local objname = "AP_" + apname
		
		local toplevel = p
		
		while toplevel.parent != undefined do
		(		
			toplevel = toplevel.parent
		)
		
		if not (ValidateUniqueName toplevel objname) then (
			MessageBox ("You already have an attach point named '" + apname + "' on this object")
			return false
		)
		
		local refobjname = "__ATTACH_POINT_MARKER"
		
		newobj = LoadReferenceObject refobjname

		if (newobj == undefined) then return false
			
		MessageBox ("Creating AP_" + apname + " at " + p.name)
		
		newobj.name = objname
	
		in coordsys p newobj.rotation = eulerangles 0 0 0
		in coordsys p newobj.pos = [ 0, 0, 0 ]
		newobj.parent = p	
		
		return newobj
	)
	catch
	(
		if (p != undefined) then
		(
			format "Failed to add an attach point to %\n" p.name
		)
		if (newobj != undefined) then
		(
			delete newobj
		)
	)
	return undefined
)
	
-----------------------------------------------------------------------------------------------------
fn ReplaceAllAttachPointMarkers = (
	
	mrks = for n in $AP_* collect n
	
	for m in mrks do (
		ResetReferenceMarker m "__ATTACH_POINT_MARKER"
	)
)

-----------------------------------------------------------------------------------------------------
fn ResetReferenceMarker picked refobjname = (

	local newobj = undefined
	
	try (
	
		-- Must pass in the name of the reference object that
		-- you want to use as a replacement
		--   Example:
		--      ResetReferenceMarker $ "__ATTACH_POINT_MARKER"
		
		if picked == undefined or isdeleted picked then return false
		
		newobj = LoadReferenceObject refobjname
				
		if (newobj == undefined) then return false
		
		in coordsys picked newobj.pos = [ 0, 0, 0 ]
		in coordsys picked newobj.rotation = eulerangles 0 0 0
		newobj.name = picked.name
		newobj.parent = picked.parent
		for c in picked.children do
		(
			c.parent = newobj
		)
		delete picked
		return newobj	
	)
	catch
	(
		if (picked != undefined) then
		(
			format "Failed to replace a reference marker for %\n" picked
		)
		else
		(
			format "Failed to replace a reference marker for %\n" picked
		)
		if (newobj != undefined) then
		(
			delete newobj
		)
		return undefined	
	)
)
	
-----------------------------------------------------------------------------------------------------
fn FetchGrip itm = (

	if (itm == $bip01) then (
	  ErrorMsg "Bip01 is not a valid item"
	  return undefined
	)
	
	if (itm == $skinmesh) then (
	  ErrorMsg "SKINMESH is not a valid item"
	  return undefined
	)
		
	if (findstring itm.name " ") != undefined then (
	  ErrorMsg ("The name of the item:\n\n" + itm.name +"\n\ncontains a space. Items names must not have spaces, please use an underscore")
	  return undefined
	)
		
	if (findstring itm.name "grip_") == 1 then (
		grip_node = itm
	) else (
	
		grip_node = FetchNodeByName ("grip_"+itm.name)
		
		if grip_node == undefined then (
			blurb = "There is no grip_" + itm.name + " in the scene"
			MessageBox blurb title:"Bad News" 
			return undefined
		)
		
	)
	
	return grip_node
)
		
-----------------------------------------------------------------------------------------------------
fn GripOnItem grip = (
	
	if selection.count != 1 then (
		MessageBox "You need exactly one item selected" title:"BadNews"
		return false
	)
	
	itm = selection[1]

	item_grip = FetchGrip(itm)	
	
	if item_grip == undefined then (
		return false
	)

	undo on (
		in coordsys item_grip grip.rotation = eulerangles 0 0 0
		in coordsys item_grip grip.pos = [ 0, 0, 0 ]
	)
	
	
)

-----------------------------------------------------------------------------------------------------
fn ItemOnGrip grip = (

	if selection.count != 1 then (
		MessageBox "You need exactly one item selected" title:"BadNews"
		return false
	)
		
	itm = selection[1]

	item_grip = FetchGrip(itm)
	
	if item_grip == undefined then (
		return false
	)
	
	undo on (
		in coordsys grip item_grip.rotation = eulerangles 0 0 0
		in coordsys grip item_grip.pos = [ 0, 0, 0 ]
	)

)


-----------------------------------------------------------------------------------------------------
rollout ItemRollout "Item Tool Kit" width:162 height:150
(

	label L1 "Item Tweaks" pos:[43,7] width:76 height:16
	button add_grip_but "Add Grip to Item" pos:[26,28] width:111 height:24
	button add_root_but "Add Dummy Root to Item" pos:[-1,57] width:164 height:24
	button add_attach_but "Add Attach Point to Item" pos:[3,86] width:156 height:24
	combobox attach_name "" pos:[12,116] width:136 height:5 items:#("light", "tip", "notch", "trace01", "trace02")
		
-----------------------------------------------------------------------------------------------------
	
	on add_grip_but pressed do
	(
		undo on (
			
				if selection.count != 1 then (
					MessageBox "You need exactly one item selected" title:"BadNews"
					return false
				)
				
				local itm = selection[1]
				local top_level = itm
				
				if (findstring top_level.name "grip") == 1 then (
					MessageBox "The item you've selected is already named 'grip'" title:"BadNews"
					return false
				)
				
				while (top_level.parent != undefined) do (
				
					top_level = top_level.parent
					
					if (findstring top_level.name "grip") == 1 then (
						MessageBox "The item is already has a 'grip'" title:"BadNews"
						return false
					)
					
				)
				
				local grip = LoadReferenceObject "__GRIP_MARKER"
					
				if (grip == undefined) then return false
					
				grip.name = ("grip_"+itm.name)
				
				grip.position = itm.position
				
				grip.rotation.x_rotation = itm.rotation.x_rotation 
				grip.rotation.y_rotation = itm.rotation.y_rotation 
				grip.rotation.z_rotation = itm.rotation.z_rotation 
				
				top_level.parent = grip
			
			)
	)
	on add_root_but pressed do
	(
		undo on (
			
				if selection.count != 1 then (
					MessageBox "You need exactly one item selected" title:"BadNews"
					return false
				)
				
				local itm = selection[1]
				local root_level = FetchNodeByName ("dummyroot_"+itm.name)
				
				if (root_level != undefined) then (
					MessageBox "Selected item already has a root" title:"BadNews"
					return false
				)
				
				local top_level = itm
				
				while (top_level.parent != undefined) do (
				
					top_level = top_level.parent
			
				)
				
				local dummyroot= LoadReferenceObject "__DUMMYROOT"
					
				if (dummyroot== undefined) then return false
					
				dummyroot.name = ("dummyroot_"+itm.name)
				
				dummyroot.position = itm.position
				dummyroot.position.z = 0
						
				top_level.parent = dummyroot
		
			)
	)
	on add_attach_but pressed do
	(
		undo on
		(
			
				if selection.count != 1 then (
					MessageBox "You need exactly one item selected" title:"BadNews"
					return false
				)
				
				itm = selection[1]
				
				local newap = AddAttachPoint itm attach_name.text
				
				add_attach_but.enabled=false
				
		)
	)
	on attach_name selected value do
	(
			add_attach_but.enabled=true
	)
	on attach_name entered value do
	(
			add_attach_but.enabled=true
	)
)

-----------------------------------------------------------------------------------------------------
fn CloseHelpTools  = (
	if (helptools != undefined and ( classof helptools == RolloutFloater ) ) then 
	(
		removeRollout ItemRollout helptools 
		closeRolloutFloater helptools 
	)
)

-----------------------------------------------------------------------------------------------------
fn OpenHelpTools = (

	CloseHelpTools()
	helptools = newRolloutFloater "Helpers"  180 300 80 40
	addrollout ItemRollout helptools 
)


