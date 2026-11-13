-- ****************************
-- Claude Link: a small always-open dialog for working with Claude
--
-- Top strip (always visible):
--   STATE: RUNNING / PAUSED / STOPPED   - what Claude's helper reads before sending anything
--   [II]  pause Claude (becomes [>] to resume)
--   [X]   EMERGENCY STOP (resume with [>])
--   [-]   shrink to the compact strip ([+] expands again)
-- Conversation rollup (collapsed in compact mode):
--   log of Claude's messages ("[Claude] ...") and yours ("[You] ..."), and a "To Claude"
--   box with Send. Claude reads the log from outside gmax.
--
-- While PAUSED or STOPPED, Claude's helper (gmax_run.ps1) refuses to send anything to gmax.
-- A button cannot interrupt a script that is already running - press Esc in gmax for that.
--
-- Everything for the link lives in this folder (scripts/ClaudeLink/):
--   ClaudeLink.ms  this dialog
--   gmax_run.ps1   the outside helper (sends a line to gmax, reads replies, checks Pause/Stop)
--
-- Open it:  filein ((GetDir #scripts) + "/ClaudeLink/ClaudeLink.ms")
-- Claude writes to it with:  ClaudeSay "message"
-- Claude runs code and gets the result back in the log with:  ClaudeEval 17 "code string"
--   (17 = a request number; the reply line is "[result 17] ..." or "[error 17] ...")
-- Claude restores the window size (gmax lets it drift) with:  ClaudeLinkFix()
-- ****************************

-- Forward declarations: rollout event handlers are compiled before the functions below exist,
-- and an undeclared name inside a handler becomes an (undefined) local variable.
global ClaudeLinkFloater
global ClaudeLinkState = "RUNNING"
global ClaudeLinkMode = "full"
global ClaudeLinkRO
global ClaudeLinkLogRO
global ClaudeLinkSetState
global ClaudeLinkSetMode
global ClaudeLinkTogglePause
global ClaudeLinkStop
global ClaudeLinkSend
global ClaudeLinkFix
global ClaudeLinkLog
global ClaudeSay
global ClaudeEval

-- Window sizes. gmax clamps a new floater to a narrow width (136 px minimum, and it opened
-- 136 px wide although 310 was asked for), which clips the controls. Setting .size again once
-- the rollouts are in place sticks. Dragging a floater wider snaps back in gmax; setting .size
-- from script works for any width from 136 px up.
global ClaudeLinkFullW = 330
global ClaudeLinkFullH = 380
global ClaudeLinkMiniW = 175
global ClaudeLinkMiniH = 125

rollout ClaudeLinkRO "Claude Link"
(
	-- Fixed positions in the left 150 px: the panel keeps the width it was created with (330),
	-- so flowing controls (across:3) would spread out beyond the compact window's edge.
	label lblState "STATE: RUNNING" pos:[8,4]
	button btnPause "II" width:40 height:21 pos:[8,26]
	button btnStop "X" width:40 height:21 pos:[54,26]
	button btnGrow "-" width:40 height:21 pos:[100,26]

	on btnPause pressed do ClaudeLinkTogglePause()
	on btnStop pressed do ClaudeLinkStop()
	on btnGrow pressed do ClaudeLinkSetMode (if ClaudeLinkMode == "full" then "mini" else "full")
)

rollout ClaudeLinkLogRO "Conversation"
(
	edittext edtLog "" height:150 width:270 align:#center
	edittext edtMsg "To Claude: " fieldWidth:200 align:#left
	button btnSend "Send" width:100 align:#right

	on btnSend pressed do ClaudeLinkSend()
	on edtMsg entered txt do ClaudeLinkSend()
)

-- The state lives in a label ("STATE: RUNNING") that the outside helper reads; setting a
-- floater's title silently does nothing in gmax, so the title is only a bonus.
fn ClaudeLinkSetState st =
(
	ClaudeLinkState = st
	try (ClaudeLinkRO.lblState.text = "STATE: " + st) catch ()
	try (ClaudeLinkRO.btnPause.caption = (if st == "RUNNING" then "II" else ">")) catch ()
	try (ClaudeLinkFloater.title = "Claude Link [" + st + "]") catch ()
)

-- Append a line to the transcript (keeps roughly the last 6000 characters)
fn ClaudeLinkLog who msg =
(
	try
	(
		local t = ClaudeLinkLogRO.edtLog.text + "[" + who + "] " + msg + "\r\n"
		if t.count > 6000 then t = substring t (t.count - 5000) -1
		ClaudeLinkLogRO.edtLog.text = t
	)
	catch (format "[%] %\n" who msg)
)

fn ClaudeSay msg = ClaudeLinkLog "Claude" msg

-- Run a code string and put its value (or the error) in the log under request number "id".
-- Use this when the Listener's own output cannot be read (the small mini-listener only shows
-- its last line). Only the returned value is captured, not text printed with format.
fn ClaudeEval id code =
(
	try
	(
		local r = execute code
		ClaudeLinkLog ("result " + (id as string)) (r as string)
	)
	-- gmax (Max 4.2 based) has no getCurrentException(), so the error text cannot be read here.
	-- Run the same line raw (gmax_run.ps1 -Cmd) and the Listener prints the real message.
	catch (ClaudeLinkLog ("error " + (id as string)) "failed - gmax cannot report the message here; run the same line with -Cmd to see it in the Listener")
)

fn ClaudeLinkSend =
(
	local txt = ClaudeLinkLogRO.edtMsg.text
	if txt != "" then
	(
		ClaudeLinkLog "You" txt
		ClaudeLinkLogRO.edtMsg.text = ""
	)
)

fn ClaudeLinkTogglePause =
(
	if ClaudeLinkState == "RUNNING" then
	(
		ClaudeLinkSetState "PAUSED"
		ClaudeLinkLog "system" "PAUSED by user - Claude will not send commands"
	)
	else
	(
		ClaudeLinkSetState "RUNNING"
		ClaudeLinkLog "system" "RUNNING - Claude may send commands again"
	)
)

fn ClaudeLinkStop =
(
	ClaudeLinkSetState "STOPPED"
	ClaudeLinkLog "system" "EMERGENCY STOP - Claude must stop. Press > to allow commands again."
)

fn ClaudeLinkFix =
(
	local w = (if ClaudeLinkMode == "full" then ClaudeLinkFullW else ClaudeLinkMiniW)
	local h = (if ClaudeLinkMode == "full" then ClaudeLinkFullH else ClaudeLinkMiniH)
	try (ClaudeLinkFloater.size = [w, h]) catch ()
	try (ClaudeLinkFloater.size = [w, h]) catch ()
)

-- full = conversation rollup open, compact = only the top strip (the log control still exists
-- while collapsed, so Claude can still read it)
fn ClaudeLinkSetMode m =
(
	ClaudeLinkMode = m
	try (ClaudeLinkLogRO.open = (m == "full")) catch ()
	try (ClaudeLinkRO.btnGrow.caption = (if m == "full" then "-" else "+")) catch ()
	ClaudeLinkFix()
)

fn ClaudeLinkOpen =
(
	try (closeRolloutFloater ClaudeLinkFloater) catch ()
	ClaudeLinkState = "RUNNING"
	ClaudeLinkFloater = newRolloutFloater "Claude Link [RUNNING]" ClaudeLinkFullW ClaudeLinkFullH 20 120
	addRollout ClaudeLinkRO ClaudeLinkFloater
	addRollout ClaudeLinkLogRO ClaudeLinkFloater
	ClaudeLinkSetState "RUNNING"
	ClaudeLinkSetMode ClaudeLinkMode
	ClaudeLinkLog "system" "Claude Link ready"
)

ClaudeLinkOpen()
