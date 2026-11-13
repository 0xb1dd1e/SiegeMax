----------------------------------------------------
--
-- FILE: RigBuilder.ms
--
-- SiegeRig phase 1: promote an existing Dungeon Siege skeleton into a
-- SiegeRig, detect bone roles, store the rest pose, and provide Figure
-- Mode. Requires plugins/SiegeRigCOM.ms to be loaded first.
--
-- Nothing here relinks, renames or re-controls any bone, so a promoted
-- skeleton still exports exactly as before.
--
----------------------------------------------------

global SIEGERIG_VERSION = 1

-- Figure Mode bookkeeping (restored if the scene was saved mid-session)
global srSavedFigureTime = 0
global srSavedAnimState = false

global srRoleList = #("", "pelvis", "spine", "neck", "head", \
	"L_clavicle", "R_clavicle", "L_upperarm", "R_upperarm", \
	"L_forearm", "R_forearm", "L_hand", "R_hand", \
	"L_thigh", "R_thigh", "L_calf", "R_calf", \
	"L_foot", "R_foot", "L_toe", "R_toe", "L_pin", "R_pin", \
	"weapon_grip", "shield_grip", "finger")

----------------------------------------------------
-- String helpers
----------------------------------------------------
fn srContains s sub =
(
	return ((findString s sub) != undefined)
)

fn srStartsWith s p =
(
	if s.count < p.count then return false
	return ((substring s 1 p.count) == p)
)

fn srEndsWith s p =
(
	if s.count < p.count then return false
	return ((substring s (s.count - p.count + 1) p.count) == p)
)

fn srHasToken toks t =
(
	return ((findItem toks t) != 0)
)

----------------------------------------------------
-- Role detection from a bone name
--
-- Returns "" when the name is not recognised. Sided parts need a clear
-- side, otherwise the role is left blank so the user can assign it.
----------------------------------------------------
fn srDetectSide lname toks =
(
	if (srHasToken toks "l") or (srHasToken toks "left") then return "L"
	if (srHasToken toks "r") or (srHasToken toks "right") then return "R"
	if srStartsWith lname "left" then return "L"
	if srStartsWith lname "right" then return "R"

	-- names like "lthigh" / "rhand": one side letter then a part word
	local parts = #("thigh", "calf", "foot", "upperarm", "forearm", "hand", "clavicle", "toe")
	if lname.count < 2 then return ""
	local c = substring lname 1 1
	local rest = substring lname 2 (lname.count - 1)
	local p
	for p in parts do
	(
		if srStartsWith rest p then
		(
			if c == "l" then return "L"
			if c == "r" then return "R"
		)
	)
	return ""
)

fn srDetectRole boneName =
(
	local lname = dsLowerCase boneName
	local toks = filterString lname "_ .-"
	local side = srDetectSide lname toks
	local part = ""

	if srContains lname "grip" then
	(
		if srContains lname "weapon" then return "weapon_grip"
		if srContains lname "shield" then return "shield_grip"
		return ""
	)

	if (srHasToken toks "pin") or (srEndsWith lname "pin") then part = "pin"
	else if (srContains lname "finger") or (srContains lname "thumb") then return "finger"
	else if srContains lname "toe" then part = "toe"
	else if srContains lname "clavicle" then part = "clavicle"
	else if srContains lname "forearm" then part = "forearm"
	else if srContains lname "upperarm" then part = "upperarm"
	else if srContains lname "thigh" then part = "thigh"
	else if srContains lname "calf" then part = "calf"
	else if srContains lname "foot" then part = "foot"
	else if srHasToken toks "hand" then part = "hand"
	else if srContains lname "pelvis" then return "pelvis"
	else if srContains lname "spine" then return "spine"
	else if srContains lname "neck" then return "neck"
	else if srHasToken toks "head" then return "head"
	else return ""

	if side == "" then return ""
	return (side + "_" + part)
)

----------------------------------------------------
-- Finding things
----------------------------------------------------
fn srFindCOM =
(
	local found = undefined
	for o in objects while found == undefined do
	(
		if (classOf o) == SiegeRigCOM then found = o
	)
	return found
)

fn srTopOf node =
(
	local n = node
	while n.parent != undefined do n = n.parent
	return n
)

fn srCollectHierarchy node list =
(
	append list node
	for c in node.children do srCollectHierarchy c list
)

fn srNodeIsAnimated n =
(
	local a = false
	try
	(
		if n.position.isAnimated or n.rotation.isAnimated then a = true
	)
	catch ()
	return a
)

fn srCountAnimated com =
(
	local count = 0
	local n
	for nm in com.boneNames do
	(
		n = getNodeByName nm exact:true
		if n != undefined then
		(
			if srNodeIsAnimated n then count += 1
		)
	)
	return count
)

