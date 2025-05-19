----------------------------------------------------------------------------------------
--
-- SNO Toolkit
--
------------------------------------------------------------------------------------------

GLOBAL gSNOToolsFloater = undefined
GLOBAL gSiegeNodeRenderMode = undefined
GLOBAL gShowAcclimatedDoorDirection = false
GLOBAL gChangeList = #()
GLOBAL fltrSNODoors = undefined
GLOBAL fltrSNOTools = undefined

struct SiegeDoor (verts,edges)

----------------------------------------------------------------------------------------
fn ArraysAreEqual a b = 
(
	if (classof a) != array then return false
	if (classof b) != array then return false
	if a.count != b.count then return false
	for i = 1 to a.count do 
	(
		if a[i] != b[i] then return false
	)
	return true
)

----------------------------------------------------------------------------------------
fn FlipDoor obj backwardsDoor = 
(			
	local tempverts = #()
	for t in backwardsDoor.verts do
	(
		insertItem t tempverts 1
	)
	
	-- Check for existing door
	if obj.'Siege Max SNO'.tDoorList.count > 1 then
	(
		for i = 1 to obj.'Siege Max SNO'.tDoorList.count do
		(
			if (ArraysAreEqual obj.'Siege Max SNO'.tDoorList[i].verts tempverts) then
			(
				MessageBox  ("Error: Flipping door would create a duplicate of door number " + (i as string))
				return false
			)
		)		
	)
	
	backwardsDoor.verts = tempverts
	
	local tempedges = backwardsDoor.edges
	backwardsDoor.edges = #()
	for t in tempedges do
	(
		insertItem t backwardsDoor.edges 1
	)
	
	return true
)

----------------------------------------------------------------------------------------
fn RoundFloat n m =
(
	-- round the number n to a maximum precision of m

	-- note: some of these calculations might appear long-winded,
	--       but only to work around very bad precision errors in max
	local mrecip = 1 / m
	local nn = n * mrecip
	local r = mod nn 1

	if ( nn > 0 ) then
	(
		if ( r < 0.5 ) then
			nn = floor nn
		else
			nn = ceil nn
	)
	else
	(
		if ( r > -0.5 ) then
			nn = ceil nn
		else
			nn = floor nn
	)

	return ( nn * m )
)

----------------------------------------------------------------------------------------
fn RoundVector v m =
(
	local x = RoundFloat v.x m
	local y = RoundFloat v.y m
	local z = RoundFloat v.z m
	
	return (point3 x y z )
)

----------------------------------------------------------------------------------------
fn CalcDoorOutDir obj selDoor canFlipBackwardsDoor forceDir ReportLoopyDoors:false = 
(

	if ( forceDir != 7 ) then
	(
		case forceDir of
		(
			1: return [1,0,0]
			2: return [0,1,0]
			3: return [0,0,1]
			4: return [-1,0,0]
			5: return [0,-1,0]
			6: return [0,0,-1]
		)
	)

	local pointA = getvert obj selDoor.verts[1]
	local pointB = getvert obj selDoor.verts[selDoor.verts.count]

	-- we gotta round this value right here, due to precision error, to keep this door
	-- the exact opposite of the door on the other node
	local doorBase = RoundVector (pointB-pointA) 0.001
	
	if ( length doorBase ) < 0.001 then
	(
		if (ReportLoopyDoors) then (
			MessageBox "This is a poor set of door edges, the first and last verts are too close together"
		)
		return  [1, 0, 0]
	)
	
	doorBase = normalize doorBase 
	
	local doorOutDir = cross [0,0,1] doorBase
	
	if ( length doorOutDir ) > 0.001 then 
	(	
		if ( canFlipBackwardsDoor ) then
		(
			doorCenter = (pointA+pointB) * 0.5
			
			doorOutRay = doorCenter - obj.pivot
			
			if (length doorOutRay ) < 0.001 then
			(
				doorOutRay = [-doorBase.y,doorBase.x,doorBase.z]
			)
			
			if (dot DoorOutRay DoorOutDir) < 0 then
			(
				FlipDoor obj selDoor
				doorOutDir = -doorOutDir 
			)	
		)
	)
	else
	(
		-- door base is perpendicular	
		if ( dot [0,0,1] doorBase ) < 0 then
		(
			doorOutDir = [1,0,0]
		)
		else
		(
			doorOutDir = [-1,0,0]
		)
		
	)
	
	return doorOutDir
)

----------------------------------------------------------------------------------------
fn CalcDoorVisualOutDir obj selDoor canFlipBackwardsDoor forceDir ReportLoopyDoors:false =
(
	local orthoDoorOut = CalcDoorOutDir obj selDoor canFlipBackwardsDoor forceDir

	if ( forceDir != 7 ) then
		return orthoDoorOut

	if ( selDoor.verts.count < 3 ) then
		return orthoDoorOut

	local pointA = getvert obj selDoor.verts[1]
	local pointB = getvert obj selDoor.verts[(selDoor.verts.count + 1 ) / 2]
	local pointC = getvert obj selDoor.verts[selDoor.verts.count]
	
	local doorPlane = cross (pointC-pointB) (pointA-pointB)
	if ( ( length doorPlane ) < 0.01 ) then
		return orthoDoorOut
	doorPlane = normalize doorPlane
	if ( ( dot doorPlane [0,0,1] ) < 0 ) then
		doorPlane *= -1

	local doorBase = pointC-pointA
	
	if ( length doorBase ) < 0.0001 then
	(
		if (ReportLoopyDoors) then (
			MessageBox "This is a poor set of door edges, the first and last verts are too close together"
		)		
		return  [1, 0, 0]
	)
	
	doorBase = normalize doorBase
	
	local doorOutDir = cross doorPlane doorBase
	
	if ( length doorOutDir ) > 0.001 then 
	(
		if ( canFlipBackwardsDoor ) then
		(
			doorCenter = (pointA+pointC) * 0.5
			
			doorOutRay = doorCenter - obj.pivot
			
			if (length doorOutRay ) < 0.001 then
			(
				doorOutRay = [-doorBase.y,doorBase.x,doorBase.z]
			)
			
			if (dot DoorOutRay DoorOutDir) < 0 then
			(
				FlipDoor obj selDoor
				doorOutDir = -doorOutDir
			)
		)
	)
	else
	(
		-- door base is perpendicular	
		if ( dot [0,0,1] doorBase ) < 0 then
		(
			doorOutDir = [1,0,0]
		)
		else
		(
			doorOutDir = [-1,0,0]
		)
	)
	
	return doorOutDir
)

