----------------------------------------------------------------------------------------
--
-- Scripted Modifier Plugin for SIEGE NODES
--
----------------------------------------------------------------------------------------

GLOBAL gSNOPopUp
fn gSNOPopUp = ()

plugin modifier SNOModDef 
name:"Siege Max SNO" 
classID:#(0x7f621ebb, 0x6850842e)
extends:Mesh_Select replaceUI:false version:4 
category:"Siege Max"
( 
	parameters SNODATA
	(
		DoorEdgeList				type:#intTab	animatable:false tabsizevariable:true
		DoorLastEdges				type:#intTab	animatable:false tabsizevariable:true
		DoorVertList				type:#intTab	animatable:false tabsizevariable:true
		DoorLastVerts				type:#intTab	animatable:false tabsizevariable:true
		DoorDirectionList			type:#point3Tab	animatable:false tabsizevariable:true
		DoorDirectionListAcclimated	type:#point3Tab	animatable:false tabsizevariable:true
		DoorForcedDir				type:#intTab	animatable:false tabsizevariable:true

		FloorFaceList				type:#intTab	animatable:false tabsizevariable:true
		WaterFaceList				type:#intTab	animatable:false tabsizevariable:true
		IgnoredFaceList				type:#intTab	animatable:false tabsizevariable:true
		LockedNormVertList			type:#intTab	animatable:false tabsizevariable:true
		DoNotRoundVertList			type:#intTab	animatable:false tabsizevariable:true
	)
	
	local tDoorList = #()
	local tFloorBits = #{} 
	local tWaterBits = #{}
	local tIgnoredBits = #{}
	local tLockedNormBits = #{}
	local tDoNotRoundBits = #{}
	local tSelectedDoor = undefined

	local tDoorChannel = 10

	struct SiegeDoor (verts,edges)
	
	rollout ModActions "Siege Max SNO"
	(
		button OpenSNOToolkit "Open SNO Tool Kit"
		
		on OpenSNOToolkit pressed do ( gSNOPopUp() )

		button SaveDoorVerts "Save Door Verts"		
		on SaveDoorVerts pressed do ( this.SaveDoorVertMapping this )		

		button RestoreDoorVerts "Restore Door Verts"		
		on RestoreDoorVerts pressed do ( this.RestoreDoorVertMapping this )		
	)

	fn collectDoorEdgesForVerts obj doorVertSet =
	(
		local edgeList = #()
		local edgeMap = #() -- prevent duplicates

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
				local edgeIndex = 3 * (f-1) + ee
				append edgeList edgeIndex
				append edgeMap key
				) 
			)
			)
		)
	
		return edgeList
	)   

	fn SaveDoorVertMapping snoMod = (
		-- Store the information that tells us which verts make up
		-- each door in the #tDoorChannel mapping channel.
		-- We can recover the information and reconstruct the doors
		-- after a topology change.

		format "UpdateDoorVertMapping!\n"
		local snoMesh = (refs.dependents snoMod)[1]

		if (meshop.getNumMaps snoMesh) <= snoMod.tDoorChannel then (
			meshop.setNumMaps snoMesh (snoMod.tDoorChannel+1) keep:true
		)

		if not (meshop.getMapSupport snoMesh snoMod.tDoorChannel) then (
			meshop.setMapSupport snoMesh thsnoModis.tDoorChannel true		
		)

		meshop.setNumMapVerts snoMesh snoMod.tDoorChannel (snoMesh.numVerts)
		for v = 1 to snoMesh.numVerts do (
			meshop.setMapVert snoMesh snoMod.tDoorChannel v (point3 0 0 0)
		)

		local numStored = 0

		for d = 1 to snoMod.tDoorList.count do
		(	
			format "door %\n" d
			local snoDoor = snoMod.tDoorList[d]		
			for v = 1 to snoDoor.verts.count do (

				local dv = snoDoor.verts[v]

				local flags = 0				
				if v == 1 then flags += 1 -- first vert of door
				if v == snoDoor.verts.count then flags += 2 -- last vert of door

				local info = meshop.getMapVert snoMesh snoMod.tDoorChannel dv
				if info.x == 0 then (
					-- This the first time we've seen this vert
					info.x = d
					info.y = 0
					info.z = flags
					numStored += 1
				)
				else (
					-- This the second time we've seen this vert
					if (info.x == d) then (
						format "loopy door detected %\n" d
						info.y = 0						
						info.z = bit.or (info.z as integer) flags						
					)
					else (
						-- we have started a new door
						if (info.y != 0) then (
							format "borked door detected % %\n" d info.y
						)
						info.y = d
						info.z = bit.or (info.z as integer) (bit.shift 2 flags)
					)					
				)
				format "    info % %\n" dv info 
				meshop.setMapVert snoMesh snoMod.tDoorChannel dv info
			)
		)

		format "Store info into % verts\n" numStored
	)

	fn RestoreDoorVertMapping snoMod = (
		-- Store the information that tells us which verts make up
		-- each door in the #tDoorChannel mapping channel so that
		-- we can recover the information after a topology change

		local numFound = 0
		format "RestoreDoorVertMapping!\n"
		local snoMesh = (refs.dependents snoMod)[1]

		local doorVerts = #()
		for v = 1 to snoMesh.numVerts do (
			local info = meshop.getMapVert snoMesh snoMod.tDoorChannel v
			local d0 = info.x as integer			
			local d1 = info.y as integer			
			if (d0 != 0) then (
				format "We need to restore % %\n" v info
				numFound += 1
				if doorVerts[d0] == undefined then (
					doorVerts[d0] = #{v}
				)
				else (
					doorVerts[d0][v] = true
				)
				if (d1 != 0) then (
					if doorVerts[d1] == undefined then (
						doorVerts[d1] = #{v}
					)
					else (
						doorVerts[d1][v] = true
					)
				)
			)
		)
		
		format "Found info in % verts\n" numFound

		local edges = #()
		for d = 1 to doorVerts.count do (
			doorVertSet = doorVerts[d]
			doorEdgeList = (collectDoorEdgesForVerts snoMesh doorVertSet)
			format "% % %\n" d doorVertSet doorEdgeList
			append edges doorEdgeList
		)

		-- Now we need to know if this really is a 
		--snoMod.tVertList = doorVertSet as array
		--snoMod.tEdgeList = edgelist		

	)
			
	fn RebuildInternals =
	(
		this.tFloorBits = #{}
		for b in this.FloorFaceList do append this.tFloorBits b
		
		this.tWaterBits = #{}
		for b in this.WaterFaceList do append tWaterBits b
	
		this.tIgnoredBits = #{}
		for b in this.IgnoredFaceList do append this.tIgnoredBits b 
	
		this.tLockedNormBits = #{}
		for b in this.LockedNormVertList do append tLockedNormBits b 

		this.tDoNotRoundBits = #{}
		for b in this.DoNotRoundVertList do append tDoNotRoundBits b 
		
		this.tDoorList = #()

		for i = 1 to DoorLastEdges.count do
		(
			local vmin = if i > 1 then (this.DoorLastVerts[i-1]+1) else 1
			local vmax = this.DoorLastVerts[i]
			local doorverts = for v = vmin to vmax collect this.DoorVertList[v]
			
			local emin = if i > 1 then (this.DoorLastEdges[i-1]+1) else 1
			local emax = this.DoorLastEdges[i]
 			local dooredges = for e = emin to emax collect this.DoorEdgeList[e]
			
			append this.tDoorList (SiegeDoor doorverts dooredges)
		)
	)

	on create do 
	(	
		 this.tFloorBits = #{}
		 this.tWaterBits = #{}
		 this.tIgnoredBits = #{}
		 this.tLockedNormBits = #{}
   		 this.tDoNotRoundBits = #{}
		
		 this.tDoorList = #()
		 this.tSelectedDoor = undefined
		
		 this.DoorEdgeList = #()
		 this.DoorLastEdges = #()
		 this.DoorVertList = #()
		 this.DoorLastVerts = #()
		
		 this.DoorDirectionList = #()
		 this.DoorDirectionListAcclimated = #()
		 this.DoorForcedDir = #()
		
		 this.FloorFaceList = #()			
		 this.WaterFaceList = #()		
		 this.IgnoredFaceList = #()
		 this.LockedNormVertList = #()	
		 this.DoNotRoundVertList = #()
		
		--try 
		(
			local oldmod = $selection[1].modifiers["Siege Max SNO"]

			if (classof oldmod) == (classof this) then
			(		
				-- format "Pulling new SNODATA out of another SNO MOD\n"
				
				this.DoorEdgeList = oldmod.DoorEdgeList 
				this.DoorLastEdges = oldmod.DoorLastEdges 
				this.DoorVertList = oldmod.DoorVertList 
				this.DoorLastVerts = oldmod.DoorLastVerts 
				this.DoorDirectionList = oldmod.DoorDirectionList 
				this.DoorDirectionListAcclimated = oldmod.DoorDirectionListAcclimated
				
				this.FloorFaceList = oldmod.FloorFaceList 		
				this.WaterFaceList = oldmod.WaterFaceList 				
				this.IgnoredFaceList = oldmod.IgnoredFaceList 				
				this.LockedNormVertList = oldmod.LockedNormVertList 				
				this.DoNotRoundVertList = oldmod.DoNotRoundVertList 				
				
				RebuildInternals()
			)
		)
		--catch
		--(
		--	format "Encountered an error while pulling SNODATA!\n"
		--)
	)
		
	on update do 
	(	
		--format "Updating SNOMODDEF version %\n" version
		RebuildInternals()
	)
	
	on load do 
	(
		--print "Loading SNO"
		RebuildInternals()
	)
	
)