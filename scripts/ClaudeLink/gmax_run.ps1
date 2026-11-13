<#
.SYNOPSIS
  Claude's outside helper for a running gmax: send a line of MAXScript, read the reply, talk to
  the user through the "Claude Link" dialog. Uses window messages only (no focus changes).

.DESCRIPTION
  Safety: if the Claude Link dialog (ClaudeLink.ms) is open and its title says [PAUSED] or
  [STOPPED], nothing is sent. If it is not open, commands are refused (use -Open first).

  Where the line goes: the small mini-listener in gmax's bottom panel by default (its one-line
  input is replaced and restored afterwards); with -Full the full Listener's top pane instead
  (a line is appended and removed afterwards). Lines are run with a numpad-Enter key message.

  Where the reply comes from:
    -Eval  : the code runs through ClaudeEval and its value comes back via the dialog log
             (works with either listener; only the returned value is captured)
    -Cmd   : the raw line is run; output is read from the full Listener's output pane if it is
             open, otherwise only the mini-listener's last line is available

  Examples:
    gmax_run.ps1 -Status                          # dialog state and conversation log
    gmax_run.ps1 -Open                            # load ClaudeLink.ms into gmax
    gmax_run.ps1 -Say "Working on it"             # message to the user in the dialog
    gmax_run.ps1 -Eval '(1+2) as string'          # run code, return its value
    gmax_run.ps1 -Cmd 'format "hi\n"'             # raw line; output from the full Listener
    gmax_run.ps1 -ShowListener / -HideListener    # F11 / WM_CLOSE on the full Listener
#>
param(
  [string]$Cmd,
  [string]$Eval,
  [string]$Say,
  [switch]$Open,
  [switch]$Status,
  [switch]$Read,
  [switch]$Full,
  [switch]$ShowListener,
  [switch]$HideListener,
  [switch]$Restore,
  [switch]$Watch,
  [int]$Since = -1,
  [int]$Timeout = 10
)

$src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class G {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int index);
  [DllImport("user32.dll", EntryPoint="SetWindowLongW")] public static extern int SetWindowLong(IntPtr h, int index, int value);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  // Remove the minimize and maximize buttons (a minimized floater vanishes from view)
  public static string StripMinMax(IntPtr h){
    int style = GetWindowLong(h, -16);
    int wanted = style & ~0x00020000 & ~0x00010000;   // WS_MINIMIZEBOX, WS_MAXIMIZEBOX
    if (wanted == style) return "already without minimize/maximize buttons";
    SetWindowLong(h, -16, wanted);
    SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0027);  // NOSIZE|NOMOVE|NOZORDER|FRAMECHANGED
    return "removed minimize/maximize buttons";}
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, StringBuilder l, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr result);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }

  public static string Cls(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,256);return s.ToString();}
  public static string Title(IntPtr h){var s=new StringBuilder(256);GetWindowText(h,s,256);return s.ToString();}
  public static int Height(IntPtr h){RECT r;GetWindowRect(h,out r);return r.B-r.T;}

  public static List<IntPtr> TopWindows(uint pid){
    var l=new List<IntPtr>();
    EnumWindows((h,x)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid&&IsWindowVisible(h))l.Add(h);return true;},IntPtr.Zero);
    return l;}
  // Every top-level window of the process, visible or not (a minimized floater can be hidden)
  public static List<IntPtr> AllTopWindows(uint pid){
    var l=new List<IntPtr>();
    EnumWindows((h,x)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid)l.Add(h);return true;},IntPtr.Zero);
    return l;}
  public static List<IntPtr> Children(IntPtr parent){
    var l=new List<IntPtr>();
    EnumChildWindows(parent,(h,x)=>{l.Add(h);return true;},IntPtr.Zero);
    return l;}

  // Hang-safe: return null if gmax does not answer (a script is running)
  public static string Text(IntPtr h){
    IntPtr n;
    if(SendMessageTimeout(h,0x000E,IntPtr.Zero,IntPtr.Zero,3,2000,out n)==IntPtr.Zero) return null;
    var sb=new StringBuilder((int)n+2); IntPtr r;
    if(SendMessageTimeout(h,0x000D,(IntPtr)((int)n+1),sb,3,2000,out r)==IntPtr.Zero) return null;
    return sb.ToString();}
  public static bool Msg(IntPtr h,uint m,int w,int l){IntPtr r;return SendMessageTimeout(h,m,(IntPtr)w,(IntPtr)l,3,2000,out r)!=IntPtr.Zero;}
  public static bool MsgStr(IntPtr h,uint m,int w,string s){IntPtr r;return SendMessageTimeout(h,m,(IntPtr)w,s,3,2000,out r)!=IntPtr.Zero;}

  public static void NumpadEnter(IntPtr h){
    PostMessage(h,0x0100,(IntPtr)0x0D,(IntPtr)0x011C0001);
    PostMessage(h,0x0101,(IntPtr)0x0D,(IntPtr)unchecked((int)0xC11C0001));}
  public static void F11(IntPtr h){
    PostMessage(h,0x0100,(IntPtr)0x7A,(IntPtr)0x00570001);
    PostMessage(h,0x0101,(IntPtr)0x7A,(IntPtr)unchecked((int)0xC0570001));}
}
'@
Add-Type -TypeDefinition $src

