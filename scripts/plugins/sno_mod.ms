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

	local tDoorChannel = 89

	struct SiegeDoor (verts,edges)
	
	rollout ModActions "Siege Max SNO"
	(
		button OpenSNOToolkit "Open SNO Tool Kit"
		
		on OpenSNOToolkit pressed do ( gSNOPopUp() )
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
		
		snoMesh = (refs.dependentNodes this.modifier)[1]
		-- make sure we are on an editable mesh
		meshop.setNumMapVerts snoMesh tDoorChannel (snoMeshnumVerts)

		for i = 1 to DoorLastEdges.count do
		(
			local vmin = if i > 1 then (this.DoorLastVerts[i-1]+1) else 1
			local vmax = this.DoorLastVerts[i]
			local doorverts = for v = vmin to vmax collect this.DoorVertList[v]
			
			local emin = if i > 1 then (this.DoorLastEdges[i-1]+1) else 1
			local emax = this.DoorLastEdges[i]
 			local dooredges = for e = emin to emax collect this.DoorEdgeList[e]
			
			append this.tDoorList (SiegeDoor doorverts dooredges)
			
			-- Encode the door verts into the vertex mapping channel
			-- When we get a topology change message we _should_ be able to locate
			-- where the have migrated to :fingers-crossed-emoji:
			for dv in doorverts do (
				format "Yer now about to map % %\n"  dv [i,vmin,vmax]
				meshop.setMapVert snoMesh tDoorChannel dv (point3 i vmin vmax)
			)

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