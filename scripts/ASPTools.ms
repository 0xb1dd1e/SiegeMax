
GLOBAL gASPToolsFloater
GLOBAL gASPPopUp

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
rollout fltrASPRenderFlags "Render Flags" width:203 height:75
(
	checkbox chkUseAlphaCutoff "Use Alpha Cutoff" pos:[13,7] width:123 height:18
	checkbox chkTextureWAlpha "Use Vertex Alpha (W coord)" pos:[13,30] width:190 height:18
	checkbox chkDisableLighting "Disable Lighting" pos:[13,53] width:120 height:18
							
	fn SetEnabled flg =
	(
		chkUseAlphaCutoff.enabled = flg 
		chkTextureWAlpha.enabled = flg 
		chkDisableLighting .enabled = flg 	
	)
	
	on fltrASPRenderFlags open do
	(		
		b = (bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT) == $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT
		chkUseAlphaCutoff.checked = b
		
		b =(bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT) == $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT
		chkTextureWAlpha.checked = b
		
		b =(bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT) == $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT
		chkDisableLighting.checked = b 
	)
	on fltrASPRenderFlags create do
	(
		b = (bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT) == $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT
		chkUseAlphaCutoff.checked = b
		
		b =(bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT) == $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT
		chkTextureWAlpha.checked = b
		
		b =(bit.and $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT) == $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT
		chkDisableLighting.checked = b 
	)
	on chkUseAlphaCutoff changed val do
	(	
		if chkUseAlphaCutoff.checked then
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.or $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT
		)
		else
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.and $.Modifiers["Siege Max ASP"].RenderFlags (bit.not $.Modifiers["Siege Max ASP"].STENCIL_ALPHA_BIT)
		)
	)
	on chkTextureWAlpha changed val do
	(
		if chkTextureWAlpha.checked then
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.or $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT
		)
		else
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.and $.Modifiers["Siege Max ASP"].RenderFlags (bit.not $.Modifiers["Siege Max ASP"].VERTEX_ALPHA_BIT)
		)
	)
	on chkDisableLighting changed val do
	(
		if chkDisableLighting.checked then
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.or $.Modifiers["Siege Max ASP"].RenderFlags $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT
		)
		else
		(
			$.Modifiers["Siege Max ASP"].RenderFlags = bit.and $.Modifiers["Siege Max ASP"].RenderFlags (bit.not $.Modifiers["Siege Max ASP"].DISABLE_LIGHTING_BIT)
		)
	)
)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
rollout fltrASPSubMesh "Sub Mesh Tools" width:200 height:231
(
	checkbutton ckbHead "head" pos:[44,8] width:40 height:24
	checkbutton ckbHand "hand" pos:[86,8] width:40 height:24
	checkbutton ckbFeet "feet" pos:[128,8] width:40 height:24
	
	label lblNumFaces "Sub Mesh Face Count: <no selection>"
	
	button btnAddSel "Add Selected Faces"
	button btnDelSel "Remove Selected Faces"
	button btnClearAll "Remove All Faces"
	
	--------------------------	
	-- Local functions
	--------------------------	
	
	fn SetEnabled flg =
	(
	
		clobber = false
		try 
		(
		clobber = (not flg) and (ckbHead.checked or ckbHand.checked or ckbFeet.checked)
		)
		catch
		(
		format "error determining clobber!\n"
		)

		if clobber then
		(
			ckbHead.checked = false
			ckbHand.checked = false
			ckbFeet.checked = false
			try 
			(
				dsSetMeshSelected $.'Siege Max ASP' #{} 3
				SetSelectFaceMode false
			)
			catch ()
			newlbl = "Sub Mesh Face Count: <no selection>"
			lblNumFaces.text = newlbl
		)
		
		lblNumFaces.enabled = flg 
		btnAddSel.enabled = flg 
		btnDelSel.enabled = flg 	
		btnClearAll.enabled = flg 	
		
		ckbHead.enabled = flg 
		ckbHand.enabled = flg
		ckbFeet.enabled = flg
	)
	
	fn GetMeshBits =
	(
		if (ckbHead.checked) then return $.Modifiers["Siege Max ASP"].tHeadBits	
		else if (ckbHand.checked) then return $.Modifiers["Siege Max ASP"].tHandBits 
		else if (ckbFeet.checked) then return $.Modifiers["Siege Max ASP"].tFeetBits
		else return #{}
	)

	fn SetMeshBits bits =
	(
		if (ckbHead.checked) then $.Modifiers["Siege Max ASP"].tHeadBits	= bits 
		else if (ckbHand.checked) then $.Modifiers["Siege Max ASP"].tHandBits = bits 
		else if (ckbFeet.checked) then $.Modifiers["Siege Max ASP"].tFeetBits = bits 
	)
	
	fn GetMeshFaceList =
	(
		if (ckbHead.checked) then return $.Modifiers["Siege Max ASP"].HeadFaceList	
		else if (ckbHand.checked) then return $.Modifiers["Siege Max ASP"].HandFaceList 
		else if (ckbFeet.checked) then return $.Modifiers["Siege Max ASP"].FeetFaceList
		else return #()
	)

	fn SetMeshFaceList flist =
	(
		if (ckbHead.checked) then $.Modifiers["Siege Max ASP"].HeadFaceList = flist 
		else if (ckbHand.checked) then $.Modifiers["Siege Max ASP"].HandFaceList = flist 
		else if (ckbFeet.checked) then $.Modifiers["Siege Max ASP"].FeetFaceList = flist 
	)

	fn SetSelectFaceMode flg = (
		if flg then
		(
			max modify mode 
			-- Enter sel face mode
			SafeSetSubObjectLevel 3
		)
		else
		(
			-- Leave sel face mode
			SafeSetSubObjectLevel 0
		)
		completeredraw()
	)
	
	fn SetSelectedFaces flg = (

		dsSetMeshSelected $.'Siege Max ASP' (GetMeshBits()) 3

		if flg then
		(
			newlbl = "Sub Mesh Face Count: " + ($.selectedfaces.count as string)
		)
		else
		(
			newlbl = "Sub Mesh Face Count: <no selection>"
		)
		lblNumFaces.text = newlbl
	)	
	
	on fltrASPSubMesh open do
	(
		newlbl = "Sub Mesh Faces:  <no selection>"
		lblNumFaces.text = newlbl
	)
	on ckbHead changed newstate do
	(
		oldstate = ckbHand.checked or ckbFeet.checked
		if oldstate then
		(
			ckbHand.checked = false
			ckbFeet.checked = false
		)
		SetSelectFaceMode newstate
		SetSelectedFaces (oldstate or newstate)
	)
	on ckbHand changed newstate do
	(
		oldstate = ckbHead.checked or ckbFeet.checked
		if oldstate then
		(
			ckbHead.checked = false
			ckbFeet.checked = false
		)
		SetSelectFaceMode newstate
		SetSelectedFaces (oldstate or newstate)
	)
	on ckbFeet changed newstate do
	(
		oldstate = ckbHead.checked or ckbHand.checked
		if oldstate then
		(
			ckbHead.checked = false
			ckbHand.checked = false
		)
		SetSelectFaceMode newstate
		SetSelectedFaces (oldstate or newstate)
	)
	on btnAddSel pressed do
	(
		bits = GetMeshBits() + (getfaceselection $)
	
		SetMeshBits bits 
		SetMeshFaceList (bits as array)
		SetSelectedFaces true
	)
	on btnDelSel pressed do
	(
		bits = GetMeshBits() * ( -(getfaceselection $) )
		
		SetMeshBits bits 
		SetMeshFaceList (bits as array)
		SetSelectedFaces true
	)
	on btnClearAll pressed do
	(
		SetMeshBits #{} 
		SetMeshFaceList #()
		SetSelectedFaces true
	)
)

