
----------------------------------------------------

PrepareCategoryForHousekeeping "Batch Export Tools"		-- Your UNIQUE category name must go here!

----------------------------------------------------
MacroScript RecursiveExport
ButtonText:"Recursive Batch Exporter"
Category:"Batch Export Tools"
Tooltip:"Export all MAX files" 
(
	fn getExportListRecursive root  = 
	( 
		if root == undefined then return #()
		dir_array = #(root+"/")
		for d in dir_array do join dir_array (GetDirectories (d+"/*")) 
		my_files = #() 
		nlist = #()
		for f in dir_array do 
		(
			tempfiles = (getFiles (f + "m_*.max"))
			join tempfiles (getFiles (f + "a_*.max")) 
			for t in tempfiles do 
			(
				n = getfilenamefile t
				if (finditem nlist n) == 0 then
				(	
					append nlist n
					append my_files t
				)
			)
		)
		my_files 
	)
	
	fn doit = ( 
		spath = (getSavePath caption:"Select a directory to export from...")
		if not (dsQueryBox ("Are you sure you want to export EVERYTHING under\n\n"+spath) title:"Confirm Recursive Export" default:false) then return false
		
		explist = getExportListRecursive spath
		for e in explist do
		(
			try 
			(
				if keyboard.escPressed then exit
				
				sm = silentmode()
				setsilentmode true
				loadmaxfile e
				setsilentmode sm
				select $skinmesh
				
				if ($root == undefined) then
				(
					format "Updating ROOT in %\n" maxfilename
					ResetRootPosMarker()		
				)

				-- If you have any custom macros that you want to apply to each file before export, place them here
				
				-- macros.run "Material Cleanup Tools" "MapMaterialsToShadow"

				max file save

				dsexportselected noprompt:true canstomp:true makepath:true
			)
			catch 
			(
				format "Export failed: %\n" maxfilename
			)
		)
	)
	
  On isVisible return true 
  On isEnabled return true
    
  On execute Do  
  (    
    try
    (
		doit()
    )
    catch()
    
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
			if smt == searchname then
			(
	 			return sm
			)
		)
		return undefined
	)
	
	local dvq ,qm, mn, smi, nsm, nmi

	dvq = menuMan.findQuadMenu "Default Viewport Quad" 
	
	-- Delete all the old quad menu items tied to our context (if they exist)

	qm= dvq.getMenu 3 -- menu 3 is the upper left quad
	
	mn= FindSubMenuItemsByName qm ("Context "+"Batch Export Tools" )
	if (mn!= undefined) then qm.RemoveItem mn
	
	-- Now add in the new quad menu items

	mn = menuMan.createMenu ("Context "+"Batch Export Tools" ) 
	smi = menuMan.createSubMenuItem "" mn -- Create a sub menu item, so that we can add it
	smi.setDisplayFlat true
	qm.AddItem smi -1

	-- Add in a call to the DoSomethingCool surrounded by separators
	
	nmi = menuMan.createSeparatorItem()
	mn.AddItem nmi -1
	nmi = menuMan.createActionItem "RecursiveExport" "Batch Export Tools" 
	mn.AddItem nmi -1
	nmi = menuMan.createSeparatorItem()
	mn.AddItem nmi -1
	
			
)

----------------------------------------------------
-- Run the quad menu extender we just defined...
ExtendQuadMenus()