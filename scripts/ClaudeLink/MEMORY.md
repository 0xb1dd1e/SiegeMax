# ClaudeLink memory: how to drive gmax (read this first)

Notes for Claude (and anyone else) on talking to a running gmax through the Claude Link
dialog and `gmax_run.ps1`. Everything here was verified against gmax 4.2 build 128 (the
SiegeMax gamepack's gmax, a Max 4.2 base) unless it says otherwise. Add to it when something new is learned.

## Rules of engagement
- **The user is in control.** The dialog's `STATE:` label is the switch. PAUSED, STOPPED, a missing
  dialog or an unreadable state all make the helper print `BLOCKED ...` and exit 2. Stop and wait;
  never work around it (no direct Win32 sends, no keystrokes).
- The helper only uses window messages (no focus changes). Even so the user interrupts anything that
  looks intrusive: say what you are about to do before touching their panes, and restore anything
  you change (the helper restores the mini-listener line and removes lines it adds to the top pane).
- A button can't interrupt a running script. If gmax is busy the helper says so; the user presses Esc.
- Test files and objects you create (scenes, `__test` boxes) must be deleted afterwards.
  `saveMaxFile` renames the user's open scene: tell them to check File > Save As.

## Quick start (from `scripts/ClaudeLink/`)
```
gmax_run.ps1 -Status                 state, which listeners exist, conversation log
gmax_run.ps1 -Open                   load ClaudeLink.ms (needed if the dialog is NOT_OPEN)
gmax_run.ps1 -Say "text"             message in the dialog log (the user reads it there)
gmax_run.ps1 -Read                   the log: the user's messages are the [You] lines
gmax_run.ps1 -Eval '<expr>'          run one expression, get its VALUE back (works with any listener state)
gmax_run.ps1 -Cmd '<line>'           run one raw line; output/errors come from the full Listener's output pane
gmax_run.ps1 -Watch [-Since N]       follow what the user does on screen (macro recorder pane), see below
gmax_run.ps1 -ShowListener | -HideListener | -Restore | -Full | -Timeout N
```
Run it from PowerShell (`powershell`); the `python` in Git Bash has `olefile`, PowerShell's does not
(the piggyback extractor for `.gmax` needs olefile, so run that one from Git Bash).

## Which command to use
- **`-Eval`** is the default. The code runs inside `ClaudeEval`, only the returned value comes back
  (through the dialog log, so it works while the full Listener is closed or minimized). `format`
  output is NOT captured. If the code fails you get `error: failed - ...` with no message.
- **`-Cmd`** runs the line raw: use it to see printed output (`format`, `print`, `apropos`) and the
  real error text (`-- Runtime error: ...`). It needs the full Listener to exist (hidden or minimized
  is fine; the helper also looks at hidden windows). The helper clears the Listener first.
- One line only (join statements with `;`). Strings: the helper escapes `\` and `"` for `-Eval`.
- Return values: end the expression with `as string` for anything that isn't a string.
- Use parentheses `( a; b; c )` for several statements. Don't put `local` inside a one-liner
  `with undo off ( ... )`: it is a syntax error that opens the editor window and gives no reply.
  Use short globals (`__snb = ...`) and delete them / their objects afterwards.

## How it works (so you can debug it)
- Listener window: top-level dialog titled `MAXScript Listener` (class `#32770`). Two RICHEDIT panes,
  control IDs **1002** (upper pane: macro recorder + history, also where lines are put) and
  **1001** (output). The bottom-panel **mini-listener** (no menu) has the same IDs under the 3DSMAX main
  window and its output control only ever holds the last line (`OK`).
- Read text with `WM_GETTEXTLENGTH`/`WM_GETTEXT` via `SendMessageTimeout` (flags SMTO_BLOCK|ABORTIFHUNG,
  so a busy gmax returns "busy" instead of hanging the tool).
- Run a line: put it in the input control (`EM_SETSEL` + `EM_REPLACESEL`) and post a **numpad Enter**
  (`WM_KEYDOWN` VK_RETURN, lParam `0x011C0001`; key-up `0xC11C0001`). Plain Enter only adds a newline.
  Do not insert a bare `\r` after existing `\r\n` text: the evaluator then picks up the wrong text.
- Clear the full Listener: `WM_COMMAND 40043` (Edit > Clear All).
- Open the full Listener: post F11 (`WM_KEYDOWN 0x7A`, lParam `0x00570001`) to the 3DSMAX main window
  (menu: MAXScript > MAXScript Listener, command 57517). Close it with `WM_CLOSE`.
  Posting F11 while it is already open does nothing.
- The dialog state lives in a `label` ("STATE: RUNNING"); a floater's `.title` can't be set in gmax.
- Replies from `-Eval` come back as `[result <id>] ...` / `[error <id>] ...` lines in the dialog log. The
  id is a millisecond clock value (second-resolution ids collided and returned stale replies).

## Following the user: the macro recorder
With MacroRecorder > Enable and "Show menu item selections" ticked in the Listener's menu (they were),
the upper pane receives the MAXScript equivalent of every UI action. `gmax_run.ps1 -Watch` prints the
last 15 lines and `next index: N`; `-Watch -Since N` prints only what was added after N. Lines sent
through the mini-listener appear there too (filter your own). Examples seen:
```
Teapot radius:0 smooth:on segs:4 ...                (object creation)
actionMan.executeAction 0 "40008"                    (a menu command: File > Save Selected)
max file save selected                               (what the menu ran)
```
Menu commands can be read from the menus themselves (`GetMenu`/`GetMenuString`, main window menu bar) and
posted with `WM_COMMAND` to the 3DSMAX window, e.g. File > Save Selected = 57312, Export Selected = 57320,
MAXScript menu: New 57514, Open 57515, Run 57516, Listener 57517, Macro Recorder 57518.

### Recorder options (Listener > MacroRecorder) and what they change in what I can see
Read with `GetMenu`/`GetMenuState` on the Listener window (check state = the mode); toggle with
`WM_COMMAND <id>`. The user changes these, so always read them live. Seen on 2026-11-12 (earlier in the
session the object-name, transform-style and sub-object options were the opposite way round, and
"Show command panel switchings" was ticked):
- `Enable` (40030, on): without it nothing is recorded, so `-Watch` sees nothing. Check it first.
- `Explicit scene object names` (40044, off) vs `Selection-relative scene object names` (40033, on):
  how objects are named in recorded lines (`$Teapot01` vs `selection[1]`). Selection-relative lines
  only make sense together with the current selection.
- `Absolute transform assignments` (40035, off) vs `Relative transforms operations` (40036, on):
  moves/rotates are recorded as `move $x [dx,dy,dz]` rather than `$x.pos = ...`.
- `Explicit sub-object sets` (40037, off) vs `Selection-relative sub-object sets` (40038, on).
- `Show command panel switchings` (40039, off), `Show tool selections` (40040, on),
  `Show menu item selections` (40041, on): the last one is why File > Save Selected and other menu picks
  show up as `actionMan.executeAction 0 "<id>"` / `max ...` lines. With command panel switchings off,
  I will not see the user change tabs.
If a UI action does not show up in `-Watch`, check these options before assuming it was not recorded.

### Learning to read gmax's UI state (long-term, out of scope for now)
The aim is to know what mode gmax is in (command panel tab, active tool, selection level, open dialogs,
which menu items are ticked) by reading window items and their state rather than guessing:
- Menu items: `GetMenu`/`GetMenuState` (checked/disabled) on any window with a classic menu bar.
- Windows and controls: enumerate top-level windows and children; class names seen so far: `3DSMAX`
  (main), `#32770` (dialogs, Listener, floaters), `RICHEDIT`, `Edit`, `CustEdit`, `CustButton`, `Static`,
  `RollupWindow`/`RollupPanel` (rollouts), `GRAY`. Button/Static text via `WM_GETTEXT`; check boxes via
  `BM_GETCHECK`; combo/list selection via `CB_GETCURSEL`/`LB_GETCURSEL`.
- Scripted state: `subObjectLevel`, `getCommandPanelTaskMode()`, `selection`, `maxFileName`, `animate`,
  `timeSlider`, `GetDir`; check each with `apropos` before relying on it in this gmax.
- Sources to study: the gmax help files (`help/maxscript.chm`, `help/gmax.chm`), the online MAXScript
  reference and tutorials, and Microsoft's Win32 / UI Automation documentation for reading controls.

## gmax facts and traps (Max 4.2 base)
- **No `getCurrentException()`**. Calling it inside a `catch` throws a second error; that error is
  raised in a script file, so gmax opens that file's editor window ("<file>.ms - MAXScript") with the
  error location selected (read the selection with `EM_GETSEL`/`EM_GETSELTEXT`). Inside `catch` you can
  only log a fixed message. To see an error message run the code raw with `-Cmd`.
- `saveNodes` exists as a name but fails: `Runtime error: Feature not available: "saveNodes"`.
  `saveSelected` doesn't exist. The File menu does have **Save Selected**, but it only runs the macro
  `max file save selected` and opens a file dialog (no path argument). It writes just the selected
  objects (about 15 KB for a teapot versus the whole scene). Driving that dialog from outside would be
  the way to save payload-only scenes without renaming the open scene; not built.
- `apropos "text"` lists matching names (types and an empty argument list, not real signatures);
  use it to check whether a function exists. Run it with `-Cmd` (the output is printed text).
- `help "Name"` is a built-in MAXScript function that does the same kind of name lookup (it prints
  matching names with an empty `()` signature, e.g. `help "saveNodes"` -> `saveNodes (const Primitive):
  saveNodes()`). It needs a quoted string: unquoted `help help` answers `No Info Found, Example: Help "Box"`,
  and a bare `help` just prints `help()`. Neither gives argument lists. For those, the gmax help files
  (`help/maxscript.chm`, `help/gmax.chm` in the gmax install, not in this repo) are the source.
- `saveMaxFile` works and renames the open scene. `holdMaxFile`/`fetchMaxFile` shows an "about to fetch"
  dialog even with `quiet:true`.
- Map channels are only -2..1. `edittext ... readOnly:` and `tooltip:` are untested (avoid: a compile
  error stops the whole dialog from opening).
- Rollout floaters: `newRolloutFloater` clamps the width (min 136 px) and opens narrow; set `.size`
  again after `addRollout` (`ClaudeLinkFix()`). A rollup panel keeps the width it was created with, so
  compact-strip controls use fixed `pos:`. Names used by rollout handlers must be forward-declared
  `global` before the rollout.
- The title-bar minimize button hides a floater. The helper strips the minimize/maximize buttons on
  `-Open`/`-Restore`; `-Restore` brings a minimized dialog back.
- MAXScript heap: a 20-million-element array fails even with `heapSize` 500 MB.
- Errors in code run raw print `-- Runtime error: ...` in the Listener. Errors inside functions defined
  in a script file also pop that file's editor window.

## Where things are
- `scripts/ClaudeLink/ClaudeLink.ms` the dialog; `gmax_run.ps1` the helper; this file.
- Data out of gmax: `scripts/Tests/piggyback.ms`, `scripts/RigTools/DataOut.ms`, extractor in
  `scripts/Tests/tools/` (see Docs/character-studio-plan.md, Phases 0 and 0b).

## Verified log
- 2026-11-12: Say / Eval / Cmd / Watch / Status / Read / Restore / ShowListener / HideListener tested;
  Pause, Resume and Emergency Stop block and unblock the helper; works with the full Listener open,
  closed or minimized; compact layout checked; `saveNodes` unavailable; `getCurrentException` missing.
