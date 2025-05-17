global dsglb_CriticalEvents = #(
		#("BEGL",	"Begin Loop"		, false),
		#("ENDL",	"End Loop"			, false),
		#("LFDN",	"Left Foot Down"	, true),
		#("LFUP",	"Left Foot Up"		, false),
		
		#("RFDN",	"Right Foot Down"	, true),
		#("RFUP",	"Right Foot Up"		, false),
		
		#("SFX1",	"Special Effect 1"	, true),
		#("SFX2",	"Special Effect 2"	, true),
		#("SFX3",	"Special Effect 3"	, true),
		#("SFX4",	"Special Effect 4"	, true),
		
		#("BSWG",	"Begin Swing/Cast"	, true),
		#("ESWG",	"End Swing/Cast"	, true),
		
		#("FIRE",	"Fire/Strike with Weapon"	, true),
		#("DEAD",	"Die/Explode"				, true),
		
		#("ATTA",	"Attach Ammo"		, true),
		
		#("HIDE",	"Hide Mesh"			, true),
		#("SHOW",	"Show Mesh"			, true))
		
global dsglb_CriticalEventFourCC = for i in dsglb_CriticalEvents collect i[1]
global dsglb_CriticalEventNames  = for i in dsglb_CriticalEvents collect i[2]

global dsglb_CriticalEventFourCCMenu = for i in dsglb_CriticalEvents where i[3] collect i[1]
global dsglb_CriticalEventNamesMenu  = for i in dsglb_CriticalEvents where i[3] collect i[2]

global dsglb_CritPointTrackName = "CriticalEvents"


----------------------------------------------------------------------------------------------------
fn	FetchSkinMesh = (

	try (
	
		local fname = maxfilename
		if fname[1] != "a" or fname[2] != "_" then return undefined
		
		if ($skinmesh == undefined) and ($selection.count != 1) then return undefined

		if ($skinmesh == undefined) then
		(
			local nm = dsLowerCase $selection[1].name
			if  (findstring nm "m_" == 1) and (canConvertTo $selection[1] Editable_Mesh) then 
			(
				return $selection[1]
			)
		)
		else
		(
			if (canConvertTo $skinmesh Editable_Mesh) then 
			(
				return $skinmesh
			)
		)			
 			
	) 
	
	catch()
	
	return undefined
)


----------------------------------------------------------------------------------------------------
fn ListCriticalEvents = (

	CritEventObj = FetchSkinMesh()
	if (CritEventObj  == undefined) then (
		MessageBox "You need an animatable object"
		return false
	)
	
	if (numnotetracks CritEventObj == 0) then
 	(
		MessageBox "There are no events defined for this animation"
		return false
	)
	else 
	(
		for t = (numnotetracks CritEventObj)+1 to dsglb_CriticalEvents.count do (
			addNoteTrack CritEventObj (notetrack dsglb_CriticalEventNames[t][1])
		)
	)

	local msglines = #()
	local msg = stringstream ""

	local sections = (animationrange.end - animationrange.start) / 100.0
	
	if (floor sections != sections) then
	(
		sections = (floor sections) + 1
	)
	
	for s = animationrange.start to animationrange.end by 17 do 
	(
		append msglines (msg as string) ; msg = stringstream ""
		
		e = if (s+16) < animationrange.end then (s+16) else animationrange.end

		for t = s to e do (
			if (t > 999) then (
				format "|%" ((t/ticksperframe) as integer) to:msg
			) else if (t > 99) then (
				format "|%" t to:msg
			) else if (t > 9) then (
				format "|% " t to:msg
			) else (
				format "| % " t to:msg
			)
		)
		format "|" to:msg
		
		append msglines (msg as string) ; msg = stringstream ""
		
		for trk = 1 to dsglb_CriticalEvents.count do (
		
			nt = getNoteTrack CritEventObj trk
	
			for t = s to e do (
				
				nki =  getnotekeyindex nt t
				if (nki != undefined) then (
					format "|%" dsglb_CriticalEvents[trk][1] to:msg
				) else (
					format "|    " to:msg
				) 
			)
			
			format "|" to:msg
			append msglines (msg as string) ; msg = stringstream ""
		)
		append msglines (msg as string) ; msg = stringstream ""
		append msglines (msg as string) ; msg = stringstream ""	
	)
		
	
	format "Events for: %" (getfilenamefile (maxfilename)) to:msg
	dsDisplayReport (msg as string) msglines

 	-- noteinfo = stringstream ""
	-- format (msg as string) to:noteinfo
  	-- MessageBox noteinfo
)

