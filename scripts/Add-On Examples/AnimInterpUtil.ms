-------------------------------------------------------------------------------------------------------------
--
-- This example adds a maxscript utility panel that provides a tool for converting the animation controller
-- interpolation of all the bones in a scene to linear or bezier. 
-- 
-- Copy this file into the gmax/gamepacks/SiegeMax/Scripts/Add-Ons folder to enable the utility it defines
--
-- To learn more about creating your own scripted utilities like the one below, search gmax's online 
-- MAXscript reference for the phrase "Scripted Utility Panels"
--
-------------------------------------------------------------------------------------------------------------

utility interp_toolkit "Interpolation Toolkit" 
( 

    button linear_but "Make bone controllers linear"
    button bezier_but "Make bone controllers bezier"
	
	fn Linearize n = (
	
		local switched = false
		
		if ((classof n.controller) == PRS) then 
		(
			
			if (classof n.pos.controller) != linear_position then
			(
				n.pos.controller = linear_position()
				switched = true
			)
			
			if (classof n.rotation.controller) != linear_rotation then
			(
				n.rotation.controller = linear_rotation()
				switched = true
			)
			
			if (classof n.scale.controller) != linear_scale then
			(
				n.scale.controller = linear_scale()
				switched = true
			)
			
			if switched then (format "Converted % to LINEAR interpolation\n" n.name)
		)
		
		for c in n.children do 
		(
			switched = (Linearize c) or switched
		)
		
		return switched
	)
	
	fn Bezierize n = (
	
		local switched = false
		if ((classof n.controller) == PRS) then 
		(
			if (classof n.pos.controller) != bezier_position then
			(
				n.pos.controller = bezier_position()
				switched = true
			)
			
			if (classof n.rotation.controller) != bezier_rotation then
			(
				n.rotation.controller = bezier_rotation()
				switched = true
			)
			
			if (classof n.scale.controller) != bezier_scale then
			(
				n.scale.controller = bezier_scale()
				switched = true
			)
			
			if switched then (format "Converted % to BEZIER interpolation\n" n.name)
		)
		
		for c in n.children do
		(
			switched = (Bezierize c) or switched
		)
		
		return switched
	)
	
	fn FetchRoot n =
	(
		if n.parent == undefined then 
		(
			return n
		)
		return FetchRoot n.parent
	)
	
	fn FetchTopmostBone = 
	(
		local boneslist = $*bip*
		if boneslist.count < 1 then
		(
			boneslist = $*bone*
		)
		if boneslist.count < 1 then
		(
			MessageBox "Can't locate any BIP or BONE nodes" title:"BadNews"
			return undefined
		)
		return (FetchRoot boneslist[1])
	)
	
	
	on linear_but pressed do undo on 
	(			
		local tmb = FetchTopmostBone() 
		if tmb == undefined then return false
		
		if (dsQueryBox "Are you sure you want to convert all bone controllers to LINEAR interpolation?" default:false) then
		(
			Linearize tmb 
		)
	)
	
	on bezier_but pressed do undo on
	(
		local tmb = FetchTopmostBone()
		if tmb == undefined then return false
		
		if (dsQueryBox "Are you sure you want to convert all bone controllers to BEZIER interpolation?" default:false) then
		(
			Bezierize tmb 
		)
	)
)
