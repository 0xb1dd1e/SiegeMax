-------------------------------------------------------------------------------------------------------------
--
-- A simple script to use as an example for adding customized quad menus
--
-- Copy this file into the gmax/gamepacks/SiegeMax/Scripts/Add-Ons folder to access the buttons it defines
-- 
-------------------------------------------------------------------------------------------------------------
--
-- RULES FOR MACROSCRIPT HOUSEKEEPING
--
-- If you make a copy this file in order to modify it for a different purpose you MUST search and replace
-- each and every instance of the string "Siege Max Sample Tools" in the file with something unique.
--
-- Like it or not, every time you execute a MacroScript definition, an MCR file that contains
-- a copy of that definition is created (or updated, if it already exists) in the UI folder. During 
-- development of a new tool and the creation a new category of MacroScripts, it's easy end up with a lot of 
-- 'stale' old definitions of aborted attempts hanging around.
--
-- The "MacroScripts for New Users" category of the online maxscript help talks about this problem.
--
-- The rotten thing about the way that automatic UI macroscript management works it you have to remove
-- any macroscripts that you DON'T want anymore by hand. To work around this I set up an system of 
-- housekeepers that delete and rebuild the UI macroscripts every time gmax is launched.
--
-- In order for "macroscript housecleaning" to work you MUST change the "Siege Max Sample Tools"
-- category to something unique to your Add-On. Use something nice and long and obvious so that your category
-- cannot be confused with any existing category in the gmax/UI/Macroscripts.
--
-- Whatever you do, DO NOT USE "Macro" OR "Siege Max Tools" as your category name!!! 
--
-- "Macro" and "DragAndDrop" are both used by gmax itself, mess around with them and you are bound to corrupt your 
-- gmax installation!
--
-- "Siege Max Tools" is reserved for the core Siege Max Tool set
--
-- If you are interested, look at gmax/gamepacks/SiegeMax/Scripts/QuadMenus.ms to see how Housekeeping 
-- is initialized
--
-- 	.biddle
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------

PrepareCategoryForHousekeeping "Siege Max Sample Tools"		-- Your UNIQUE category name must go here!

----------------------------------------------------
MacroScript DoSomethingCool
ButtonText:"Do Something Cool"
Category:"Siege Max Sample Tools"
Tooltip:"Do Something Cool" 
(
  On isVisible return true 
  On isEnabled return true
    
  On execute Do  
  (    
    try
    (
		MessageBox "You can do something cool here!"
    )
    catch()
    
    return true
  )
  
)

----------------------------------------------------
MacroScript DoSomethingEvenCooler
ButtonText:"Do Something Even Cooler"
Category:"Siege Max Sample Tools" 
Tooltip:"Do Something Even Cooler" 
(
	On isVisible return true 
	On isEnabled return true
  
	On execute Do  
	(    
		try
	    (
			MessageBox "You can do something even cooler here!"
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
	
	mn= FindSubMenuItemsByName qm ("Context "+"Siege Max Sample Tools" )
	if (mn!= undefined) then qm.RemoveItem mn
	
	-- Now add in the new quad menu items

	mn = menuMan.createMenu ("Context "+"Siege Max Sample Tools" ) 
	smi = menuMan.createSubMenuItem "" mn -- Create a sub menu item, so that we can add it
	smi.setDisplayFlat true
	qm.AddItem smi -1

		-- Add in a call to the DoSomethingCool surrounded by separators
		
		nmi = menuMan.createSeparatorItem()
		mn.AddItem nmi -1
		nmi = menuMan.createActionItem "DoSomethingCool" "Siege Max Sample Tools" 
		mn.AddItem nmi -1
		nmi = menuMan.createSeparatorItem()
		mn.AddItem nmi -1
		
		-- Make a sub-menu with that calls the even cooler stuff
		
		nsm = menuMan.createMenu "More Cool Stuff" 
		nsmi = menuMan.createSubMenuItem "" nsm -- Create a sub-sub menu item, so that we can add it
		mn.AddItem nsmi -1
			nmi = menuMan.createActionItem "DoSomethingEvenCooler" "Siege Max Sample Tools" 
			nsm.AddItem nmi -1
			
)

----------------------------------------------------
-- Run the quad menu extender we just defined...
ExtendQuadMenus()