$proc = Get-Process | Where-Object { $_.ProcessName -like 'gmax*' } | Select-Object -First 1
if (-not $proc) { Write-Output "ERROR: gmax is not running"; exit 1 }
$gpid = [uint32]$proc.Id

function Find-Windows {
  $script:tops = [G]::TopWindows($gpid)
  $script:main     = $script:tops | Where-Object { [G]::Cls($_) -eq '3DSMAX' } | Select-Object -First 1
  # the full Listener may be minimized or hidden (not "visible"): its panes still answer messages
  $script:listener = [G]::AllTopWindows($gpid) | Where-Object { [G]::Title($_) -eq 'MAXScript Listener' } | Select-Object -First 1
  $script:link     = $script:tops | Where-Object { [G]::Title($_) -like 'Claude Link*' } | Select-Object -First 1
  # mini-listener: a RICHEDIT with control ID 1002 below the main window, and its 1001 sibling
  $script:miniIn = [IntPtr]::Zero; $script:miniOut = [IntPtr]::Zero
  if ($script:main) {
    foreach ($k in [G]::Children($script:main)) {
      if ([G]::Cls($k) -eq 'RICHEDIT' -and [G]::GetDlgCtrlID($k) -eq 1002) {
        $script:miniIn  = $k
        $script:miniOut = [G]::GetDlgItem([G]::GetParent($k), 1001)
        break
      }
    }
  }
}

# The dialog shows its state in a label "STATE: RUNNING|PAUSED|STOPPED". Anything we cannot read
# is reported as UNKNOWN, which blocks sending.
function Get-LinkState {
  if (-not $script:link) { return 'NOT_OPEN' }
  foreach ($k in [G]::Children($script:link)) {
    if ([G]::Cls($k) -eq 'Static') {
      $t = [G]::Text($k)
      if ($t -match '^STATE: (\w+)') { return $Matches[1] }
    }
  }
  return 'UNKNOWN'
}

function Get-LinkLog {
  if (-not $script:link) { return $null }
  $edits = [G]::Children($script:link) | Where-Object { [G]::Cls($_) -eq 'Edit' }
  if (-not $edits) { return $null }
  $log = $edits | Sort-Object { [G]::Height($_) } -Descending | Select-Object -First 1
  return [G]::Text($log)
}

# Put one line into a listener input pane, run it, put the user's text back.
# Returns $null on success or an error string.
function Send-Line([string]$line, [bool]$useFull) {
  if ($line -match "[\r\n]") { return "ERROR: send a single line (join statements with ;)" }
  if ($useFull -and $script:listener) {
    $in = [G]::GetDlgItem($script:listener, 1002)
    $orig = [G]::Text($in)
    if ($orig -eq $null) { return "ERROR: gmax is busy (not responding). A script may be running - press Esc in gmax." }
    if ($orig.Length -gt 0 -and -not $orig.EndsWith("`n")) { [G]::MsgStr($in, 0xC2, 1, "`r`n") | Out-Null; $orig = [G]::Text($in) }
    $n = $orig.Length
    [G]::Msg($in, 0x00B1, $n, $n) | Out-Null
    [G]::MsgStr($in, 0xC2, 1, $line) | Out-Null
    [G]::NumpadEnter($in)
    $script:restoreAction = { [G]::Msg($in, 0x00B1, $n, -1) | Out-Null; [G]::MsgStr($in, 0xC2, 1, "") | Out-Null }.GetNewClosure()
    return $null
  }
  if ($script:miniIn -eq [IntPtr]::Zero) { return "ERROR: no mini-listener or full Listener found (press F11 in gmax, or use -ShowListener)" }
  $in = $script:miniIn
  $orig = [G]::Text($in)
  if ($orig -eq $null) { return "ERROR: gmax is busy (not responding). A script may be running - press Esc in gmax." }
  [G]::Msg($in, 0x00B1, 0, -1) | Out-Null
  [G]::MsgStr($in, 0xC2, 1, $line) | Out-Null
  [G]::NumpadEnter($in)
  $script:restoreAction = { [G]::Msg($in, 0x00B1, 0, -1) | Out-Null; [G]::MsgStr($in, 0xC2, 1, $orig) | Out-Null }.GetNewClosure()
  return $null
}

