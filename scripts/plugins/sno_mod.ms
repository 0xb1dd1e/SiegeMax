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

	-- VData channels used to preserve the per-vert door information
	-- If this gets too bloated with all the data on verts then I
	-- might have to try and do this with vertmaps (again)
	local tDoorPNum = 11
	local tDoorPSeq = 12
	local tDoorQNum = 13
	local tDoorQSeq = 14
	local tDoorPosX = 15
	local tDoorPosY = 16
	local tDoorPosZ = 17

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

		-- Build a list of all edges from faces containing door verts
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

		-- While we have more than the minimal spanning set of edges
		-- Remove a edge that revisit a verts
		local redundant = #{}
		local fanout = #()

		expectedEdgeCount = (doorVertSet.numberset-1)		 
		while edgeList.count > expectedEdgeCount do (

			local worstVert = 0
			for v in doorVertSet do (
				fanout[v] = 0
				if worstVert == 0 then worstVert = v
				edges = meshop.getEdgesUsingVert obj v
				for edge in edges do (
					if (findItem edgeList edge) > 0 do (
						fanout[v] += 1
					)
				)
				if fanout[v] > fanout[worstVert] then (
					worstVert = v
				)
				redundant[v] = fanout[v] > 2
			)
			
			if (fanout[worstVert] <= 2) then (
				--format "The door verts form a closed loop of edges. You are going to get a loopy door message.\n"
				exit
			)
			
			-- Look for edges that have faces on both sides. This would indicate that they are not on the boundary
			-- of the mesh and make good candidates for pruning out of the set of edges that span the door verts.
			local worstEdge = 0
			local usingWorstVert = meshop.getEdgesUsingVert obj #(worstVert) as bitarray
			for r in redundant do (	
				local edgesUsingRedundantVert =  meshop.getEdgesUsingVert obj #(r) as bitarray
				local candidates = usingWorstVert * edgesUsingRedundantVert
				for candidate in candidates do (
					revEdges = meshop.getEdgesReverseEdge obj candidate
					-- format "candidate % as % reverse edges % (idx: %)\n" candidate revEdges.numberset revEdges ((findItem edgeList (revEdges as array)[1]))
					if revEdges.numberset > 0 then (
						wedge = (revEdges as array)[1]
						if (findItem edgeList wedge) > 0 then (
							-- format "candidate % wedge %\n" candidate wedge
							worstEdge = wedge
							exit
						)
					)					
				)
				if (worstEdge > 0) then (
					exit
				)
			)				

			-- Prune the worst edge and try again. We converge on a spanning set
			prunedList = #()
			for keeper in edgelist do if keeper != worstEdge then append prunedList keeper	

			if (edgeList.count == prunedList.count) then (
				format "ERROR: nothing was pruned!!!\n"
				exit
			)
			edgeList = prunedList
		)

		return edgeList
	)   

	fn SaveDoorVertMapping snoMod = (
		-- Store the information that tells us which verts make up
		-- each door in the #tDoorChannel mapping channel.
		-- We can recover the information and reconstruct the doors
		-- after a topology change.

		format "PreserveDoorVertMapping!\n"
		local snoMesh = (refs.dependents snoMod)[1]

		if (meshop.getNumVDataChannels snoMesh) <= snoMod.tDoorPosZ then (
			meshop.setNumVDataChannels snoMesh (snoMod.tDoorPosZ+1) keep:true
		)

		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorPNum) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorPNum true		
		)

		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorPSeq) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorPSeq true		
		)

		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorQNum) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorQNum true		
		)

		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorQSeq) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorQSeq true		
		)

		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorPosX) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorPosX true		
		)
		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorPosY) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorPosY true		
		)
		if not (meshop.getVDataChannelSupport snoMesh snoMod.tDoorPosZ) then (
			meshop.setVDataChannelSupport snoMesh snoMod.tDoorPosZ true		
		)
		
		for v = 1 to snoMesh.numVerts do (
			meshop.setVDataValue snoMesh snoMod.tDoorPNum v 0
			meshop.setVDataValue snoMesh snoMod.tDoorPSeq v 0
			meshop.setVDataValue snoMesh snoMod.tDoorQNum v 0
			meshop.setVDataValue snoMesh snoMod.tDoorQSeq v 0
		)

		local numStored = 0

		for d = 1 to snoMod.tDoorList.count do
		(	
			-- format "door %\n" d
			local snoDoor = snoMod.tDoorList[d]		
			for v = 1 to snoDoor.verts.count do (

				local dv = snoDoor.verts[v]

				local dPn = (meshop.getVDataValue snoMesh snoMod.tDoorPNum dv) as integer
				local dPs = (meshop.getVDataValue snoMesh snoMod.tDoorPSeq dv) as integer
				local dQn = (meshop.getVDataValue snoMesh snoMod.tDoorQNum dv) as integer
				local dQs = (meshop.getVDataValue snoMesh snoMod.tDoorQSeq dv) as integer	
				
				local info = #()
				if dPn == 0 then (
					-- This the first time we've seen this vert
					dPn = d
					dPs = v
					meshop.setVDataValue snoMesh snoMod.tDoorPNum dv dPn
					meshop.setVDataValue snoMesh snoMod.tDoorPSeq dv dPs

					-- Save the location of the vertex as so we can tell
					-- if it has been bumped.. (and perhaps snap it back?)

					local pos = meshop.getVert snoMesh dv
					-- format "stowing % %\n" dv pos
					meshop.setVDataValue snoMesh snoMod.tDoorPosX dv pos.x
					meshop.setVDataValue snoMesh snoMod.tDoorPosY dv pos.y
					meshop.setVDataValue snoMesh snoMod.tDoorPosZ dv pos.z

					numStored += 1
				)
				else (
					-- This the second time we've seen this vert
					if (dPn == d) then (
						format "loopy door detected %\n" d
						if (v != snoDoor.verts.count) then (
							format "BROKEN loopy door detected % %\n" d
						)
						dPs = -v -- negative value indicates we are first AND last
						meshop.setVDataValue snoMesh snoMod.tDoorPseq dv dPs								
					)
					else (
						-- we have started a new door
						if (dQn != 0) then (
							format "triple (or more) door detected % %\n" d dQn
						)
						dQn = d
						dQs = v
						meshop.setVDataValue snoMesh snoMod.tDoorQNum dv dQn
						meshop.setVDataValue snoMesh snoMod.tDoorQSeq dv dQs					
					)					
				)
				-- format "    info % % % % %\n" dv dPn dPs dQn dQs 
			)
		)

		-- format "Store info into % verts\n" numStored
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

			local dPn = ((meshop.getVDataValue snoMesh snoMod.tDoorPNum v) as integer)
			local dPs = ((meshop.getVDataValue snoMesh snoMod.tDoorPSeq v) as integer)
			local dQn = ((meshop.getVDataValue snoMesh snoMod.tDoorQNum v) as integer)
			local dQs = ((meshop.getVDataValue snoMesh snoMod.tDoorQSeq v) as integer)

			local pos = point3 \
						(meshop.getVDataValue snoMesh snoMod.tDoorPosX v) \
			 			(meshop.getVDataValue snoMesh snoMod.tDoorPosY v) \
			  			(meshop.getVDataValue snoMesh snoMod.tDoorPosZ v) 
	
			if (dPn != 0) then (
				format "We need to restore % % % % % %\n" v dPn dPs dQn dQs pos
				numFound += 1
				if doorVerts[dPn] == undefined then (
					doorVerts[dPn] = #()
				)
				doorVerts[dPn][dPs] = v
				if (dQn != 0) then (
					if doorVerts[dQn] == undefined then (
						doorVerts[dQn] = #()
					)
					doorVerts[dQn][dQs] = v
				)
			)
		)
		
		format "Found info for % verts\n" numFound

		for d = 1 to doorVerts.count do (
			local doorVertList = doorVerts[d]
			local doorEdgeList = collectDoorEdgesForVerts snoMesh (doorVertList as bitarray)
			format "restoring % % %\n" d doorVertList doorEdgeList
			-- Now we need to know if this really is a 
			-- TODO perhaps a little validation here...
			snoMod.tDoorList[d].verts = doorVertList
			snoMod.tDoorList[d].edges = doorEdgeList
		)

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