----------------------------------------------------------------------------------------
fn BuildDoorDirections node snoMod = (
	local oldDoorDirs = snoMod.DoorDirectionList
	local hasChanged = false

	snoMod.DoorEdgeList = #()
	snoMod.DoorLastEdges = #()
	
	snoMod.DoorVertList = #()
	snoMod.DoorLastVerts = #()
	
	snoMod.DoorDirectionList = #()
	snoMod.DoorDirectionListAcclimated = #()

	for i = 1 to snoMod.tDoorList.count do 
	(	
		for nde in snoMod.tDoorList[i].edges do append snoMod.DoorEdgeList nde
		append snoMod.DoorLastEdges (snoMod.DoorEdgeList.count)
		
		for ndv in snoMod.tDoorList[i].verts do append snoMod.DoorVertList ndv
		append snoMod.DoorLastVerts (snoMod.DoorVertList.count)
		
		outDir = CalcDoorOutDir node snoMod.tDoorList[i] false snoMod.DoorForcedDir[i]
		append snoMod.DoorDirectionList (Normalize outDir)
		
		outDirAcclimated = CalcDoorVisualOutDir node snoMod.tDoorList[i] false snoMod.DoorForcedDir[i]
		append snoMod.DoorDirectionListAcclimated (Normalize outDirAcclimated)
		
		if ( snoMod.DoorDirectionList[i] != oldDoorDirs[i] ) then (
			hasChanged = true
		)
	)

	return hasChanged
)

----------------------------------------------------------------------------------------
fn ExtractDoorFromSelectedEdges obj newDoor = (
	edgeList = for ei in obj.selectededges collect ei.index
	return ExtractDoorFromEdgeList obj edgeList newDoor
)