function Restore-Input { if ($script:restoreAction) { Start-Sleep -Milliseconds 300; & $script:restoreAction; $script:restoreAction = $null } }

Find-Windows

# ---- follow what the user does on screen (read-only) ---------------------------------------------------
# With the Macro Recorder enabled (Listener > MacroRecorder > Enable) the Listener's upper pane
# (control 1002) gets the MAXScript equivalent of every UI action: object creation, and
# actionMan.executeAction 0 "<id>" for menu / toolbar commands. Lines Claude sends through the
# mini-listener appear there too. Usage:
#   -Watch            the last 15 lines, then "next index: N"
#   -Watch -Since N   only what was added after character N (pass the previous "next index")
if ($Watch) {
  if (-not $script:listener) { Write-Output "ERROR: Listener window not found (it can be hidden or minimized, but must exist - use -ShowListener)"; exit 1 }
  $pane = [G]::GetDlgItem($script:listener, 1002)
  $text = [G]::Text($pane)
  if ($text -eq $null) { Write-Output "ERROR: gmax is busy (not responding)"; exit 1 }
  if ($Since -ge 0 -and $Since -le $text.Length) { $new = $text.Substring($Since) }
  elseif ($Since -gt $text.Length) { $new = "(the pane was cleared or shortened since index $Since)`n" + $text }
  else { $new = (($text -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 15) -join "`n") }
  Write-Output $new.TrimEnd()
  Write-Output "next index: $($text.Length)"
  exit 0
}

# ---- bring a minimized / hidden dialog back (does not send anything to the listener) -----------------
if ($Restore) {
  $found = $false
  foreach ($w in [G]::AllTopWindows($gpid)) {
    if ([G]::Title($w) -like 'Claude Link*') {
      $found = $true
      $wasIconic = [G]::IsIconic($w); $wasVisible = [G]::IsWindowVisible($w)
      [G]::ShowWindow($w, 9) | Out-Null   # SW_RESTORE
      Write-Output ("Claude Link window: iconic=$wasIconic visible=$wasVisible -> restored; " + [G]::StripMinMax($w))
    }
  }
  if (-not $found) { Write-Output "no Claude Link window found (use -Open to create it)" }
  exit 0
}