----------------------------------------------------------------------------------------------------
fn ClearCrititalEvents = (

	CritEventObj = FetchSkinMesh()
	if (CritEventObj  == undefined) then (
		MessageBox "You need an animatable object"
		return false
	)
	
	if (numnotetracks CritEventObj == 0) then
 	(
		MessageBox "There are no events defined for this animation"
		return false
	)
	else 
	(
		if (QueryBox ("Clear all critical events?")) then (
			for trk = 1 to dsglb_CriticalEvents.count do (
				nt = getNoteTrack CritEventObj trk
				deleteNoteKeys nt.keys #allkeys
			)
		)
	)
)

----------------------------------------------------------------------------------------------------
fn AddCriticalEventToNoteTrack timeval fourcc trk = (

	CritEventObj = FetchSkinMesh()
	if (CritEventObj  == undefined) then (
		MessageBox "You need an animatable object"
		return false
	)
	
	critpointtrackname = "CriticalEvents"
	
	if (numnotetracks CritEventObj == 0) then (
		for t = 1 to dsglb_CriticalEvents.count do (
			addNoteTrack CritEventObj (notetrack dsglb_CriticalEventNames[t][1])
		)
	)
	else 
	(
		for t = (numnotetracks CritEventObj)+1 to dsglb_CriticalEvents.count do (
			addNoteTrack CritEventObj (notetrack dsglb_CriticalEventNames[t][1])
		)
	)

	nt = getNoteTrack CritEventObj trk
	
	nki =  getnotekeyindex nt timeval
	if (nki == undefined) then (
		nk = addNewNoteKey nt.keys timeval
	) else (
		nk = nt.keys[nki]
	)
	
	nk.value = fourcc
	nk.selected = true
	
)

----------------------------------------------------------------------------------------------------
fn DeleteCriticalEventsFromNoteTrack trk = (

	CritEventObj = FetchSkinMesh()
	if (CritEventObj  == undefined) then (
		MessageBox "You need an animatable object"
		return false
	)

	nt = getNoteTrack CritEventObj trk
	deleteNoteKeys nt.keys #allkeys
)

----------------------------------------------------------------------------------------------------
fn HasLoopEventAtAnimEnd obj = (

	if (obj == undefined or dsglb_CriticalEvents == undefined) then (return false)
	if (numnotetracks obj != dsglb_CriticalEvents.count) then ( return false )
	
	nt = getNoteTrack obj  2

	nki =  getnotekeyindex nt animationrange.end
	
	return nki != undefined

)

----------------------------------------------------------------------------------------------------
fn AddBegEndEvents = (

	try (
		
		CritEventObj = FetchSkinMesh()
		if (CritEventObj  == undefined) then (
			MessageBox "You need an animatable object"
			return false
		)
	
		AddCriticalEventToNoteTrack animationrange.start dsglb_CriticalEvents[1][1] 1
		AddCriticalEventToNoteTrack animationrange.end dsglb_CriticalEvents[2][1] 2
		
	) catch (return false)
	
	return true
)		
	
----------------------------------------------------------------------------------------------------
fn DeleteBegEndEvents = (

	try (
		
		CritEventObj = FetchSkinMesh()
		if (CritEventObj  == undefined) then (
			MessageBox "You need an animatable object"
			return false
		)
	
		DeleteCriticalEventsFromNoteTrack 1
		DeleteCriticalEventsFromNoteTrack 2
		
	) catch (return false)
	
	return true
)		
	
----------------------------------------------------------------------------------------------------
rollout CriticalEventsFloater "Critical Events"  (

	listbox AddCritical "Add Critical Event" text:"" items:dsglb_CriticalEventNamesMenu height:(dsglb_CriticalEventNamesMenu.count)
	listbox DelCritical "Remove Critical Events" text:"" items:dsglb_CriticalEventNamesMenu height:(dsglb_CriticalEventNamesMenu.count)
	button DisplayCrit "List Critical Events" 
	button ClearCrit "Clear Critical Events"

	on AddCritical doubleclicked it do (
		i = finditem dsglb_CriticalEventFourCC dsglb_CriticalEventFourCCMenu[it]
		if (QueryBox ("Add "+dsglb_CriticalEventNames[i] + " at key " + currenttime as string)) then (
			AddCriticalEventToNoteTrack currenttime dsglb_CriticalEventFourCC[i] i
		) else (
		)
	)

	on DelCritical doubleclicked it do (
		i = finditem dsglb_CriticalEventFourCC dsglb_CriticalEventFourCCMenu[it]
		if (QueryBox ("Delete all "+dsglb_CriticalEventNames[i] + " events?")) then (
			DeleteCriticalEventsFromNoteTrack i
		) else (
		)
	)

	on DisplayCrit pressed do (
		ListCriticalEvents() 
	)

	on ClearCrit pressed do (
		ClearCrititalEvents()
	)
)