----------------------------------------------------------------------------------------
fn ExtractDoorFromEdgeList obj edgeList newDoor AllowLoopyDoors:false = (

	newDoor.verts = #()
	newDoor.edges = #()
	
	local low_v = #()
	local high_v = #()
	
	local first_vert = undefined 
	local last_vert = undefined 
	local next_vert = undefined 
	
	local search_index = undefined 
	
	local edge_bits = #{}
	
	local dupes_v = #()	
	for e in edgeList do
	(
		arry = ((meshop.getvertsusingedge obj e) as array)
		np =  point2 arry[1] arry[2]
		if (finditem dupes_v np) == 0 then
		(
			append dupes_v np
			append low_v arry[1]
			append high_v arry[2]
			append edge_bits e
		)
	)
	
	if dupes_v.count == 0 then
	(
		MessageBox  "Error: No edges selected"
		return false
	)
	
	dupes_v = #()
		
	last_vert = low_v[1]
	next_vert = high_v[1]
	
	deleteItem low_v 1
	deleteItem high_v 1

	if low_v.count == 0 then
	(
		append newDoor.verts last_vert
		append newDoor.verts next_vert
		last_vert = undefined
	)
	else
	(	
		search_index = finditem low_v next_vert
		if (search_index == 0) then
		(
			search_index = finditem high_v next_vert
			if (search_index == 0) then
			(
				local temp = last_vert
				last_vert = next_vert
				next_vert = temp	
			
				search_index = finditem low_v next_vert
				if (search_index == 0) then
				(
					search_index = finditem high_v next_vert
					if (search_index == 0) then
					(
						MessageBox "Error: Edges are not continuous, cannot extract door"
						return false
					)
				)
			)
		)
		
		append newDoor.verts last_vert
		
		last_vert = next_vert
	)
	
	while low_v.count > 0 do 
	(
		if next_vert != undefined then
		(
			search_index = finditem low_v next_vert
			if (search_index > 0) then
			(
				next_vert = high_v[search_index]
			)
			else 
			(
				search_index = finditem high_v next_vert
				if (search_index > 0) then
				(	
					next_vert = low_v[search_index]
				)
			)
			
			if (search_index > 0) then
			(
				
				append newDoor.verts last_vert
				deleteItem low_v search_index
				deleteItem high_v search_index
				
				last_vert = next_vert
			)
			else
			(
				last_vert = next_vert
				next_vert = undefined
			)
		)
		
		if next_vert == undefined then
		(		
			search_index = finditem low_v newDoor.verts[1]
			if search_index > 0 then
			(
				first_vert = high_v[search_index]
			)
			else 
			(
				search_index = finditem high_v newDoor.verts[1]
				if search_index > 0 then
				(	
					first_vert = low_v[search_index]
				)
			)
			
			if search_index > 0 then
			(
				insertItem first_vert newDoor.verts 1 
				deleteItem low_v search_index
				deleteItem high_v search_index				
			)
			else
			(
				MessageBox "Error: Edges are not continuous, cannot extract door"
				return false
			)
		)
	
	)
	
	if last_vert != undefined then
	(
		append newDoor.verts last_vert
	)	


	if newDoor.verts[1] == newDoor.verts[newDoor.verts.count] then
	(
		if (AllowLoopyDoors) then (
			format "Warning: Door edges form a closed loop"
		)
		else (
			MessageBox "Error: Door edges form a closed loop"
			return false				
		)			
	)
	local pointA = getvert obj newDoor.verts[1]
	local pointB = getvert obj newDoor.verts[newDoor.verts.count]
	local doorBase = pointB - pointA
	
	if (length doorBase) < 0.001 then
	(
		if (AllowLoopyDoors) then (
			format "Warning: The first and last verts are too close together"
		)
		else (
			MessageBox "Error: The first and last verts are too close together"
			return false				
		)
	)				
	
	for v in newDoor.verts do
	(		
		local using_edge_bits = meshop.getEdgesUsingVert obj #(v) as bitarray
		local shared_edge_bits = using_edge_bits * edge_bits
		if shared_edge_bits.numberset > 2 then
		(
			return false
		)
	)
	
	for i = 1 to (newDoor.verts.count-1) do
	(
		local e = edge_bits *(meshop.getEdgesUsingVert obj #(newDoor.verts[i]))
		e = e * (meshop.getEdgesUsingVert obj #(newDoor.verts[i+1]))
		if  not e.isEmpty  then
		(
			append newDoor.edges ((e as array)[1])
		)
	)
	
	return true
)

----------------------------------------------------------------------------------------
fn DoorAlreadyExists obj newDoor =
(
	-- Check to see if the door is already present

	if obj.'Siege Max SNO'.tDoorList.count > 0 then
	(
		for i = 1 to obj.'Siege Max SNO'.tDoorList.count do
		(
			if (ArraysAreEqual $.'Siege Max SNO'.tDoorList[i].verts newDoor.verts) then
			(
				newDoor.verts = #()
				newDoor.edges = #()
				MessageBox  ("Error: New door is a duplicate of door number " + (i as string))
				return true
			)
		)		
	)
	return false
)
	
--------------------------------------------------------------------------------
fn SelectedHasASNOModifier = 
(
	try
	(		
		return $selection[1].modifiers["Siege Max SNO"] != undefined
	)
	catch ()
	return false
)

--------------------------------------------------------------------------------
fn AllSelectedHasASNOModifier = 
(
	try
	(
		for s in $selection do
			if s.modifiers["Siege Max SNO"] == undefined then
				return false
		return true
	)
	catch ()
	return false
)

----------------------------------------------------------------------------------------
rollout fltrSNODoors "Siege Node Doors"
(
	checkbutton ckbEditDoors "Edit Doors"
	label lblNumDoors "Num Doors:" 
	label lblSelDoor "Selected Door: 1"
	slider sldSelDoor "" ticks:1 type:#integer range:[1,1,1]
	button btnAddDoor "Append New Door #1"
	button btnInsertDoor "Insert New Door #1"
	button btnDeleteDoor "Delete Door #1"
	button btnFlipDoor "Flip Door #1"
	button btnResetDoors "Delete All Doors"
	checkbox chkShowAcclimatedDoorDirections "Show Acclimated Door Directions"
	radiobuttons radForceDoorDir "Force Door Direction" labels:#("+X","+Y","+Z","-X","-Y","-Z","Default") default:7 columns:3

	fn SetSubSelectMode flg = (
		if flg then
		(
			SafeSetSubObjectLevel 2
		)
		else
		(


			-- Leave sel face mode
			SafeSetSubObjectLevel 0
		)
		completeRedraw() --completeRedrawcompleteRedraw()
	)
	
	fn SetSelectDoorEdges =
	(
	
		local edgebits = #{}
		local val = sldSelDoor.value
		
		if (val > 0) and ($.'Siege Max SNO'.DoorLastEdges != undefined) and ($.'Siege Max SNO'.DoorLastEdges.count >= val) then
		(
			local emin = if  val > 1 then ($.'Siege Max SNO'.DoorLastEdges[val-1]+1) else 1
			local emax = $.'Siege Max SNO'.DoorLastEdges[val]
			for e = emin to emax do (append edgebits $.'Siege Max SNO'.DoorEdgeList[e])
		)
		
		if subobjectlevel != 2 then
		(
			SafeSetSubObjectLevel 2
		)
		
		--$.selectededges = edgebits
		dsSetMeshSelected $.'Siege Max SNO' edgebits 2
		
	)
	
	fn RebuildDoorTables node reselect = 
	(
		local hasChanged = BuildDoorDirections node node.'Siege Max SNO'
		
		newlbl = "Num Doors: " + (node.'Siege Max SNO'.tDoorList.count as string)
		lblNumDoors.text = newlbl
		
		if (node.'Siege Max SNO'.tDoorList.count > 0) then
		(
			if (sldSelDoor.value > node.'Siege Max SNO'.tDoorList.count) then
			(
				sldSelDoor.range = [1,node.'Siege Max SNO'.tDoorList.count,node.'Siege Max SNO'.tDoorList.count]
			)
			else
			(
				sldSelDoor.range = [1,node.'Siege Max SNO'.tDoorList.count,sldSelDoor.value]
			)
			
			btnAddDoor.text = ("Append New Door #" + ((node.'Siege Max SNO'.tDoorList.count+1) as string))
			btnInsertDoor.text = ("Insert New Door #" + (sldSelDoor.value as string))
			btnDeleteDoor.text = ("Delete Door #" + (sldSelDoor.value as string))
			btnFlipDoor.text = ("Flip Door #" + (sldSelDoor.value as string))

			if ( node.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value] != undefined ) then
				radForceDoorDir.state = node.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value]
			else
				radForceDoorDir.state = 7

			lblSelDoor.text = "Selected Door: " + (sldSelDoor.value as string)
			sldSelDoor.ticks =  node.'Siege Max SNO'.tDoorList.count
		)
		else


		(
			btnAddDoor.text = "Append New Door #1"
			btnInsertDoor.text = "Insert New Door #1"
			btnDeleteDoor.text = "Delete Door #1"
			btnFlipDoor.text = "Flip Door #1"
			radForceDoorDir.state = 7

			lblSelDoor.text = "Selected Door: 1"
			sldSelDoor.range = [1,1,1]
			sldSelDoor.ticks =  1
		)

		if ( hasChanged ) then
			append gChangeList node.name

		if reselect then SetSelectDoorEdges()
		completeRedraw() --completeRedrawcompleteRedraw()
	)
		
	fn SetEnabled flg =
	(
		lblNumDoors.enabled = flg 
		lblSelDoor.enabled = flg 
		sldSelDoor.enabled = flg 
		btnAddDoor.enabled = flg 
		btnInsertDoor.enabled = flg 	
		btnDeleteDoor.enabled = flg 	
		btnFlipDoor.enabled = flg 	
		btnResetDoors.enabled = flg 
		radForceDoorDir.enabled = flg
		if flg then 
		(
			fltrSNOTools.SetPartiallyEnabled()
		)
		else
		(
			ckbEditDoors.enabled = false
		)
	)
	
	fn SetPartiallyEnabled =
	(
		ckbEditDoors.enabled = true
		ckbEditDoors.checked = false
		
		sldSelDoor.enabled = false 		
		lblNumDoors.enabled = false 
		lblSelDoor.enabled = false 
		btnAddDoor.enabled = false 
		btnInsertDoor.enabled = false 	
		btnDeleteDoor.enabled = false 	
		btnFlipDoor.enabled = false 	
		btnResetDoors.enabled = false 
		radForceDoorDir.enabled = false
		RebuildDoorTables $ false
	)


	on fltrSNODoors open do
	(
		newlbl = "Num Doors: " + ($.'Siege Max SNO'.DoorLastEdges.count as string)
		lblNumDoors.text = newlbl
		sldSelDoor.range = [1,$.'Siege Max SNO'.tDoorList.count,1]
		if ($.'Siege Max SNO'.tDoorList.count > 0) then
		(
			sldSelDoor.ticks =  $.'Siege Max SNO'.tDoorList.count
		)
		else
		(
			sldSelDoor.ticks = 1
		)
		btnAddDoor.text = ("Append New Door #" + (($.'Siege Max SNO'.tDoorList.count+1) as string))
		btnInsertDoor.text = ("Insert New Door #" + (sldSelDoor.value as string))
		btnDeleteDoor.text = ("Delete Door #" + (sldSelDoor.value as string))
		btnFlipDoor.text = ("Flip Door #" + (sldSelDoor.value as string))
		chkShowAcclimatedDoorDirections.checked = gShowAcclimatedDoorDirection
		if ( $.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value] != undefined ) then
			radForceDoorDir.state = $.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value]
		else
			radForceDoorDir.state = 7
	)
	
	on btnAddDoor pressed do
	(	
		newDoor = SiegeDoor #() #()
			
		local doorok = ExtractDoorFromSelectedEdges $ newDoor
			
		if doorok then
		(
			CalcDoorOutDir $ newDoor true 7
			CalcDoorVisualOutDir $ newDoor true 7
			
			if not (DoorAlreadyExists $ newDoor) then
			(			
				if ($.'Siege Max SNO'.tDoorList == undefined) or ($.'Siege Max SNO'.tDoorList.count == 0) then
				(
					$.'Siege Max SNO'.tDoorList = #(newDoor)
				)
				else
				(	
					append $.'Siege Max SNO'.tDoorList newDoor 
				)
				
				sldSelDoor.value = $.'Siege Max SNO'.tDoorList.count
				RebuildDoorTables $ true
				
				-- deselect edges after we've finish adding the door
				setEdgeSelection $ #{}
				completeRedraw()
			)
		)
	)
	
	on btnInsertDoor pressed do
	(	
		local newDoor = SiegeDoor #() #()
			
		local doorok = ExtractDoorFromSelectedEdges $ newDoor
		
		if doorok then
		(
			format "Door Out: %\n" ( CalcDoorOutDir $ newDoor true 7 )
			CalcDoorVisualOutDir $ newDoor true 7
			
			if not (DoorAlreadyExists $ newDoor) then
			(			
				local val = sldSelDoor.value
				
				if ($.'Siege Max SNO'.tDoorList == undefined) or ($.'Siege Max SNO'.tDoorList.count == 0) then
				(
					$.'Siege Max SNO'.tDoorList = #(newDoor)
				)
				else
				(					
					insertItem newDoor $.'Siege Max SNO'.tDoorList val		
				)			
				
				RebuildDoorTables $ true

				-- deselect edges after we've finish adding the door
				setEdgeSelection $ #{}
				completeRedraw()
			)
		)
	)
	
	on btnDeleteDoor pressed do
	(
		local val = sldSelDoor.value
		
		if (val > 0) and (val <= $.'Siege Max SNO'.tDoorList.count) then
		(
			deleteItem $.'Siege Max SNO'.tDoorList val
			RebuildDoorTables $ true
		)
	)
	
	on btnFlipDoor pressed do
	(
		local val = sldSelDoor.value
		
		if (val > 0) and (val <= $.'Siege Max SNO'.tDoorList.count) then
		(
			FlipDoor $ $.'Siege Max SNO'.tDoorList[val]
			RebuildDoorTables $ true
		)
	)
	
	on btnResetDoors pressed do
	(	
		local ok = dsQueryBox "Are you sure you want to remove all the doors?" default:false
		if (ok) then 
		(
			$.'Siege Max SNO'.tDoorList = #()		
			RebuildDoorTables $ true
		)
	)
	
	on ckbEditDoors changed state do
	(
		if (state) then
		(
			SetEnabled true
			if (subobjectlevel != 2) then
			(
				SetSubSelectMode true
			)
		)
		else
		(
			SetPartiallyEnabled()
			SetSubSelectMode false
		)
	)
	
	on sldSelDoor changed val do
	(
		if $.'Siege Max SNO'.tDoorList.count != 0 then 
		(
			lblSelDoor.text = "Selected Door: " + (sldSelDoor.value as string)
			btnInsertDoor.text = ("Insert New Door #" + (sldSelDoor.value as string))
			btnDeleteDoor.text = ("Delete Door #" + (sldSelDoor.value as string))
			btnFlipDoor.text = ("Flip Door #" + (sldSelDoor.value as string))

			local forcedDoorDir = $.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value]
			if ( forcedDoorDir != undefined and forcedDoorDir >= 1 and forcedDoorDir <= 6 ) then
				radForceDoorDir.state = $.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value]
			else
				radForceDoorDir.state = 7

			SetSelectDoorEdges()
	
			--completeRedraw()
		)
	)
	
	on chkShowAcclimatedDoorDirections changed val do
	(
		gShowAcclimatedDoorDirection = val
		completeRedraw()
	)

	on radForceDoorDir changed val do
	(
		$.'Siege Max SNO'.DoorForcedDir[sldSelDoor.value] = val
		RebuildDoorTables $ true
	)
)