----------------------------------------------------
-- Rest pose storage: 7 floats per bone (pos xyz, quat xyzw), parent space
----------------------------------------------------
fn srCaptureRest com onlyUnanimated:false =
(
	local names = com.boneNames
	local old = com.restData
	local data = #()
	local i, j, n, p, q, o

	at time 0
	(
		for i = 1 to names.count do
		(
			o = (i - 1) * 7
			n = getNodeByName names[i] exact:true

			if n == undefined then
			(
				-- missing bone: keep what we had, or an identity placeholder
				if old.count >= o + 7 then
				(
					for j = 1 to 7 do append data old[o + j]
				)
				else
				(
					join data #(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
				)
			)
			else if onlyUnanimated and (srNodeIsAnimated n) and (old.count >= o + 7) then
			(
				-- animated bone: frame 0 is not the rest pose, keep the stored one
				for j = 1 to 7 do append data old[o + j]
			)
			else
			(
				p = (in coordsys parent n.position)
				q = (in coordsys parent n.rotation)
				join data #(p.x, p.y, p.z, q.x, q.y, q.z, q.w)
			)
		)
	)
	com.restData = data
	return data.count / 7
)

fn srApplyRest com =
(
	local names = com.boneNames
	local d = com.restData
	local i, n, o

	if d.count < names.count * 7 then return false

	at time 0 animate off
	(
		for i = 1 to names.count do
		(
			o = (i - 1) * 7
			n = getNodeByName names[i] exact:true
			if n != undefined then
			(
				-- auto-aligned bones take their rotation from their children
				local autoAligned = false
				if (isProperty n #boneAutoAlign) then autoAligned = n.boneAutoAlign

				if not autoAligned then
					in coordsys parent n.rotation = (quat d[o+4] d[o+5] d[o+6] d[o+7])
				in coordsys parent n.position = [d[o+1], d[o+2], d[o+3]]
			)
		)
	)
	return true
)

----------------------------------------------------
-- Promote an existing skeleton
----------------------------------------------------
fn srPromoteSkeleton picked =
(
	if picked == undefined then
	(
		messageBox "Select any bone of the skeleton first" title:"SiegeRig"
		return undefined
	)
	if (srFindCOM()) != undefined then
	(
		messageBox "This scene already has a SiegeRig COM" title:"SiegeRig"
		return undefined
	)

	local top = srTopOf picked
	local nodes = #()
	srCollectHierarchy top nodes

	local names = #()
	local roles = #()
	local n
	for n in nodes do
	(
		append names n.name
		append roles (srDetectRole n.name)
	)

	local com = undefined
	undo "Promote to SiegeRig" on
	(
		com = SiegeRigCOM name:"SiegeRig_COM" comSize:60 pos:top.position
		com.boneNames = names
		com.boneRoles = roles
		com.rigVersion = SIEGERIG_VERSION
		srCaptureRest com
	)

	local animated = srCountAnimated com
	if animated > 0 then
	(
		local msg = "Rest pose captured from frame 0.\n\n"
		msg += (animated as string) + " bones are animated, so frame 0 may not be the true rest pose.\n"
		msg += "Re-capture it after resetting the character to its rest pose."
		messageBox msg title:"SiegeRig"
	)
	return com
)

fn srSetRole com boneName role =
(
	local names = com.boneNames
	local idx = findItem names boneName
	if idx == 0 then return false

	local roles = com.boneRoles
	roles[idx] = role
	com.boneRoles = roles
	return true
)

fn srDumpRoles com =
(
	local names = com.boneNames
	local roles = com.boneRoles
	local i
	format "SiegeRig: % bones\n" names.count
	for i = 1 to names.count do
		format "  %  ->  %\n" names[i] (if roles[i] == "" then "(none)" else roles[i])
)

----------------------------------------------------
-- Figure Mode
--
-- Figure Mode turns Animate off and goes to frame 0 so the skeleton can
-- be repositioned. On exit, the rest pose is re-captured from the bones.
-- Bones that carry keys keep their stored rest pose, because frame 0 of
-- an animated bone is not its rest pose.
--
-- Note: with Animate off, moving a keyed bone shifts all of its keys.
-- Figure Mode is meant for rigs with no animation, or for small fixes.
----------------------------------------------------
fn srEnterFigureMode com =
(
	if com.figureMode then return true

	local animated = srCountAnimated com
	if animated > 0 then
	(
		local msg = (animated as string) + " bones in this rig have animation keys.\n\n"
		msg += "In Figure Mode, moving a keyed bone shifts all of its keys,\n"
		msg += "and the stored rest pose of keyed bones will not be updated.\n\n"
		msg += "Enter Figure Mode anyway?"
		if not (dsQueryBox msg default:false) then return false
	)

	srSavedFigureTime = sliderTime
	srSavedAnimState = animButtonState
	animButtonState = false
	sliderTime = 0
	com.figureMode = true
	return true
)

fn srExitFigureMode com =
(
	if not com.figureMode then return true

	srCaptureRest com onlyUnanimated:true
	com.figureMode = false
	animButtonState = srSavedAnimState
	sliderTime = srSavedFigureTime
	return true
)
