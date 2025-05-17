global refobjlist = #()

global refobjfile = if ProductIs3dsMax()  then 
		(
			(getdir #scene) + "/Reference_Scenes/reference_objects.max" 
		)
		else
		(
			(getdir #maxroot) + "gamepacks/SiegeMAX/Scenes/Reference_Scenes/reference_objects.gmax"
		)

global droppertoolfloater = undefined

rollout RefObjDropper "Ref Object Dropper"  (

	local objname, MouseDropper

	listbox DropObjs "Available Objects" items:refobjlist
	checkbox SeeThrough "See-Through" 
	checkbox SpinObjs "Spin Objects"
	button DelObjs "Delete Objects"
	timer spinclock "Spin Clock" interval:100 active:false
	
	tool MouseDropper (
		
		fn DropObj wpoint = (
			if (mergemaxfile refobjfile  #(objname) #select #mergeDups) then (
				newobj = execute ("$"+objname)
				newobj.name = "_REFOBJ_"+newobj.name
				newobj.pos = wpoint ;
			)
		)
		
		on MousePoint clickno do
		(
			if clickno == 1 then
			(	
				try
				 (
					local newobj,existobj			
					existobj = execute ("$_REFOBJ_"+objname)
					if existobj == undefined then
					(
						if (mergemaxfile refobjfile  #(objname) #select #mergeDups) then
						(
							newobj = execute ("$"+objname)
						)
					)
					else
					(
						newobj = snapshot existobj
						newobj.wirecolor = existobj.wirecolor 
					)
					if newobj != undefined then
					(
						newobj.name = "_REFOBJ_"+newobj.name
						newobj.pos = worldPoint
						newobj.xray = SeeThrough.checked
					)
				)
				catch
				(
				 	format "Weird, failed to drop %\n" objname
				)
			) else (
				#stop
			)
		) 
		
		on end do
		(
			newobj = undefined
		)
		
	)
	
	on RefObjDropper open do (
		spinclock.active = false
	)
	
	on DelObjs pressed do (
		r = $_REFOBJ_*
		if (r.count > 0) then delete r
		spinclock.active = false
	)
	
	on DropObjs doubleclicked item do (
		objname = refobjlist[item]
		StartTool MouseDropper 
	)
	
	on SeeThrough changed state do (
		for r in $_REFOBJ_* do
		(
			r.xray = SeeThrough.checked
		)
	)

	on SpinObjs changed state do (
		spinclock.active = state
	)

	on SpinClock tick do (
		for r in $_REFOBJ_* do (
			rotate r 10 z_axis
		)
	)

)

fn OpenRefObjDropper = 
(
	refobjlist = getMAXFileObjectNames refobjfile
	sort refobjlist

	if droppertoolfloater != undefined and (classof droppertoolfloater) == RolloutFloater then
	(
		closerolloutfloater droppertoolfloater 
	) 
	droppertoolfloater = newRolloutFloater "Dropper"  180 350 800 200
	addrollout RefObjDropper droppertoolfloater 
)