-----------------------------------------------------------------------------------------------------
fn ResetAndRoundoffSNO n =
(
	format "Cleaning up %\n" n.name

	try
	(		
		if not SelectedHasASNOModifier() then 
		(
			max modify mode 
			addmodifier n (SNOModDef())
		)
		
		if (n.modifiers.count != 1) then
		(
			MessageBox "Can't cleanup a SNO when other modifiers are on the stack\n\nCollapse or delete other modifiers and try again"
			return false
		)
		if (classof n) != Editable_Mesh then
		(
			MessageBox ("Can't apply cleanup function. Object is class is " + ((classof n) as string) +"\n\nYou must convert this object to an Editable_Mesh (or clean up by hand)")	
		)
	)
	catch 
	(
		return false
	)

	local hasChanged = false

	local rounder = 10.0	 --  10 mm (1 centimetre)
	
	local allverts = #{1..n.numverts}
	
	local roundoffverts = allverts 
	if (n.'Siege Max SNO'.DoNotRoundVertList.count > 0) then
	(
		for dnr in n.'Siege Max SNO'.DoNotRoundVertList do roundoffverts[dnr] = false
	)
	
	-- Temporarily remove the TERRAIN modifier so that we can modify the underlying Editable_Mesh
	
	local oldmod = (n.'Siege Max SNO')
	
	local tFloorBits = oldmod.tFloorBits
	local tWaterBits = oldmod.tWaterBits
	local tIgnoredBits = oldmod.tIgnoredBits
	local tLockedNormBits = oldmod.tLockedNormBits
   	local tDoNotRoundBits = oldmod.tDoNotRoundBits

	local tDoorList = oldmod.tDoorList
	local tSelectedDoor = oldmod.tSelectedDoor
		
	local DoorEdgeList = oldmod.DoorEdgeList
	local DoorLastEdges = oldmod.DoorLastEdges
	local DoorVertList = oldmod.DoorVertList
	local DoorLastVerts = oldmod.DoorLastVerts
		
	local DoorDirectionList = oldmod.DoorDirectionList
	local DoorDirectionListAcclimated = oldmod.DoorDirectionListAcclimated
	
	local FloorFaceList = oldmod.FloorFaceList
	local WaterFaceList = oldmod.WaterFaceList
	local IgnoredFaceList = oldmod.IgnoredFaceList
	local LockedNormVertList = oldmod.LockedNormVertList
	local DoNotRoundVertList = oldmod.DoNotRoundVertList
			
	deletemodifier n oldmod 	
	
	try
	(
		for i in roundoffverts do in coordsys local
		(
			v = getvert n i
			p = v / rounder
			p.x = floor (p.x+0.5)
			p.y = floor (p.y+0.5)
			p.z = floor (p.z+0.5)
			p = p * rounder
			setvert n i p

			if ( v != p ) then
				hasChanged = true
		)

		p = n.objectoffsetpos / rounder
		p.x = floor (p.x+0.5)
		p.y = floor (p.y+0.5)
		p.z = floor (p.z+0.5)
		p = p * rounder
		
		diff = n.objectoffsetpos - p
		
		if diff != [0,0,0] then
		(
			format "Reset % to remove OFFSETPOS of %\n" n.name diff
	
			for i in allverts do 
			(
				v = getvert n i
				v += diff
				setvert n i v
			)
			n.objectoffsetpos = p
			
			hasChanged = true
		)
		
		p = n.pos / rounder
		p.x = floor (p.x+0.5)
		p.y = floor (p.y+0.5)
		p.z = floor (p.z+0.5)
		p = p * rounder
		
		diff = n.pos - p
		
		if (diff != [0,0,0]) then 
		(
			format "Roundoff % to round out POS of %\n" n.name diff

			for i in allverts do in coordsys local
			(
				v = getvert n i
				v += diff
				setvert n i v
			)
			n.pos = p
			
			hasChanged = true
		)

		completeRedraw() --completeRedraw()
		
		if ( hasChanged ) then
			append gChangeList n.name
	)
	
	catch()
	
	-- Make sure that we re-create the terrain data
	
	max modify mode 
	addmodifier n (SNOModDef())
	
	local newmod = (n.'Siege Max SNO')
	
	newmod.tFloorBits = tFloorBits
	newmod.tWaterBits = tWaterBits
	newmod.tIgnoredBits = tIgnoredBits
	newmod.tLockedNormBits = tLockedNormBits
   	newmod.tDoNotRoundBits = tDoNotRoundBits
		
	newmod.tDoorList = tDoorList
	newmod.tSelectedDoor = tSelectedDoor
		
	newmod.DoorEdgeList = oldmod.DoorEdgeList
	newmod.DoorLastEdges = DoorLastEdges
	newmod.DoorVertList = DoorVertList
	newmod.DoorLastVerts = DoorLastVerts
		
	newmod.DoorDirectionList = DoorDirectionList
	newmod.DoorDirectionListAcclimated = DoorDirectionListAcclimated
		
	newmod.FloorFaceList = FloorFaceList
	newmod.WaterFaceList = WaterFaceList
	newmod.IgnoredFaceList = IgnoredFaceList
	newmod.LockedNormVertList = LockedNormVertList
	newmod.DoNotRoundVertList = DoNotRoundVertList
	
	completeRedraw()
	
	return true
	
)

