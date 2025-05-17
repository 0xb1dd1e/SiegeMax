global dsglb_BoxFourCC = #("CLIP","COLL","SLCT")
global dsglb_BoxNames = #("BBox_Clipping","BBox_Collision","BBox_Selection")

fn dscb_CollectBBoxes n = (

	lst = #()
	
	for nm in dsglb_BoxNames do 
	(
		for kid in n.children do 
		(
			if (ClassOf kid == Box ) and (nm == kid.name) then 
			(
				kid.pivot = kid.center
				append lst kid
			)
		)
	)
	
	return lst
	
)

fn FindBBox n i = (

	if i<1 or i>dsglb_BoxNames.count then return undefined
	
	for kid in n.children do 
	(
		if (ClassOf kid == Box ) and  dsglb_BoxNames[i] == kid.name then return kid
	)

	return undefined
)

fn AddBBox n i cl = (

	if i<1 or i>dsglb_BoxNames.count then return undefined
 	
	local oldb = FindBBox n i
	if oldb != undefined then delete oldb 
	
	local l = n.max.y-n.min.y
	local w = n.max.x-n.min.x
	local h = n.max.z-n.min.z
	local c = [n.center.x,n.center.y,n.min.z]
	local bbox = box length:l width:w height:h pos:c xray:true
	bbox.pivot = bbox.center
	bbox.name = dsglb_BoxNames[i]
	bbox.wirecolor = cl
	bbox.parent = n
	return bbox
)

fn EquivalentBBoxes a b = (
	return (a.center == b.center) and (a.min == b.min) and (a.max == b.max)
)
	

----------------------------------------------------------------------------------------------------
rcmenu BBoxRCMenu (

	fn SkinmeshOnly = (
	
		try (
			if selection.count != 1 then return false
			
			nm = dsLowerCase $selection[1].name
					
			if (findstring nm "skinmesh" != 1) and (findstring nm "m_" != 1) then return false
			
			if (canConvertTo $selection[1] Editable_Mesh) then (
				return false
			)

			return true	
		) 
		
		catch()
		
		return false
	)


	subMenu "BBox Tools" filter:SkinmeshOnly (
	
		menuItem AddClippingBox  "Add CLIPPING BBox"
		menuItem AddCollideBox   "Add COLLISION BBox"
		menuItem AddSelectionBox "Add SELECTION BBox"
		menuItem HideBBoxes "Hide BBoxes"
		menuItem ShowBBoxes "Show BBoxes"
		
	)
	
	On AddCollideBox picked do (
		b = AddBBox $selection[1] 1 (color 134 6 6)
		select b
	)
	
	On AddClippingBox picked do (
		b = AddBBox $selection[1] 2 (color 6 134 6)
		select b
	)

	On AddSelectionBox picked do (
		b = AddBBox $selection[1] 3 (color 6 134 134)
		select b
	)
	
	On HideBBoxes picked do (
		bx = CollectBBoxes $selection[1]
		for b in bx do hide b
	)
	
	On ShowBBoxes picked do (
		bx = CollectBBoxes $selection[1]
		for b in bx do unhide b
	)
	
)
--registerRightClickMenu BBoxRCMenu 
