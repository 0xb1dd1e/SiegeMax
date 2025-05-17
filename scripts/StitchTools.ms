----------------------------------------------------------------------------------------
fn ReadTaggedStitchSets pMesh = (

	try (
	
		local taggedvertsets= #()
		for i = 1 to pMesh.'Siege Max ASP'.StitchTagList.count do 
		(
			append taggedvertsets #(pMesh.'Siege Max ASP'.StitchTagList[i],#())
		)
		
		local vpos = 1
		for tag = 1 to taggedvertsets.count do 
		(
			local vcount = pMesh.'Siege Max ASP'.StitchVertList[vpos]
			vpos += 1
			for j = 1 to vcount do
			(
				append taggedvertsets[tag][2] pMesh.'Siege Max ASP'.StitchVertList[vpos]
				vpos += 1
			)
		)
		return taggedvertsets
	)
	catch
	(
		print "Error reading tagged stitch sets from Siege Max ASP modifier"
	)
	return #()
)

----------------------------------------------------------------------------------------
fn WriteTaggedStitchSets pMesh stitchsets = (

	try (
		
		local tlist = #()
		local vlist = #()
	
		for sset = 1 to stitchsets.count do 
		(
			if (stitchsets[sset][2].count > 0) then
			(
				append tlist stitchsets[sset][1]
				append vlist stitchsets[sset][2].count
				vlist = join vlist stitchsets[sset][2]
			)
		)
		
		pMesh.'Siege Max ASP'.StitchTagList = tlist
		pMesh.'Siege Max ASP'.StitchVertList = vlist 
		
		return true
	)
	catch
	(
		print "Error writing tagged stitch sets to Siege Max ASP modifier"
	)
	return false
)

----------------------------------------------------------------------------------------
fn GetTaggedStitchVerts pMesh tag = (

	stitchsets = ReadTaggedStitchSets pMesh 
	
	for sset in stitchsets do 
	(
		if sset[1] == tag then return sset[2]
	)
	return #()
)

----------------------------------------------------------------------------------------
fn SetTaggedStitchVerts pMesh tag verts = (


	if (tag.count != 4) then
	(
		print "Illegal stitch set tag name % (must be a FourCC)" tag
		return false
	)
	
	stitchsets = ReadTaggedStitchSets pMesh 
	
	for sset = 1 to stitchsets.count do 
	(
		if stitchsets[sset][1] == tag then 
		(
			-- We are swapping out an existing set of verts
			stitchsets[sset][2] = verts
			WriteTaggedStitchSets pMesh stitchsets
			return true
		)
	)
	-- Tag wasn't found, so this is a new set of verts
	append stitchsets #(tag,verts)
	WriteTaggedStitchSets pMesh stitchsets 
	return true
	
)

--**************************************************************


global necktoolfloater = undefined

