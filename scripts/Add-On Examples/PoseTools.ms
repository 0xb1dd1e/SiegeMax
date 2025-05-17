--------------------------------------------------------------------------------------------------------
-- This script has two parts: 
--
-- In the first section I've ported a set of 'pose tools' that our artists used to help synchronize the names
-- and rest positions of the bones of characters. (This was a headache in 3dsMax3.0, as gmax is much
-- improved, this set of tools is less useful now ...which make it a good candidate for an example!)
--
-- In the second section, I created a quad menu extender that provides access to these tools.
--
-- Copy this file into the gmax/gamepacks/SiegeMax/Scripts/Add-Ons folder to use it
-- 
-- Look at gmax/gamepacks/SiegeMax/Add-On Examples/CustomQuadMenus.ms for more info on Quad Menus
--------------------------------------------------------------------------------------------------------

---******************************************************************************
--- Section 1: Defining the Pose Tools
---******************************************************************************

GLOBAL g_BoneInfoList
GLOBAL g_BoneTransformList
GLOBAL g_BoneTransformKeysList
GLOBAL g_BoneTransformKeyType
GLOBAL g_BoneList
GLOBAL g_PoseToolFloater 

--*************************************************************
fn BuildFullBoneListRecursive p_BoneNode = (

	append g_BoneList p_BoneNode
	
	for kid in p_BoneNode.children do (
		BuildFullBoneListRecursive kid 
	)
)

--*************************************************************
fn BuildFullBoneList p_BoneNode = (

	g_BoneList = #()
	
	BuildFullBoneListRecursive p_BoneNode
	
	return g_BoneList.count
)

--*************************************************************
fn CopyBoneInfo = (

	
	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to copy from"
		return false
	)

	while (b.parent != undefined) do b = b.parent

	g_BoneInfoList = #()
	BuildFullBoneList b

	for b in g_BoneList do (
		datalist = #(b.name)
		append g_BoneInfoList datalist 
	)
	
	return true

)
--*************************************************************
fn PasteBoneInfo sourcefile = (

	if (g_BoneInfoList.count == 0) then (
		MessageBox "You need to 'copy' before you can 'paste'"
		return false
	)
	
	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to paste to"
		return false
	)
	
	while (b.parent != undefined) do b = b.parent

	BuildFullBoneList b
	
	if (g_BoneInfoList.count != g_BoneList.count) then (
		MessageBox (
			"The number of bones you are trying to paste ["+
			(g_BoneInfoList.count as string)+
			"]\ndoesn't match the number of bones in this model ["+
			(g_BoneList.count as string)+"]\n") title:"Unable to paste"
		return false
	)
	
	for j = 1 to g_BoneList.count do (
	
		b = g_BoneList[j]
		
		b.name = g_BoneInfoList[j][1]
		
	)

	setUserPropBuffer $selection[1] ("Rest pose info copied from " +sourcefile)

	return true
)


--*************************************************************

fn IsBipedBone b = 
(
	false -- gmax has no Biped bones
)

--*************************************************************
fn CopyBoneTransform = (

	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to copy from"
		return false
	)

	while (b.parent != undefined) do b = b.parent

	g_BoneTransformList = #()
	BuildFullBoneList b

	shortlist = for b in g_BoneList where not IsBipedBone b collect b
	
	for b in shortlist do (
		append g_BoneTransformList (in coordsys parent b.transform)
	)
	
	return true

)

--*************************************************************
fn PasteBoneTransform sourcefile = (

	if (g_BoneTransformList.count == 0) then (
		MessageBox "You need to 'copy' before you can 'paste'"
		return false
	)
	
	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to paste to"
		return false
	)
	
	while (b.parent != undefined) do b = b.parent

	BuildFullBoneList b
	
	shortlist = for b in g_BoneList where not IsBipedBone b collect b
	
	if (g_BoneTransformList.count != shortlist.count) then (
		MessageBox (
			"The number of bones you are trying to paste ["+
			(g_BoneTransformList.count as string)+
			"]\ndoesn't match the number of bones in this model ["+
			(g_BoneList.count as string)+"]\n") title:"Unable to paste"
		return false
	)
	
	for j = 1 to shortlist.count do (
		in coordsys parent shortlist[j].transform = g_BoneTransformList[j]
	)

	setUserPropBuffer $selection[1] ("Rest pose info copied from " +sourcefile)

	return true
)