--------------------------------------------------------------------------------
fn SelectedHasAnASPModifier = 
(
	try
	(		
		return $selection[1].modifiers["Siege Max ASP"] != undefined
	)
	catch ()
	return false
)

--------------------------------------------------------------------------------
fn ASPPopUpSetEnabled flg =
(
	--try 
	(
		if gASPToolsFloater != undefined then
		(
			fltrASPSubMesh.SetEnabled flg
			fltrASPRenderFlags.SetEnabled flg
		)
	)
	--catch
	--(
	--	format "Caught error in ASPPopUpSetEnabled()\n"
	--)
)

--------------------------------------------------------------------------------
fn ASPPopUpSelectionUpdate =
(
	if gASPToolsFloater != undefined then
	(
		if ($selection.count == 1) then
		(
			if SelectedHasAnASPModifier() then
			(
				ASPPopUpSetEnabled true
				return true
			)
		)
		ASPPopUpSetEnabled false
		return true
	)
	
)

fn gASPPopUp =
(
	if (classof gASPToolsFloater) == RolloutFloater then
	(
		closeRolloutFloater gASPToolsFloater
	)
	if ($selection.count == 1) then
	(
		if SelectedHasAnASPModifier() then
		(
			gASPToolsFloater = newRolloutFloater "ASP Tool Kit" 240 320
			addRollout fltrASPSubMesh gASPToolsFloater
			addRollout fltrASPRenderFlags gASPToolsFloater
			ASPPopUpSetEnabled true
			return true
		)
	)
	ASPPopUpSetEnabled false
	return true
)


callbacks.RemoveScripts id:#ASPPOPUP 
callbacks.AddScript #selectionSetChanged  "ASPPopUpSelectionUpdate()" id:#ASPPOPUP