rollout StitchNeckTools "Neck Stitching"  (

	local NeckMesh
	local NeckVerts = #()
	local NeckMarkers = #()
	local NeckTextMarkers = #()
	
	local NeckChangeHandler 
	local NeckDeleteHandler
	
	local PrevTaskMode 
	local PrevModObject
	local PrevSubLevel
	local PrevMeshSubLevel
	
	checkbutton AddNeckVerts "Add Neck verts" \
		tooltip:"Mark selected neck verts with red spheres" \
		highlightcolor:(color 150 220 150)
	checkbutton DelNeckVerts "Delete Neck verts" \
		tooltip:"Unmark selected neck verts with red spheres" \
		 highlightcolor:(color 150 220 150)
	
	button ResetNeckVerts	"Reset the Neck verts"
	
	label NeckCount "0 Neck Verts"
	
	button SelectNeckVerts	"Add Mesh_Select with verts"
	
	----------------------------------
	
	fn NeckCleanup = (
	
		try (deleteChangeHandler NeckChangeHandler) catch ()
		try (deleteChangeHandler NeckDeleteHandler) catch ()
		try (delete NeckMarkers) catch ()
		try (delete NeckTextMarkers) catch ()
		
		NeckChangeHandler = undefined
		NeckDeleteHandler = undefined
		NeckMarkers		  = undefined
		NeckTextMarkers		  = undefined
		
		try (
			delete $'__NeckText_*'
			delete $'__NeckVert_*'
		)
		catch ()
		
		try (
			NeckCount.text = "0 Neck Verts"
			AddNeckVerts.checked = false
			AddNeckVerts.enabled = true
			DelNeckVerts.checked = false 
			DelNeckVerts.enabled = false 
			ResetNeckVerts.enabled = true
			SelectNeckVerts.enabled = false
			NeckMesh = undefined
		)
		catch()
		
		closerolloutfloater necktoolfloater 
	)
	
	----------------------------------
	fn LoadNeckVerts = (
	
		local LoadMesh = $
		
		if LoadMesh == undefined then (
			MessageBox "No mesh selected"
			return false
		)
		
		try (
		
			NeckVerts = GetTaggedStitchVerts LoadMesh "NECK"
			
			NeckMesh = LoadMesh 
			for v = 1 to NeckVerts.count do (
				local vpos = getvert NeckMesh NeckVerts[v]
				b = sphere pos:vpos radius:.0088m wirecolor:[255,0,0] name:("__NeckVert_"+v as string)
				b.parent = NeckMesh
				append NeckMarkers b
				t = text text:(v as string) position:(b.pos+[0,0,-35]) size:30 name:("__NeckText_"+v as string)
				coordsys local rotate t 90 [1,0,0]
				t.wirecolor = [255,0,0]
				t.parent = b
				append NeckTextMarkers t
			)
			
			try (deleteChangeHandler NeckDeleteHandler) catch ()
			NeckDeleteHandler = when #(NeckMesh) deleted do (
				NeckCleanup()
			)
		) 
		
		catch (
			NeckMesh = undefined
			NeckVerts = #()
			NeckMarkers = #()
			NeckTextMarkers = #()
		)
		
		if NeckVerts.count > 0 then (
			DelNeckVerts.Enabled = true
			SelectNeckVerts.enabled = true
		) else (
			DelNeckVerts.Enabled = false
			SelectNeckVerts.enabled = false
		)
		
		NeckCount.text = NeckVerts.count as string + " Neck Verts"
		
		if (NeckMesh != undefined) then (
			NeckChangeHandler = when select NeckMesh changes id:#NCH do (
				if (not NeckMesh.isSelected) then NeckCleanup()
			)
		)
		
	)
	
	----------------------------------
	
	on StitchNeckTools open do (
		NeckMesh = $
		NeckVerts = #()
		NeckMarkers = #()
		NeckTextMarkers = #()
		PrevTaskMode = undefined
		PrevModObject = undefined
		PrevSubLevel = undefined
		NeckCount.text = "0 Neck Verts"
		AddNeckVerts.checked = false
		AddNeckVerts.enabled = true
		DelNeckVerts.checked = false 
		DelNeckVerts.enabled = false 
		ResetNeckVerts.enabled = true
		SelectNeckVerts.enabled = false
		if (NeckMesh!=undefined) then LoadNeckVerts()

	)
	
	----------------------------------
	
	on StitchNeckTools oktoclose do (

		local differs = false
		
		if (NeckMesh == undefined) then return true
		
		SetTaggedStitchVerts NeckMesh "NECK" NeckVerts
				
		return true
	)
	
	----------------------------------
	
	on StitchNeckTools close do (
	
		try (deleteChangeHandler NeckChangeHandler) catch ()
		try (deleteChangeHandler NeckDeleteHandler) catch ()
		try (delete NeckMarkers) catch ()
		try (delete NeckTextMarkers) catch ()
		
		NeckChangeHandler = undefined
		NeckDeleteHandler = undefined
		NeckMarkers		  = undefined
		NeckTextMarkers	  = undefined
		
		try (
			delete $'__NeckText_*'
			delete $'__NeckVert_*'
		) catch ()
		
		try (

			if (PrevTaskMode != undefined and PrevModObject != undefined) then (
			
				if (modPanel.getCurrentObject() != PrevModObject) then (
					if (PrevMeshSubLevel != undefined and subObjectLevel != PrevMeshSubLevel) then subObjectLevel = PrevMeshSubLevel
					modPanel.setCurrentObject PrevModObject
				)
				
				if (subObjectLevel != PrevSubLevel) then subObjectLevel = PrevSubLevel
				if PrevTaskMode != getCommandPanelTaskMode() then setCommandPanelTaskMode mode:PrevTaskMode
				PrevTaskMode = undefined
			)
		) catch ()
	)
	
	----------------------------------
	on SelectNeckVerts pressed do
	(	
		if NeckMesh == undefined then 
		(
			NeckMesh = $
			if NeckMesh == undefined then 
			(
				MessageBox "No mesh selected"
				return false
			) 
		)
		
		try
		(
			disableSceneRedraw() 

			neckverts = GetTaggedStitchVerts NeckMesh "NECK"	
			max modify mode
			modpanel.setcurrentobject NeckMesh.baseobject
			NeckMesh.selectedverts = neckverts
			selmod = MeshSelect()
			modpanel.AddModToSelection selmod
			modpanel.setcurrentobject selmod
			subobjectlevel = 1
			enableSceneRedraw() 

		)
		catch
		(
			print "Unexpected problem with SelectNeckVerts"
		)
	)
	
	----------------------------------
	
	on ResetNeckVerts pressed do (
	
		if  not (dsQueryBox "Sure you want to reset your NECK verts?" default:false ) then (
			return false
		)
		
		try (deleteChangeHandler NeckChangeHandler) catch ()
		try (deleteChangeHandler NeckDeleteHandler) catch ()
		
		NeckMesh = $
		
		try (delete NeckMarkers) catch ()
		try (delete NeckTextMarkers) catch ()
		delete $'__NeckText_*'
		delete $'__NeckVert_*'
		
		SetTaggedStitchVerts NeckMesh "NECK" #()
		
		NeckMesh = undefined
		NeckVerts = #()
		NeckMarkers = #()
		NeckTextMarkers = #()
		NeckCount.text = NeckVerts.count as string + " Neck Verts"
		
		DelNeckVerts.Enabled = false
		SelectNeckVerts.enabled = false
		
	)
	
	----------------------------------

	on AddNeckVerts changed ischecked do (
	
		if NeckMesh == undefined then (
			NeckMesh = $
			if NeckMesh == undefined then (
				MessageBox "No mesh selected"
				AddNeckVerts.checked = false
				return false
			) else (
				try (deleteChangeHandler NeckDeleteHandler) catch ()
				NeckDeleteHandler = when #(NeckMesh) deleted do (
					NeckCleanup()
				)
			)
		)
	
		if not ischecked then (
		
			try (deleteChangeHandler NeckChangeHandler) catch ()
			DelNeckVerts.Enabled = true
			ResetNeckVerts.Enabled = true
			SelectNeckVerts.Enabled = true
			
			if (modPanel.getCurrentObject() != PrevModObject) then (
				if (subObjectLevel != PrevMeshSubLevel) then subObjectLevel = PrevMeshSubLevel
				modPanel.setCurrentObject PrevModObject
			)
			if (subObjectLevel != PrevSubLevel) then subObjectLevel = PrevSubLevel
			if PrevTaskMode != getCommandPanelTaskMode() then setCommandPanelTaskMode mode:PrevTaskMode
			PrevTaskMode = undefined
			
			for v = 1 to NeckVerts.count do (
				try (
					local vpos = getvert NeckMesh NeckVerts[v]
					NeckMarkers[v].pos = vpos;
				) catch ()
			)

	
		) else (
		
			PrevTaskMode = getCommandPanelTaskMode()
			if PrevTaskMode != #modify  then (
				setCommandPanelTaskMode mode:#modify
			)
			try (
				PrevModObject = modPanel.getCurrentObject()
				PrevSubLevel = subObjectLevel 
				if (modPanel.getCurrentObject() != NeckMesh.baseObject) then modPanel.setCurrentObject NeckMesh.baseObject 
				PrevMeshSubLevel = subObjectLevel 
				if (subObjectLevel != 1) then (
					subObjectLevel = 1
				)
			)
			catch(
				MessageBox "Base object isn't an editable mesh/patch"
				AddNeckVerts.checked = false
				return false
			)
			
			SetTaggedStitchVerts NeckMesh "NECK" NeckVerts
			
			for v = 1 to NeckVerts.count do (
				try (
					local vpos = getvert NeckMesh NeckVerts[v]
					NeckMarkers[v].pos = vpos;
				) catch()
			)
		
			max select
			setvertselection NeckMesh #()
			DelNeckVerts.Enabled = false
			ResetNeckVerts.Enabled = false
			SelectNeckVerts.Enabled = false
			
			try (deleteChangeHandler NeckChangeHandler) catch ()
			NeckChangeHandler = when select NeckMesh changes id:#NCH do (
				
				if NeckMesh.isSelected == false then (
					NeckCleanup()
				) else (
					local SelVerts 
					try (
					
						SelVerts = for i in (getvertselection NeckMesh) collect i
					
						if SelVerts.count == 1 then (
						
							local v = SelVerts[1]
							
							if (finditem NeckVerts v) == 0 then (
							
								local vpos = getvert NeckMesh v
								append NeckVerts v
								
								b = sphere pos:vpos radius:.0088m wirecolor:[255,0,0] name:("__NeckVert_"+NeckVerts.count as string)
								b.parent = NeckMesh
								
								append NeckMarkers b
								
								t = text text:(NeckVerts.count as string) position:(b.pos+[0,0,-35]) size:30 name:("__NeckText_"+NeckVerts.count as string)
								coordsys local rotate t 90 [1,0,0]
								t.wirecolor = [255,0,0]
								t.parent = b
								append NeckTextMarkers t
								
								NeckCount.text = NeckVerts.count as string + " Neck Verts"
							)
							completeredraw()
						)
					)
					catch ()
				)
			)
		)
	
		
	)
	----------------------------------
	
	on DelNeckVerts changed ischecked do (
	
		if NeckMesh == undefined then (
			MessageBox "No mesh selected"
			DelNeckVerts.checked = false
			return false
		)
		
		if not ischecked then (
		
			try (deleteChangeHandler NeckChangeHandler) catch ()
			
			AddNeckVerts.Enabled = true
			ResetNeckVerts.Enabled = true
			
			if NeckVerts.count > 0 then (
				DelNeckVerts.Enabled = true
				SelectNeckVerts.Enabled = true
			) else (
				DelNeckVerts.Enabled = false
				SelectNeckVerts.Enabled = false
			)
	
			if (modPanel.getCurrentObject() != PrevModObject) then (
				if (PrevMeshSubLevel != undefined and subObjectLevel != PrevMeshSubLevel) then subObjectLevel = PrevMeshSubLevel
				modPanel.setCurrentObject PrevModObject
			)
			if (subObjectLevel != PrevSubLevel) then subObjectLevel = PrevSubLevel
			if PrevTaskMode != getCommandPanelTaskMode() then setCommandPanelTaskMode mode:PrevTaskMode
			PrevTaskMode = undefined

			for v = 1 to NeckVerts.count do (
				try (
					local vpos = getvert NeckMesh NeckVerts[v]
					NeckMarkers[v].pos = vpos;
				) catch ()
			)

		) else (
		
			PrevTaskMode = getCommandPanelTaskMode()
			if PrevTaskMode != #modify  then (
				setCommandPanelTaskMode mode:#modify
			)
			try (
				PrevModObject = modPanel.getCurrentObject()
				PrevSubLevel = subObjectLevel 
				if (modPanel.getCurrentObject() != NeckMesh.baseObject) then modPanel.setCurrentObject NeckMesh.baseObject 
				PrevMeshSubLevel = subObjectLevel 
				if (subObjectLevel != 1) then subObjectLevel = 1
			)
			catch(
				MessageBox "Base object isn't an editable mesh"
				AddNeckVerts.checked = false
				return false
			)
		
			max select
			setvertselection NeckMesh #()
			AddNeckVerts.Enabled = false
			ResetNeckVerts.Enabled = false

			for v = 1 to NeckVerts.count do (
				try (
					local vpos = getvert NeckMesh NeckVerts[v]
					NeckMarkers[v].pos = vpos;
				) catch ()
			)
			
			SetTaggedStitchVerts NeckMesh "NECK" NeckVerts
		
			try (deleteChangeHandler NeckChangeHandler) catch ()
			NeckChangeHandler = when select NeckMesh changes id:#NCH do (
				
				if NeckMesh.isSelected == false then (
					NeckCleanup()
				) else (
				
				local SelVerts 
					try (
					
						SelVerts = for i in (getvertselection NeckMesh) collect i
					
						if SelVerts.count == 1 then (
						
							local v = SelVerts[1]
							local pos = (finditem NeckVerts v)
							
							if pos != 0 then (
							
								deleteitem NeckVerts pos
								
								try (delete NeckMarkers) catch ()
								try (delete NeckTextMarkers) catch ()
								
								delete $'__NeckText_*'
								delete $'__NeckVert_*'
								NeckMarkers = #()
								NeckTextMarkers = #()
								
								for v = 1 to NeckVerts.count do (
									local vpos = getvert NeckMesh NeckVerts[v]
									b = sphere pos:vpos radius:.0088m wirecolor:[255,0,0] name:("__NeckVert_"+v as string)
									b.parent = NeckMesh
									append NeckMarkers b
									t = text text:(v as string) position:(b.pos+[0,0,-35]) size:30 name:("__NeckText_"+v as string)
									coordsys local rotate t 90 [1,0,0]
									t.wirecolor = [255,0,0]
									t.parent = b
									append NeckTextMarkers t
								)
								
								NeckCount.text = NeckVerts.count as string + " Neck Verts"
								
								completeredraw()
							)
						)
					)
					catch ()
				)
			)
		)
		
	)
		

)

fn OpenNeckToolkit = 
(
	if necktoolfloater != undefined and (classof necktoolfloater) == RolloutFloater then
	(
		closerolloutfloater necktoolfloater 
	) 
	necktoolfloater = newRolloutFloater "Stitch Tools"  180 237 800 100
	addrollout StitchNeckTools necktoolfloater 
)