--*************************************************************
fn CopyBoneTransformKeys = (

	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to copy from"
		return false
	)

	while (b.parent != undefined) do b = b.parent

	g_BoneTransformKeysList = #()
	g_BoneTransformKeyType = #()

	BuildFullBoneList b

	shortlist = for b in g_BoneList where not IsBipedBone b collect b
	
	for b in shortlist do (

		keytimes = #()
		
		for k in b.position.keys do
		(
			append keytimes k.time
		)
		
		for k in b.rotation.keys do
		(
			if (finditem keytimes k.time) == 0 then
			(
				append keytimes k.time 
			)
		)
		
		pc = (classof b.position.controller)
		rc = (classof b.rotation.controller)
		sc = (classof b.scale.controller)
		
		append g_BoneTransformKeyType #(pc,rc,sc)
		
		translist = #()
		for kt in keytimes do at time kt in coordsys parent 
		(
			 append translist #(kt,b.transform)
		)
		append g_BoneTransformKeysList translist
	)
	
	return true

)


--*************************************************************
fn PasteBoneTransformKeys sourcefile = (

	if (g_BoneTransformKeysList.count == 0) then (
		MessageBox "You need to 'copy' before you can 'paste'"
		return false
	)
	
	b = $selection[1]
	if b == undefined then 
	(
		MessageBox "You must select a bone to paste to"
		return false
	)
	
	while (b.parent != undefined) do b = b.parent

	BuildFullBoneList b
	
	shortlist = for b in g_BoneList where not IsBipedBone b collect b
	
	if (g_BoneTransformKeysList.count != shortlist.count) then (
		MessageBox (
			"The number of bones you are trying to paste ["+
			(g_BoneTransformKeysList.count as string)+
			"]\ndoesn't match the number of bones in this model ["+
			(g_BoneList.count as string)+"]\n") title:"Unable to paste"
		return false
	)

	progressStart "Removing old keys"	

	for j = 1 to shortlist.count do (
	
		progressupdate ((j*100.0)/shortlist.count)
		
		deletekeys shortlist[j].position.keys #allkeys
		deletekeys shortlist[j].rotation.keys #allkeys
		deletekeys shortlist[j].scale.keys #allkeys
		
		braces = "()"
		shortlist[j].position.controller = execute ((g_BoneTransformKeyType[j][1] as string) + braces)
		shortlist[j].rotation.controller = execute ((g_BoneTransformKeyType[j][2] as string) + braces)
		shortlist[j].scale.controller = execute ((g_BoneTransformKeyType[j][3] as string) + braces)
	)

	progressEnd()
	
	progressStart "Pasting new keys"	
	
	for j = 1 to shortlist.count do animate on (	
		progressupdate ((j*100.0)/shortlist.count)
		for p in g_BoneTransformKeysList[j] do
		(
			at time p[1] in coordsys parent shortlist[j].transform = p[2]
		)
	)
	
	progressEnd()

	setUserPropBuffer $selection[1] ("Rest pose info copied from " +sourcefile)

	return true
)


-----------------------------------------------------------------------------------------------------

