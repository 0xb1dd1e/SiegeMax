----------------------------------------------------
--
-- FILE: InstallSiegeRig.ms
--
-- Loads the SiegeRig tools (a Character Studio style rig for gmax)
-- and defines the "SiegeRig" macro.
--
-- Files loaded:
--   plugins/SiegeRigCOM.ms     the COM helper object
--   RigTools/RigBuilder.ms     promote skeleton, roles, Figure Mode
--
-- To use: Customize > Customize User Interface > Toolbars (or Quad Menus),
-- category "Siege Rig Tools", action "SiegeRig".
--
----------------------------------------------------

PrepareCategoryForHousekeeping "Siege Rig Tools"

scriptdir = GetDir #scripts
if ProductIs3dsMax() then scriptdir += "/SiegeMax"

fileIn (scriptdir+"/plugins/SiegeRigCOM.ms")
fileIn (scriptdir+"/RigTools/RigBuilder.ms")

----------------------------------------------------
global g_SiegeRigFloater

rollout SiegeRigMain "SiegeRig"
(
	group "Rig"
	(
		button btnPromote "Promote Selected Skeleton" width:150
		button btnSelectCOM "Select COM" width:150
	)

	group "Figure Mode"
	(
		checkbutton chkFigure "Figure Mode" width:150 highlightColor:(color 255 170 0)
		button btnReset "Reset To Rest Pose" width:150
		button btnRecapture "Re-capture Rest Pose" width:150
	)

	group "Bone Roles"
	(
		dropdownlist ddRole "" width:150 items:srRoleList
		button btnAssign "Assign To Selected Bone" width:150
		button btnDump "Print Role Map" width:150
	)

	label lblStatus "" align:#left

	fn RefreshUI =
	(
		local com = srFindCOM()
		local hasRig = (com != undefined)
		btnSelectCOM.enabled = hasRig
		chkFigure.enabled = hasRig
		btnReset.enabled = hasRig
		btnRecapture.enabled = hasRig
		btnAssign.enabled = hasRig
		btnDump.enabled = hasRig
		btnPromote.enabled = not hasRig

		if hasRig then
		(
			chkFigure.checked = com.figureMode
			local named = 0
			for r in com.boneRoles do (if r != "" then named += 1)
			lblStatus.text = (com.boneNames.count as string) + " bones, " + (named as string) + " with roles"
		)
		else
		(
			chkFigure.checked = false
			lblStatus.text = "No rig in this scene"
		)
	)

	on SiegeRigMain open do RefreshUI()

	on btnPromote pressed do
	(
		local sel = undefined
		if selection.count > 0 then sel = selection[1]
		srPromoteSkeleton sel
		RefreshUI()
	)

	on btnSelectCOM pressed do
	(
		local com = srFindCOM()
		if com != undefined then select com
	)

	on chkFigure changed state do
	(
		local com = srFindCOM()
		if com != undefined then
		(
			if state then srEnterFigureMode com
			else srExitFigureMode com
		)
		RefreshUI()
	)

	on btnReset pressed do
	(
		local com = srFindCOM()
		if com != undefined then
		(
			if com.figureMode or (dsQueryBox "Move all bones back to the stored rest pose?" default:false) then
				srApplyRest com
		)
	)

	on btnRecapture pressed do
	(
		local com = srFindCOM()
		if com != undefined then
		(
			if dsQueryBox "Replace the stored rest pose with the bones' current frame 0 pose?" default:false then
				srCaptureRest com
		)
	)

	on btnAssign pressed do
	(
		local com = srFindCOM()
		if com != undefined and selection.count > 0 then
		(
			if not (srSetRole com selection[1].name ddRole.selected) then
				messageBox "That bone is not part of the rig" title:"SiegeRig"
			RefreshUI()
		)
	)

	on btnDump pressed do
	(
		local com = srFindCOM()
		if com != undefined then srDumpRoles com
	)
)

fn OpenSiegeRig =
(
	-- the old floater may already have been closed by the user
	try (closeRolloutFloater g_SiegeRigFloater) catch ()

	g_SiegeRigFloater = newRolloutFloater "SiegeRig" 190 420
	addRollout SiegeRigMain g_SiegeRigFloater
)

----------------------------------------------------
MacroScript SiegeRig
ButtonText:"SiegeRig"
Category:"Siege Rig Tools"
Tooltip:"Open the SiegeRig panel"
(
	On isVisible return true
	On isEnabled return true

	On execute Do
	(
		try
		(
			OpenSiegeRig()
		)
		catch()
		return true
	)
)