--------------------------------------------------------------------------------
fn SNOPopUpSetEnabled flg =
(
	try 
	(
		if gSNOToolsFloater != undefined then
		(
			if flg then
			(
				fltrSNODoors.SetPartiallyEnabled()
				fltrSNOTools.SetPartiallyEnabled()
			)
			else
			(
				fltrSNODoors.SetEnabled false
				fltrSNOTools.SetEnabled false
			)
		)
	)
	catch
	( 		format "Caught error in SNOPopUpSetEnabled()\n"
	)
)

--------------------------------------------------------------------------------
fn SNOPopUpSetEnabledMulti =
(
	try 
	(
		if gSNOToolsFloater != undefined then
		(
			fltrSNODoors.SetEnabled false
			fltrSNOTools.SetEnabledMulti()
		)
	)
	catch
	( 		format "Caught error in SNOPopUpSetEnabledMulti()\n"
	)
)

----------------------------------------------------------------------------------------
fn SNOPopUpSelectionUpdate =
(
	gSiegeNodeRenderMode = undefined 
	if gSNOToolsFloater != undefined then
	(
		if ($selection.count == 1) then
		(
			if SelectedHasASNOModifier() then
			(
				SNOPopUpSetEnabled true
				gSiegeNodeRenderMode = 0
				return true
			)
		)
		else if ($selection.count > 1) then
		(
			if AllSelectedHasASNOModifier() then
			(
				SNOPopUpSetEnabledMulti()
				gSiegeNodeRenderMode = 0
				return true			
			)
		)
		SNOPopUpSetEnabled false
		return true
	)
	
)


----------------------------------------------------------------------------------------
fn gSNOPopUp =
(
	if (classof gSNOToolsFloater) == RolloutFloater then
	(
		closeRolloutFloater gSNOToolsFloater
	)
	if ($selection.count == 1) then
	(
		if SelectedHasASNOModifier() then
		(
			gSNOToolsFloater= newRolloutFloater "SNO Tool Kit" 280 583
			addRollout fltrSNODoors gSNOToolsFloater
			addRollout fltrSNOTools gSNOToolsFloater
			SNOPopUpSetEnabled true
			gSiegeNodeRenderMode = 0			
			return true
		)
	)
	SNOPopUpSetEnabled false
	return true
)