# ---- listener window control -----------------------------------------------------------------
if ($HideListener) {
  if ($script:listener) { [G]::PostMessage($script:listener, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; Write-Output "full Listener closed" }
  else { Write-Output "full Listener was not open" }
  exit 0
}
if ($ShowListener) {
  if ($script:listener) {
    if ([G]::IsIconic($script:listener) -or -not [G]::IsWindowVisible($script:listener)) { [G]::ShowWindow($script:listener, 9) | Out-Null; Write-Output "full Listener restored" }
    else { Write-Output "full Listener already open" }
  }
  else {
    [G]::F11($script:main)
    Start-Sleep -Milliseconds 1200
    Find-Windows
    Write-Output ($(if ($script:listener) { "full Listener opened" } else { "F11 sent but the Listener did not appear" }))
  }
  exit 0
}

# ---- status / read -----------------------------------------------------------------------------
if ($Status -or $Read) {
  Write-Output ("Claude Link: " + (Get-LinkState))
  Write-Output ("full Listener: " + $(if ($script:listener) { 'open' } else { 'closed' }) + "; mini-listener: " + $(if ($script:miniIn -ne [IntPtr]::Zero) { 'found' } else { 'not found' }))
  $log = Get-LinkLog
  if ($log) { Write-Output "--- conversation log ---"; Write-Output $log }
  if (-not ($Open -or $Say -or $Cmd -or $Eval)) { exit 0 }
}

# ---- open the dialog -----------------------------------------------------------------------------
if ($Open) {
  # Reloading is allowed when the dialog is not open yet (bootstrap), but if it is open the
  # user's Pause / Emergency Stop applies to this too.
  $st = Get-LinkState
  if ($st -ne 'NOT_OPEN' -and $st -ne 'UNKNOWN' -and $st -ne 'RUNNING') { Write-Output "BLOCKED: Claude Link is $st - the user has taken control. Not sending."; exit 2 }
  $err = Send-Line 'filein ((GetDir #scripts) + "/ClaudeLink/ClaudeLink.ms")' $Full.IsPresent
  if ($err) { Write-Output $err; exit 1 }
  $deadline = (Get-Date).AddSeconds($Timeout)
  do { Start-Sleep -Milliseconds 300; Find-Windows } while (-not $script:link -and (Get-Date) -lt $deadline)
  Restore-Input
  if ($script:link) { Write-Output ("Claude Link opened; " + [G]::StripMinMax($script:link)) }
  else { Write-Output "the dialog did not appear within ${Timeout}s" }
  exit 0
}

# ---- everything below sends commands: check the user has not taken control ------------------------
if ($Say -or $Cmd -or $Eval) {
  $state = Get-LinkState
  if ($state -eq 'NOT_OPEN') { Write-Output "BLOCKED: the Claude Link dialog is not open in gmax. Run with -Open first."; exit 2 }
  if ($state -ne 'RUNNING')  { Write-Output "BLOCKED: Claude Link is $state - the user has taken control. Not sending."; exit 2 }
}

function Esc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

if ($Say) {
  $err = Send-Line ('ClaudeSay "' + (Esc $Say) + '"') $Full.IsPresent
  Restore-Input
  if ($err) { Write-Output $err; exit 1 }
  Write-Output "said it"
}

if ($Eval) {
  # millisecond clock: two calls in the same second must not share an id (a shared id returns the
  # previous call's stale reply)
  $id = [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) % 1000000000)
  $err = Send-Line ('ClaudeEval ' + $id + ' "' + (Esc $Eval) + '"') $Full.IsPresent
  if ($err) { Write-Output $err; exit 1 }
  $deadline = (Get-Date).AddSeconds($Timeout)
  $reply = $null
  do {
    Start-Sleep -Milliseconds 250
    Find-Windows
    $log = Get-LinkLog
    if ($log -match "(?s)\[(result|error) $id\] (.*?)(\r?\n\[|\r?\n?$)") { $reply = $Matches[1] + ": " + $Matches[2].TrimEnd(); break }
  } while ((Get-Date) -lt $deadline)
  Restore-Input
  if ($reply) { Write-Output $reply } else { Write-Output "(no reply within ${Timeout}s - a script may still be running; check -Read)" }
}

if ($Cmd) {
  # raw line: read the full Listener's output pane if it is open
  $out = $null; $before = $null
  if ($script:listener) {
    $out = [G]::GetDlgItem($script:listener, 1001)
    [G]::PostMessage($script:listener, 0x0111, [IntPtr]40043, [IntPtr]::Zero) | Out-Null   # Edit > Clear All
    Start-Sleep -Milliseconds 300
    $before = [G]::Text($out)
  } elseif ($script:miniOut -ne [IntPtr]::Zero) { $out = $script:miniOut; $before = [G]::Text($out) }
  $err = Send-Line $Cmd $Full.IsPresent
  if ($err) { Write-Output $err; exit 1 }
  $deadline = (Get-Date).AddSeconds($Timeout)
  $last = $null; $stable = $null; $text = $before
  do {
    Start-Sleep -Milliseconds 200
    $text = [G]::Text($out)
    if ($text -ne $null -and $text -ne $before) {
      if ($text -eq $last) { if (-not $stable) { $stable = Get-Date } elseif (((Get-Date) - $stable).TotalMilliseconds -gt 600) { break } }
      else { $stable = $null }
      $last = $text
    }
  } while ((Get-Date) -lt $deadline)
  Restore-Input
  if ($text -eq $null -or $text -eq $before) { Write-Output "(no output within ${Timeout}s - the script may still be running)" }
  else { Write-Output $text.TrimEnd() }
  if (-not $script:listener) { Write-Output "(note: full Listener is closed - only the mini-listener's last line is visible; use -Eval for results)" }
}