rollout RestPoseRollout "Bone Utils"  (

    button copy_Rest_but  "Copy Bone Names"	toolTip:"Save bone information to the buffer"
    button paste_Rest_but "Paste Bone Names"	enabled:false toolTip:"Paste bone information from the buffer"
	label  bcount_label 
	label  nstatus_label "Name Buffer Empty"
	label  dummylabel1 
	
    button copy_Resttrans_but  "Copy Non-Bip Pos/Rot"	toolTip:"Save non Biped bone positions/rotations to the buffer"
    button paste_Resttrans_but "Paste Non-Bip Pos/Rot"	enabled:false toolTip:"Paste non Biped bone positions/rotations from the buffer"
	label  tcount_label 
	label  tstatus_label "Pos/Rot Buffer Empty"
	label  dummylabel2
	
    button copy_Restkeys_but  "Copy Non-Bip Keys"	toolTip:"Save non Biped bone position/rotation keys to the buffer"
    button paste_Restkeys_but "Paste Non-Bip Keys"	enabled:false toolTip:"Paste non Biped bone position/rotation keys from the buffer"
	label  kcount_label 
	label  kstatus_label "Pos/Rot Keys Empty"
	label  dummylabel3 
	
	on copy_Rest_but pressed do (
		if CopyBoneInfo() then (
			bcount_label.text = (g_BoneInfoList.count as string + " bones in buffer")
			nstatus_label.text = ("["+(getfilenamefile maxfilename)+"]")
			paste_Rest_but.enabled = true
		)
	)

	on paste_Rest_but pressed do (
		if (PasteBoneInfo nstatus_label.text) then (
			MessageBox "Paste was successful!" title:"Good News"
		)
		else
		(
			MessageBox "Paste FAILED!" title:"Bad News"
		)
	)
	
	on copy_Resttrans_but pressed do (
		if CopyBoneTransform() then (
			tcount_label.text = (g_BoneTransformList.count as string + " bones in buffer")
			tstatus_label.text = ("["+(getfilenamefile maxfilename)+"]")
			paste_Resttrans_but.enabled = true
		)
	)

	on paste_Resttrans_but pressed do (
		if (PasteBoneTransform tstatus_label.text) then (
			MessageBox "Paste was successful!" title:"Good News"
		)
		else
		(
			MessageBox "Paste FAILED!" title:"Bad News"
		)
	)

	on copy_Restkeys_but pressed do (
		MessageBox "This is EXPERIMENTAL\n\nSave before you paste!" title:"Heads Up!"
		if CopyBoneTransformKeys() then (
			kcount_label.text = (g_BoneTransformKeysList.count as string + " bones in buffer")
			kstatus_label.text = ("["+(getfilenamefile maxfilename)+"]")
			paste_Restkeys_but.enabled = true
		)
	)

	on paste_Restkeys_but pressed do (
		MessageBox "This is a REALLY SLOW operation\n\nIt make take several MINUTES to complete" title:"Heads Up!"
		if (PasteBoneTransformKeys kstatus_label.text) then (
			MessageBox "Paste was successful!" title:"Good News"
		)
		else
		(
			MessageBox "Paste FAILED!" title:"Bad News"
		)
	)

	
)	

-----------------------------------------------------------------------------------------------------

fn OpenPoseTools = 
(
	if g_PoseToolFloater != undefined and (classof g_PoseToolFloater) == RolloutFloater then
	(
		closerolloutfloater g_PoseToolFloater
	) 
	g_PoseToolFloater = newRolloutFloater "Pose Tools"  180 450 40 40
	addrollout RestPoseRollout g_PoseToolFloater
)

---******************************************************************************
--- Section 2: Adding a hook to call OpenPoseTools() to the quad menus
---******************************************************************************

--  NOTE: I'm using "Siege Max Pose Tools" as the Category for this example

PrepareCategoryForHousekeeping "Siege Max Pose Tools"

----------------------------------------------------

MacroScript OpenPoseToolkit
ButtonText:"Open Pose Tools"
Category:"Siege Max Pose Tools"
Tooltip:"Open Pose Tools" 
(
	On execute Do  
	(    
	    try
    	(
			OpenPoseTools()
	    )
	    catch
		(
		)
	    return true
	)
)

----------------------------------------------------

fn ExtendQuadMenus = 
(
	fn FindSubMenuItemsByName m searchname = (
		for smi = 1 to m.numItems() do
		(
			local sm = m.getItem smi
			local smt = sm.gettitle()
			if smt == searchname  then
			(
		 			return sm
			)
		)
		return undefined
	)
	
	local dvq ,qm, mn, smi, nsm, nmi

	dvq = menuMan.findQuadMenu "Default Viewport Quad" 
	
	-- Remove any existing menu, so that we can update it
	qm= dvq.getMenu 3
	mn= FindSubMenuItemsByName qm ("Context "+"Siege Max Pose Tools")
	if (mn!= undefined) then qm.RemoveItem mn
	
	mn = menuMan.createMenu ("Context "+"Siege Max Pose Tools") 
	
	 -- Create a sub menu item, so that we can to add it
	smi = menuMan.createSubMenuItem "" mn
	smi.setDisplayFlat true
	qm.AddItem smi -1

	 -- Add an item to the sub menu we just created
		nmi = menuMan.createActionItem "OpenPoseToolkit" "Siege Max Pose Tools"
		mn.AddItem nmi -1

)

----------------------------------------------------
-- Run the quad menu extender we just defined...
ExtendQuadMenus()