----------------------------------------------------------------------------------------
rollout fltrSNOTools "Siege Node Tools"
(
	
	checkbutton ckbFloor "flr" pos:[31,24] width:26 height:24
	checkbutton ckbWater "wtr" pos:[68,24] width:26 height:24
	checkbutton ckbIgnored "ign" pos:[105,24] width:26 height:24
	checkbutton ckbLocked "lck" pos:[142,24] width:26 height:24
	checkbutton ckbNoRound "nrd" pos:[179,24] width:26 height:24
	
	label lblNumSelected "        " 
	

	button btnAddSel "Add Selected"
	button btnDelSel "Remove Selected"
	button btnClearAll "Remove All"
	button btnResetAndRound "Cleanup and Round Off Siege Node"

	--------------------------	
	-- Local functions
	--------------------------	
	
	fn SetEnabled flg =
	(
	
		clobber = false
		try 
		(
			clobber = (not flg) and (ckbFloor.checked or ckbWater.checked or ckbIgnored.checked or ckbLocked.checked or ckbNoRound.checked)
		)
		catch
		(
			format "Caught error determining clobber!\n"
		)

		if clobber then
		(
			ckbFloor.checked = false
			ckbWater.checked = false
			ckbIgnored.checked = false
			ckbLocked.checked = false
			ckbNoRound.checked = false
			try 
			(
				--$.selectedfaces = #{}
				dsSetMeshSelected $.'Siege Max SNO' #{} 3
				--$.selectedverts = #{}
				dsSetMeshSelected $.'Siege Max SNO' #{} 1
				SetSubSelectMode false
			)
			catch ()
			newlbl = "Selected Count: "
			lblNumSelected.text = newlbl
		)

		ckbFloor.enabled = flg 
		ckbWater.enabled = flg 
		ckbIgnored.enabled = flg 
		ckbLocked.enabled = flg 
		ckbNoRound.enabled = flg 
		
		lblNumSelected.enabled = flg 
		btnAddSel.enabled = flg 
		btnDelSel.enabled = flg 	
		btnClearAll.enabled = flg 	
		btnResetAndRound.enabled = flg 
	
		if flg then fltrSNODoors.SetPartiallyEnabled()
		
	)
	
	fn SetPartiallyEnabled =
	(
		lblNumSelected.enabled = false 
		btnAddSel.enabled = false 
		btnDelSel.enabled = false 
		btnClearAll.enabled = false 
		
		btnResetAndRound.enabled = SelectedHasASNOModifier()
	
		ckbFloor.enabled = true 
		ckbWater.enabled = true 
		ckbIgnored.enabled = true 
		ckbLocked.enabled = true 
		ckbNoRound.enabled = true 
		
		ckbFloor.checked = false
		ckbWater.checked = false
		ckbIgnored.checked = false
		ckbLocked.checked = false
		ckbNoRound.checked = false
	)

	fn SetEnabledMulti =
	(
		SetEnabled false
		btnResetAndRound.enabled = AllSelectedHasASNOModifier()
	)
	
	fn GetMeshBits =
	(
		if      (ckbFloor.checked)   then return $.'Siege Max SNO'.tFloorBits	
		else if (ckbWater.checked)   then return $.'Siege Max SNO'.tWaterBits 
		else if (ckbIgnored.checked) then return $.'Siege Max SNO'.tIgnoredBits
		else if (ckbLocked.checked)  then return $.'Siege Max SNO'.tLockedNormBits
		else if (ckbNoRound.checked) then return $.'Siege Max SNO'.tDoNotRoundBits
		else return #{}
	)

	fn SetMeshBits bits =
	(
		if bits == undefined then (messagebox "undefined bits")
		if      (ckbFloor.checked)   then $.'Siege Max SNO'.tFloorBits = bits 	
		else if (ckbWater.checked)   then $.'Siege Max SNO'.tWaterBits = bits  
		else if (ckbIgnored.checked) then $.'Siege Max SNO'.tIgnoredBits = bits 
		else if (ckbLocked.checked)  then $.'Siege Max SNO'.tLockedNormBits = bits 
		else if (ckbNoRound.checked) then $.'Siege Max SNO'.tDoNotRoundBits = bits 
	)
	
	fn GetMeshFaceList =
	(
		if      (ckbFloor.checked)   then return $.'Siege Max SNO'.FloorFaceList	
		else if (ckbWater.checked)   then return $.'Siege Max SNO'.WaterFaceList

		else if (ckbIgnored.checked) then return $.'Siege Max SNO'.IgnoredFaceList
		else if (ckbLocked.checked)  then return $.'Siege Max SNO'.LockedNormVertList
		else if (ckbNoRound.checked) then return $.'Siege Max SNO'.DoNotRoundVertList
		else return #()
	)

	fn SetMeshList flist =

	(
		if flist == undefined then (messagebox "undefined bits")
		if      (ckbFloor.checked)   then $.'Siege Max SNO'.FloorFaceList = flist	
		else if (ckbWater.checked)   then $.'Siege Max SNO'.WaterFaceList = flist
		else if (ckbIgnored.checked) then $.'Siege Max SNO'.IgnoredFaceList = flist
		else if (ckbLocked.checked)  then $.'Siege Max SNO'.LockedNormVertList = flist
		else if (ckbNoRound.checked) then $.'Siege Max SNO'.DoNotRoundVertList = flist
	)

	fn SetSubSelectMode flg = (
		if flg then
		(
			max modify mode 
			-- Enter sel face mode
			-- modPanel.setCurrentObject $
			if (ckbLocked.checked or ckbNoRound.checked) then
			(
				SafeSetSubObjectLevel 1
			)
			else
			(
				SafeSetSubObjectLevel 3
			)
		)
		else
		(
			-- Leave sel face mode
			SafeSetSubObjectLevel 0
		)
		completeRedraw() --completeRedraw()
	)
	
	fn SetSelectedFaces flg = (
	
		--$.selectedfaces = GetMeshBits()
		dsSetMeshSelected $.'Siege Max SNO' (GetMeshBits()) 3
		if flg then
		(
		 	lbltext =      if ckbFloor.checked	 then "Num Floor Faces: "
					  else if ckbWater.checked   then "Num Water Faces: "
					  else if ckbIgnored.checked then "Num Ignored Faces: "
					  else " "
					 
			lblNumSelected.text = lbltext + ($.selectedfaces.count as string)  
		)
		else
		(
			lblNumSelected.text = "        "
		)
	)	
	
	fn SetSelectedVerts flg = (
				  
		--$.selectedverts = GetMeshBits()
		dsSetMeshSelected $.'Siege Max SNO' (GetMeshBits()) 1
		if flg then
		(
		 	lbltext =      if ckbLocked.checked	 then "Num Locked Normal Verts: "
					  else if ckbNoRound.checked then "Num No Roundoff Verts: "
					  else " "
	
			lblNumSelected.text = lbltext + ($.selectedverts.count as string)
		)
		else
		(
			lblNumSelected.text = "        "
		)
	)	
	
	on ckbFloor changed newstate do
	(
		if not lblNumSelected.enabled then SetEnabled true
		
		gSiegeNodeRenderMode = undefined
		oldstate = ckbWater.checked or ckbIgnored.checked or ckbLocked.checked or ckbNoRound.checked
		if oldstate then
		(
			ckbWater.checked = false
			ckbIgnored.checked = false
			ckbLocked.checked = false
			ckbNoRound.checked = false
		)
		SetSubSelectMode newstate
		SetSelectedFaces (oldstate or newstate)
		gSiegeNodeRenderMode = if (newstate) then 1 else 0
		completeRedraw()
	)
	on ckbWater changed newstate do
	(
		if not lblNumSelected.enabled then SetEnabled true
		
		gSiegeNodeRenderMode = undefined

		oldstate = ckbFloor.checked or ckbIgnored.checked or ckbLocked.checked or ckbNoRound.checked
		if oldstate then
		(
			ckbFloor.checked = false
			ckbIgnored.checked = false

			ckbLocked.checked = false
			ckbNoRound.checked = false
		)
		SetSubSelectMode newstate
		SetSelectedFaces (oldstate or newstate)
		gSiegeNodeRenderMode = if (newstate) then 2 else 0
		completeRedraw()
	)
	on ckbIgnored changed newstate do
	(
		if not lblNumSelected.enabled then SetEnabled true
		
		gSiegeNodeRenderMode = undefined
		gSiegeNodeRenderMode = if (newstate) then 3 else 0
		oldstate = ckbFloor.checked or ckbWater.checked or ckbLocked.checked or ckbNoRound.checked
		if oldstate then
		(
			ckbFloor.checked = false
			ckbWater.checked = false
			ckbLocked.checked = false
			ckbNoRound.checked = false
		)
		SetSubSelectMode newstate
		SetSelectedFaces (oldstate or newstate)
		gSiegeNodeRenderMode = if (newstate) then 2 else 0
		completeRedraw()
	)
	on ckbLocked changed newstate do
	(
		if not lblNumSelected.enabled then SetEnabled true
		
		gSiegeNodeRenderMode = undefined
		oldstate = ckbFloor.checked or ckbWater.checked or ckbIgnored.checked or ckbNoRound.checked
		if oldstate then
		(
			ckbFloor.checked = false
			ckbWater.checked = false
			ckbIgnored.checked = false
			ckbNoRound.checked = false
		)
		SetSubSelectMode newstate
		SetSelectedVerts (oldstate or newstate)
		gSiegeNodeRenderMode = if (newstate) then 4 else 0
		completeRedraw()
	)
	on ckbNoRound changed newstate do
	(
		if not lblNumSelected.enabled then SetEnabled true
		
		gSiegeNodeRenderMode = undefined
		oldstate = ckbFloor.checked or ckbWater.checked or ckbIgnored.checked or ckbLocked.checked
		if oldstate then
		(
			ckbFloor.checked = false
			ckbWater.checked = false
			ckbIgnored.checked = false
			ckbLocked.checked = false
		)
		SetSubSelectMode newstate
		SetSelectedVerts (oldstate or newstate)
		gSiegeNodeRenderMode = if (newstate) then 5 else 0
		completeRedraw()
	)
	on btnAddSel pressed do
	(
		if (ckbLocked.checked or ckbNoRound.checked) then
		(
			bits = GetMeshBits() + (getvertselection $)
			SetMeshBits bits 
			SetMeshList (bits as array)
			SetSelectedVerts true
		)
		else
		(
			bits = GetMeshBits() + (getfaceselection $)
			SetMeshBits bits 
			SetMeshList (bits as array)
			SetSelectedFaces true
		)
	)
	on btnDelSel pressed do
	(
		if (ckbLocked.checked or ckbNoRound.checked) then
		(
			bits = GetMeshBits() * ( -(getvertselection $) )
			SetMeshBits bits 
			SetMeshList (bits as array)
			SetSelectedVerts true
		)
		else
		(
			bits = GetMeshBits() * ( -(getfaceselection $) )
			SetMeshBits bits 
			SetMeshList (bits as array)
			SetSelectedFaces true
		)
		
	)
	on btnClearAll pressed do
	(
		SetMeshBits #{} 
		SetMeshList #()
		if (ckbLocked.checked or ckbNoRound.checked) then
		(
			SetSelectedVerts true
		)
		else
		(
			SetSelectedFaces true
		)
	)
	
	on btnResetAndRound pressed do
	(
		undo on
		(
			gChangeList = #()

			for s in $selection do
			(
				ResetAndRoundoffSNO s
				fltrSNODoors.RebuildDoorTables s false
			)

			format "*** Changelist ***\n"
			if ( gChangeList.count > 0 ) then
			(
				for n in gChangeList do
					format "%\n" n
			)
			else
			(
				format "<nothing has changed>\n"
			)
		)
	)
	
	on fltrSNOTools open do
	(
		completeRedraw() --completeRedraw()
	)
	
	on fltrSNOTools close do
	(
		SetSubSelectMode false
	)
	
)

