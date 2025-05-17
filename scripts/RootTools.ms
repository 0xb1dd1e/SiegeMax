fn RangeROOTtoTopBone picked =
(
	local RootBoneNode = dsFetchTopmostBone picked 
	
	if ($ROOT == undefined) or (RootBoneNode == undefined) then
	(
		return false
	)
	animate on (
	
		at time animationrange.start (
			if (classof RootBoneNode.controller) == Link_Control then
			(
				local lt = dsGetLinkControlledParentAtTime RootBoneNode animationrange.start
				if (lt != undefined and lt != false) then
				(
					$ROOT.position.x = lt.pos.x
					$ROOT.position.y = lt.pos.y
				)
			)
			else if (classof RootBoneNode.controller) == BipSlave_Control then
			(
				if (RootBoneNode.parent != undefined) and ((classof RootBoneNode.parent.controller) == Vertical_Horizontal_Turn) then
				(
					try
					(
						$ROOT.position.x = (RootBoneNode.parent).controller.horizontal.translation.x
						$ROOT.position.y = (RootBoneNode.parent).controller.horizontal.translation.y
					)
					catch
					(
						$ROOT.position.x = (RootBoneNode.parent).transform.pos.x
						$ROOT.position.y = (RootBoneNode.parent).transform.pos.y
					)
				)
			)
			else
			(
				$ROOT.position.x = RootBoneNode.pos.x
				$ROOT.position.y = RootBoneNode.pos.y
			)
		)
		
		at time animationrange.end (
			if (classof RootBoneNode.controller) == Link_Control then
			(
				local lt = dsGetLinkControlledParentAtTime RootBoneNode animationrange.end
				if (lt != undefined and lt != false) then
				(
					$ROOT.position.x = lt.pos.x
					$ROOT.position.y = lt.pos.y
				)
			)
			else if (classof RootBoneNode.controller) == BipSlave_Control then
			(
				if (RootBoneNode.parent != undefined) and ((classof RootBoneNode.parent.controller) == Vertical_Horizontal_Turn) then
				(
					try
					(
						$ROOT.position.x = (RootBoneNode.parent).controller.horizontal.translation.x
						$ROOT.position.y = (RootBoneNode.parent).controller.horizontal.translation.y
					)
					catch
					(
						$ROOT.position.x = (RootBoneNode.parent).transform.pos.x
						$ROOT.position.y = (RootBoneNode.parent).transform.pos.y
					)
				)
			)
			else
			(
				$ROOT.position.x = RootBoneNode.pos.x
				$ROOT.position.y = RootBoneNode.pos.y
			)
		)
	
	)
	
	return true
)

-------------------------------------------------------------------------
fn ResetRootPosMarker =
(
	try
	(	
		if $ROOT != undefined then 
		(
			delete $ROOT
		)
		
		newroot = LoadReferenceObject "__ROOT"
		
		if (newroot != undefined) then
		(
			newroot.name = "ROOT"
			newroot.rotation.controller = linear_rotation()
			newroot.position.controller = linear_position()
			newroot.scale.controller = linear_scale()
		)
		
	)	
	catch ()
)
	
-------------------------------------------------------------------------
fn AddFirstLastRootPosMarkerKeys picked = 
(
	try
	(
		RangeROOTtoTopBone picked
	)
	catch ()
)

-------------------------------------------------------------------------
fn BuildListOfNodesToAdjust picked =
( 
	-- When we play with the translation of the hierarchy, we need to
	-- be sure to adjust the topmost bone and the any 'loose' IK chains that
	-- affect bones that are attaches to the TMB
	
	local TMB = dsFetchTopmostBone picked 
	
	-- Make sure we have the TMB's parent if it exists
	-- (we WANT to include dummy bones)
	
	local rootobj = TMB
	while rootobj.parent != undefined do
	(
		rootobj = rootobj.parent
	)
	
	todo = #(rootobj)
	
	-- See if there are any IK chains that we need to adjust
	for ikobj in $* where ((classof ikobj) == IK_Chain_Object) do
	(
		-- Skip the ikobj if it is also a child of the TMB
		if (dsFetchTopmostBone ikobj) == TMB then continue
		
		if (dsFetchTopmostBone ikobj.controller.startJoint) == TMB or 
   			   (dsFetchTopmostBone ikobj.controller.endJoint) == TMB then
		(
		   append todo ikobj
		)
	)
	
	-- See if there are any Dummy objects floating around that we need to adjust
	for freedummy in $* where (((freedummy.parent) == undefined and (classof freedummy) == Dummy)) do
	(
		if (finditem todo freedummy) == 0 then 
		(
			append todo freedummy
		)
	)
	
	return todo
)



-------------------------------------------------------------------------
fn RestoreRootTranslation picked = 
(
	try (
	
		unfreeze $root
			
		todo = BuildListOfNodesToAdjust picked
		
		for obj in todo do 
		(
			unhide obj
			unfreeze obj
			if (classof obj.controller) == Vertical_Horizontal_Turn then
			(
				-- Biped is driving this character
				obj.controller.inPlaceYMode = false
			)
			else
			(
				for k in obj.position.controller.keys do
				(
					at time k.time animate on
					(
						obj.position += $root.position
					)
					
					-- Look for any loose IK controllers and move them too
				)
			)
		)
		
	)
	catch
	(
		print "Something broke RestoreRootTranslation" 
	)
	
)



-------------------------------------------------------------------------
fn RemoveRootTranslation picked = 
(
	try (
			
		freeze $root
		
		todo = BuildListOfNodesToAdjust picked
		
		for obj in todo do 
		(
			unhide obj
			unfreeze obj
			if (classof obj.controller) == Vertical_Horizontal_Turn then
			(
				-- Biped is driving this character
				obj.controller.inPlaceYMode = true
			)
			else
			(
				for k in obj.position.controller.keys do
				(
					at time k.time animate on
					(
						obj.position -= $root.position
					)
					
					-- Look for any loose IK controllers and move them too
				)
			)
		)
		

		
	)
	catch
	(
		print "Something broke RemoveRootTranslation" 
	)
	
)