callbacks.RemoveScripts id:#SNOPOPUP 
callbacks.AddScript #selectionSetChanged  "SNOPopUpSelectionUpdate()" id:#SNOPOPUP


----------------------------------------------------------------------------------------
--
--	Siege Node Rendering 
--
----------------------------------------------------------------------------------------

fn DisplaySiegeNodeData = 
(
	if not (fltrSNOTools.open and fltrSNODoors.open) then return false
	
	if gSiegeNodeRenderMode == undefined then return false
	
	local s = $selection[1]

	-- Make sure that we are processing SiegeNode modifiers 
	local sno = $selection[1].Modifiers["Siege Max SNO"]

	if sno == undefined then return false
	
	gw.ResetUpdateRect()	
	
	local curr_limits = gw.GetRndLimits()
	local new_limits = join curr_limits #(#zBuffer,#twosided)
	--gw.setRndLimits new_limits
	
	gw.SetTransform (matrix3 1) -- s.transform
	
	-- Only allow doors to be drawn, everything else takes too long
	-- to render right now. Using "selected face shading" (toggle with F2)
	-- is more efficient
	gSiegeNodeRenderMode = 0
	
	if gSiegeNodeRenderMode == 1 then
	(	
		dirty = true
		for fi in sno.FloorFaceList do in coordsys world
		(
			fc = getface s fi
			vtxA = getvert s fc.x
			vtxB = getvert s fc.y
			vtxC = getvert s fc.z
			--format "%\n" #(vtxA,vtxB,vtxC)
			--gw.PolyLine #(vtxA,vtxB,vtxC) true
 
			gw.Polygon #(vtxA,vtxB,vtxC) #(green,green,green) #([0,0,0],[0,0,0],[0,0,0])
		)
	)
	else if gSiegeNodeRenderMode == 2 then
	(		
		for fi in sno.WaterFaceList do in coordsys world
		(
			fc = getface s fi
			vtxA = getvert s fc.x
			vtxB = getvert s fc.y
			vtxC = getvert s fc.z
			--format "%\n" #(vtxA,vtxB,vtxC)
			--gw.PolyLine #(vtxA,vtxB,vtxC) true
 
			gw.Polygon #(vtxA,vtxB,vtxC) #(purple,purple,purple) #([0,0,0],[0,0,0],[0,0,0])
		)
	)
	else if gSiegeNodeRenderMode == 3 then
	(
		for fi in sno.IgnoredFaceList do in coordsys world
		(
			fc = getface s fi
			vtxA = getvert s fc.x
			vtxB = getvert s fc.y
			vtxC = getvert s fc.z
			--format "%\n" #(vtxA,vtxB,vtxC)
			--gw.PolyLine #(vtxA,vtxB,vtxC) true
 
			gw.Polygon #(vtxA,vtxB,vtxC) #(yellow,yellow,yellow) #([0,0,0],[0,0,0],[0,0,0])
		)
	)
	else if gSiegeNodeRenderMode == 4  then
	(
		gw.SetColor #line orange
		for i = 1 to sno.LockedNormVertList.count do in coordsys world
		(
			lnv = (getvert s sno.LockedNormVertList[i])
			local lockedup = [0,0,1] * (gw.getVPWorldWidth lnv)/20		
			gw.PolyLine #(lnv ,(lnv +lockedup )) false			
		)
	)
	else if gSiegeNodeRenderMode == 5 then
	(
		gw.SetColor #line orange
		for i = 1 to sno.DoNotRoundVertList.count do in coordsys world
		(
			lnv = (getvert s sno.LockedNormVertList[i])
			local lockedup = [0,0,1] * (gw.getVPWorldWidth lnv)/20		
			gw.PolyLine #(lnv ,(lnv +lockedup )) false			
		)
	)
	
	if (sno.DoorVertList.count != 0) then
	(			
		for di in sno.DoorVertList do
		(
			vtx = getvert s di
			gw.Marker vtx #triangle color:green
		)
		
		
		local vmin = 0
		local vmax = 0
		local firstv = [0,0,0]
		local lastv =  [0,0,0]
		local doorcenter = [0,0,0]
		local widthscale = 0
		local doordelta = [0,0,0]
		local numsegs = 0
				

		for i = 1 to sno.DoorLastVerts.count do in coordsys world
		(
			vmin = vmax+1
			vmax = sno.DoorLastVerts[i]
			
			firstv = (getvert s sno.DoorVertList[vmin])
			lastv =  (getvert s sno.DoorVertList[vmax])
			
			doorcenter = ((firstv+lastv) * 0.5)
			
			widthscale = (gw.getVPWorldWidth doorcenter)/20
			
			doordelta = lastv-firstv
		
			numsegs = ceil (2*(length doordelta)/widthscale)
			
			doordelta = doordelta/((2*numsegs)+1)
			
			local doorverts = #(firstv,firstv + doordelta)
			
			gw.SetColor #line blue
		
			doordelta *= 2
			for i = 0 to numsegs do
			(
				gw.PolyLine doorverts false
				doorverts[1] += doordelta
				doorverts[2] += doordelta
			)			

			local ddiroff
			if ( gShowAcclimatedDoorDirection ) then
				ddiroff = sno.DoorDirectionListAcclimated[i] * widthscale
			else
				ddiroff = sno.DoorDirectionList[i] * widthscale		
			gw.SetColor #line yellow
			gw.PolyLine #(doorcenter,(doorcenter+ddiroff )) false			
			
			gw.Text (doorcenter+ddiroff) (i as string)
		)
		
	)
	
	for i = 1 to sno.LockedNormVertList.count do in coordsys world
	(
		vtx = getvert s sno.LockedNormVertList[i]
		gw.Marker vtx #triangle color:yellow
		local ddiroff = [0,0,0.667] * widthscale		
		gw.SetColor #line orange
		gw.PolyLine #(vtx ,(vtx +ddiroff )) false			
	)
	
	for i = 1 to sno.DoNotRoundVertList.count do in coordsys world
	(
		vtx = getvert s sno.DoNotRoundVertList[i]
		gw.Marker vtx #triangle color:red
	)
	
	gw.EnlargeUpdateRect #whole
	gw.UpdateScreen()
	gw.SetRndLimits curr_limits
					
)

fn DrawSiegeNodeCallback = 
(
	try
	(
 		DisplaySiegeNodeData()	
	)
	catch
	(
		-- print "DrawSiegeNodeCallback error!"
	)
)

unRegisterRedrawViewsCallback DrawSiegeNodeCallback
registerRedrawViewsCallback DrawSiegeNodeCallback

