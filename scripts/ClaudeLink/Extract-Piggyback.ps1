<#
.SYNOPSIS
  Extract data smuggled out of gmax by scripts/Tests/piggyback.ms. Pure PowerShell: no compiled
  code, no Python, no extra packages. Everything it does is readable in this file.

.DESCRIPTION
  piggyback.ms saves the payload in a .gmax scene file (see "Dense mode" in piggyback.ms):
  the bytes are stored as 24-bit integers in the float32 map-vertex data of a one-triangle mesh.
  A .gmax file is an OLE compound document, so this script
    1. reads the 'Scene' stream out of the compound file (a small built-in reader: header,
       sector allocation table, directory, sector chains),
    2. searches the stream for the dense chunk header (a float32 signature),
    3. decodes and checksums each chunk, joins the chunks, and expands RLE if used.

  Heavy lifting uses native .NET calls (Array.IndexOf, Buffer.BlockCopy, LINQ Sum/Min/Max, SHA256),
  so a 1 MB payload takes a few seconds. Works in Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER Path     .gmax files, or folders (searched non-recursively for *.gmax)
.PARAMETER Out      write the recovered bytes to this file (chunks joined, RLE expanded)
.PARAMETER Text     print the recovered bytes as UTF-8 text
.PARAMETER Verify   compare against the PB_TestPattern payload used by LimitTestSave
.PARAMETER Report   per-file report only (no payload output)
.PARAMETER Prefix   only files whose name starts with this (case-insensitive)
.PARAMETER SelfTest run the built-in checks (no gmax needed) and exit

.EXAMPLE
  .\Extract-Piggyback.ps1 C:\Scenes\DataOut_hello.gmax -Text
  .\Extract-Piggyback.ps1 C:\Scenes -Prefix piggyback_dense -Verify -Report
  .\Extract-Piggyback.ps1 -SelfTest
#>
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Path,
  [string]$Out,
  [switch]$Text,
  [switch]$Verify,
  [switch]$Report,
  [string]$Prefix = '',
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# Dense chunk layout (map vertices; every number is an integer stored in a float32):
#   map vert 1: [DENSE_MAGIC, byteCount, checksum (sum of bytes mod 2^24)]
#   map vert 2: [chunkIdx, chunkCount, flags]         flags bit0 = payload is RLE-compressed
#   map vert 3..: payload, 9 bytes per map vertex = three 24-bit little-endian integers
$DENSE_MAGIC = 5259844          # 'P'*65536 + 'B'*256 + 'D'
$MAX_REGULAR = [int64]4294967290   # sector numbers at or above this are special (FAT, DIFAT, free, end)
$END_OF_CHAIN = [int64]4294967294

# ---- small helpers -------------------------------------------------------------------------------

function Get-Hash([byte[]]$bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  [Convert]::ToBase64String($sha.ComputeHash($bytes))
}

function Test-Bytes([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  return ((Get-Hash $a) -eq (Get-Hash $b))
}

# Same formula as PB_TestPattern in piggyback.ms: (i*7 + (i/256)*13 + 5) mod 256. It repeats every
# 65536 bytes, so build one period and copy it.
function Get-Pattern([int]$n) {
  $period = New-Object byte[] 65536
  for ($i = 0; $i -lt 65536; $i++) { $period[$i] = [int](($i * 7 + [Math]::Floor($i / 256) * 13 + 5) % 256) }
  $out = New-Object byte[] $n
  $off = 0
  while ($off -lt $n) {
    [Buffer]::BlockCopy($period, 0, $out, $off, [Math]::Min(65536, $n - $off))
    $off += 65536
  }
  , $out
}

# ---- RLE (PackBits style): c<128 -> copy c+1 literals; c>=128 -> repeat next byte c-126 times ----

function Expand-Rle([byte[]]$buf) {
  $ms = New-Object System.IO.MemoryStream
  $i = 0
  $n = $buf.Length
  while ($i -lt $n) {
    $c = $buf[$i]
    if ($c -lt 128) {
      if ($i + $c + 2 -gt $n) { throw 'truncated RLE literal' }
      $ms.Write($buf, $i + 1, $c + 1)
      $i += $c + 2
    } else {
      if ($i + 2 -gt $n) { throw 'truncated RLE run' }
      $count = $c - 126
      $ms.Write([byte[]](@($buf[$i + 1]) * $count), 0, $count)
      $i += 2
    }
  }
  , $ms.ToArray()
}

# Mirror of PB_Compress (only the self-test needs it)
function Compress-Rle([byte[]]$buf) {
  $ms = New-Object System.IO.MemoryStream
  $lit = New-Object System.Collections.Generic.List[byte]
  $flush = { if ($lit.Count -gt 0) { $ms.WriteByte([byte]($lit.Count - 1)); $ms.Write($lit.ToArray(), 0, $lit.Count); $lit.Clear() } }
  $i = 0
  $n = $buf.Length
  while ($i -lt $n) {
    $j = $i
    while ($j + 1 -lt $n -and $j - $i -lt 128 -and $buf[$j + 1] -eq $buf[$i]) { $j++ }
    $r = $j - $i + 1
    if ($r -ge 3) {
      & $flush
      $ms.WriteByte([byte]($r + 126)); $ms.WriteByte($buf[$i])
      $i = $j + 1
    } else {
      $lit.Add($buf[$i]); $i++
      if ($lit.Count -eq 128) { & $flush }
    }
  }
  & $flush
  , $ms.ToArray()
}

# ---- reading a .gmax (OLE compound file) ---------------------------------------------------------
# Layout (MS-CFB): a 512-byte header, then sectors of 512 (or 4096) bytes. The FAT says which sector
# follows which. The directory (a chain of sectors of 128-byte entries) names the streams. Streams
# shorter than the mini cutoff (4096) live in 64-byte "mini sectors" inside the root entry's stream.

function Read-Chain([byte[]]$f, [uint32[]]$fat, [int64]$start, [int]$sectorSize, [int64]$size) {
  $ms = New-Object System.IO.MemoryStream
  $s = $start
  $guard = 0
  while ($s -ne $END_OF_CHAIN -and $s -lt $MAX_REGULAR) {
    if ($guard++ -gt $fat.Length + 2 -or $s -ge $fat.Length) { throw 'broken FAT chain' }
    $off = ($s + 1) * $sectorSize
    if ($off + $sectorSize -gt $f.Length) { throw 'sector beyond the end of the file' }
    $ms.Write($f, [int]$off, $sectorSize)
    $s = [int64]$fat[$s]
    if ($size -ge 0 -and $ms.Length -ge $size) { break }
  }
  $all = $ms.ToArray()
  if ($size -lt 0) { return , $all }
  $r = New-Object byte[] $size
  [Buffer]::BlockCopy($all, 0, $r, 0, [int][Math]::Min($size, $all.Length))
  , $r
}

function Read-OleStream([byte[]]$f, [string]$name) {
  if ($f.Length -lt 512) { throw 'not an OLE file (too short)' }
  $sig = 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1
  for ($i = 0; $i -lt 8; $i++) { if ($f[$i] -ne $sig[$i]) { throw 'not an OLE compound file' } }

  $sectorSize = 1 -shl [BitConverter]::ToUInt16($f, 0x1E)
  $miniSize = 1 -shl [BitConverter]::ToUInt16($f, 0x20)
  $numFat = [int64][BitConverter]::ToUInt32($f, 0x2C)
  $dirStart = [int64][BitConverter]::ToUInt32($f, 0x30)
  $miniCutoff = [int64][BitConverter]::ToUInt32($f, 0x38)
  $miniFatStart = [int64][BitConverter]::ToUInt32($f, 0x3C)
  $difatStart = [int64][BitConverter]::ToUInt32($f, 0x44)
  $numDifat = [int64][BitConverter]::ToUInt32($f, 0x48)

  # sectors that hold the FAT: 109 entries in the header, the rest in a chain of DIFAT sectors
  $fatSectors = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt 109 -and $fatSectors.Count -lt $numFat; $i++) {
    $s = [int64][BitConverter]::ToUInt32($f, 0x4C + 4 * $i)
    if ($s -lt $MAX_REGULAR) { [void]$fatSectors.Add($s) }
  }
  $d = $difatStart
  for ($di = 0; $di -lt $numDifat -and $d -lt $MAX_REGULAR; $di++) {
    $off = ($d + 1) * $sectorSize
    for ($i = 0; $i -lt $sectorSize / 4 - 1 -and $fatSectors.Count -lt $numFat; $i++) {
      $s = [int64][BitConverter]::ToUInt32($f, [int]$off + 4 * $i)
      if ($s -lt $MAX_REGULAR) { [void]$fatSectors.Add($s) }
    }
    $d = [int64][BitConverter]::ToUInt32($f, [int]$off + $sectorSize - 4)
  }
  $perSector = $sectorSize / 4
  $fat = New-Object uint32[] ($fatSectors.Count * $perSector)
  for ($i = 0; $i -lt $fatSectors.Count; $i++) {
    [Buffer]::BlockCopy($f, [int](($fatSectors[$i] + 1) * $sectorSize), $fat, $i * $sectorSize, $sectorSize)
  }

  # the directory: 128-byte entries; find the named stream and the root entry
  $dir = Read-Chain $f $fat $dirStart $sectorSize -1
  $start = [int64]0; $size = [int64]-1; $rootStart = [int64]0; $rootSize = [int64]0
  for ($e = 0; ($e + 1) * 128 -le $dir.Length; $e++) {
    $o = $e * 128
    $type = $dir[$o + 0x42]
    if ($type -eq 0) { continue }
    $nameLen = [BitConverter]::ToUInt16($dir, $o + 0x40)
    $nm = ''
    if ($nameLen -ge 2) { $nm = [System.Text.Encoding]::Unicode.GetString($dir, $o, $nameLen - 2) }
    $st = [int64][BitConverter]::ToUInt32($dir, $o + 0x74)
    $sz = [int64][BitConverter]::ToUInt64($dir, $o + 0x78)
    if ($type -eq 5) { $rootStart = $st; $rootSize = $sz }
    if ($type -eq 2 -and $size -lt 0 -and $nm -ceq $name) { $start = $st; $size = $sz }
  }
  if ($size -lt 0) { throw "stream '$name' not found in the OLE file" }

  if ($size -ge $miniCutoff) { return , (Read-Chain $f $fat $start $sectorSize $size) }

  # short stream: it lives in mini sectors inside the root entry's stream
  $miniStream = Read-Chain $f $fat $rootStart $sectorSize $rootSize
  $miniFatBytes = Read-Chain $f $fat $miniFatStart $sectorSize -1
  $miniFat = New-Object uint32[] ($miniFatBytes.Length / 4)
  [Buffer]::BlockCopy($miniFatBytes, 0, $miniFat, 0, $miniFatBytes.Length)
  $ms = New-Object System.IO.MemoryStream
  $s = $start
  $guard = 0
  while ($s -ne $END_OF_CHAIN -and $ms.Length -lt $size) {
    if ($guard++ -gt $miniFat.Length + 2 -or $s -ge $miniFat.Length) { throw 'broken mini FAT chain' }
    $ms.Write($miniStream, [int]($s * $miniSize), $miniSize)
    $s = [int64]$miniFat[$s]
  }
  $r = New-Object byte[] $size
  [Buffer]::BlockCopy($ms.ToArray(), 0, $r, 0, [int]$size)
  , $r
}

# ---- finding the payload ---------------------------------------------------------------------------

# Returns chunk objects: Index, Count, Data (bytes), Compressed, Verts
function Find-DenseChunks([byte[]]$data) {
  $magic = [BitConverter]::GetBytes([single]$DENSE_MAGIC)
  $results = New-Object System.Collections.ArrayList
  $pos = 0
  $last = $data.Length - 24
  while ($pos -le $last) {
    $i = [Array]::IndexOf($data, $magic[0], $pos, $last - $pos + 1)      # native scan for the first byte
    if ($i -lt 0) { break }
    $pos = $i + 1
    if ($data[$i + 1] -ne $magic[1] -or $data[$i + 2] -ne $magic[2] -or $data[$i + 3] -ne $magic[3]) { continue }

    # header: byteCount, checksum, chunkIdx, chunkCount, flags (all whole numbers >= 0)
    $h = @(0..4 | ForEach-Object { [double][BitConverter]::ToSingle($data, $i + 4 + 4 * $_) })
    $bad = $false
    foreach ($v in $h) { if ($v -ne [Math]::Floor($v) -or $v -lt 0) { $bad = $true } }
    if ($bad) { continue }
    $n = [int64]$h[0]; $chk = [int64]$h[1]; $idx = [int]$h[2]; $cnt = [int]$h[3]; $flags = [int]$h[4]
    if ($cnt -lt 1 -or $idx -ge $cnt -or $flags -gt 1) { continue }

    $dataVerts = [int64][Math]::Floor(($n + 8) / 9)
    $nFloats = 3 * $dataVerts
    if ($i + 24 + 4 * $nFloats -gt $data.Length) { continue }

    $payload = New-Object byte[] ($dataVerts * 9)
    if ($nFloats -gt 0) {
      $floats = New-Object single[] $nFloats
      [Buffer]::BlockCopy($data, $i + 24, $floats, 0, 4 * $nFloats)
      if ([Linq.Enumerable]::Min($floats) -lt 0 -or [Linq.Enumerable]::Max($floats) -ge 16777216) { continue }
      $ints = [int[]]$floats
      $o = 0
      for ($k = 0; $k -lt $nFloats; $k++) {
        $v = $ints[$k]
        $payload[$o] = $v -band 255
        $payload[$o + 1] = ($v -shr 8) -band 255
        $payload[$o + 2] = $v -shr 16
        $o += 3
      }
    }
    $bytes = New-Object byte[] $n
    if ($n -gt 0) { [Buffer]::BlockCopy($payload, 0, $bytes, 0, $n) }
    $sum = [Linq.Enumerable]::Sum([long[]]$bytes)
    if (($sum % 16777216) -ne $chk) { continue }                          # not a real chunk

    [void]$results.Add([pscustomobject]@{ Index = $idx; Count = $cnt; Data = $bytes; Compressed = (($flags -band 1) -eq 1); Verts = 2 + $dataVerts })
    $pos = $i + 24 + 4 * $nFloats
  }
  , $results.ToArray()
}

# ---- self-test -------------------------------------------------------------------------------------
# Test-only encoders: they mirror PB_DenseChunk in piggyback.ms and write a minimal OLE file.

function ConvertTo-DenseBlob([byte[]]$buf, [int]$idx, [int]$cnt, [int]$flags) {
  $n = $buf.Length
  $nv = [Math]::Max(3, 2 + [Math]::Floor(($n + 8) / 9))
  $chk = 0
  foreach ($b in $buf) { $chk += $b }
  $chk = $chk % 16777216
  $vals = New-Object System.Collections.ArrayList
  foreach ($x in $DENSE_MAGIC, $n, $chk, $idx, $cnt, $flags) { [void]$vals.Add([single]$x) }
  for ($v = 3; $v -le $nv; $v++) {
    $b0 = 9 * ($v - 3)
    for ($k = 0; $k -lt 3; $k++) {
      $o = $b0 + 3 * $k
      $a = 0
      for ($j = 0; $j -lt 3; $j++) { if ($o + $j -lt $n) { $a += [int]$buf[$o + $j] * [Math]::Pow(256, $j) } }
      [void]$vals.Add([single]$a)
    }
  }
  $floats = [single[]]$vals.ToArray()
  $bytes = New-Object byte[] (4 * $floats.Length)
  [Buffer]::BlockCopy($floats, 0, $bytes, 0, $bytes.Length)
  , $bytes
}

# A tiny valid compound file with one regular-sized stream (>= 4096 bytes), 512-byte sectors:
# sector 0 = FAT, sector 1 = directory, sectors 2.. = the stream.
function New-OleFile([string]$streamName, [byte[]]$streamData) {
  $sectors = [int][Math]::Ceiling($streamData.Length / 512)
  if ($streamData.Length -lt 4096 -or $sectors -gt 120) { throw 'test writer: stream must be 4096..61440 bytes' }
  $FREE = [uint32]4294967295; $ENDC = [uint32]4294967294; $FATSEC = [uint32]4294967293   # 0xFFFFFFFF/E/D, unsigned
  $f = New-Object byte[] (512 * (2 + 1 + $sectors))
  [Array]::Copy([byte[]](0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1), $f, 8)
  $put16 = { param($o, $v) [BitConverter]::GetBytes([uint16]$v).CopyTo($f, $o) }
  $put32 = { param($o, $v) [BitConverter]::GetBytes([uint32]$v).CopyTo($f, $o) }
  & $put16 0x18 0x3E; & $put16 0x1A 3; & $put16 0x1C 0xFFFE; & $put16 0x1E 9; & $put16 0x20 6
  & $put32 0x2C 1          # one FAT sector
  & $put32 0x30 1          # directory starts at sector 1
  & $put32 0x38 4096       # mini stream cutoff
  & $put32 0x3C $ENDC # no mini FAT
  & $put32 0x44 $ENDC # no DIFAT
  for ($i = 0; $i -lt 109; $i++) { & $put32 (0x4C + 4 * $i) $FREE }
  & $put32 0x4C 0          # FAT is in sector 0
  # FAT (sector 0 -> file offset 512)
  $fatOff = 512
  for ($i = 0; $i -lt 128; $i++) { & $put32 ($fatOff + 4 * $i) $FREE }
  & $put32 ($fatOff + 0) $FATSEC          # this sector is a FAT sector
  & $put32 ($fatOff + 4) $ENDC          # directory: one sector
  for ($s = 2; $s -lt 2 + $sectors; $s++) {
    $next = $ENDC
    if ($s -lt 1 + $sectors) { $next = $s + 1 }
    & $put32 ($fatOff + 4 * $s) $next
  }
  # directory (sector 1 -> offset 1024): root entry and the stream entry
  $entry = {
    param($index, $nm, $type, $start, $size)
    $o = 1024 + 128 * $index
    $u = [System.Text.Encoding]::Unicode.GetBytes($nm)
    $u.CopyTo($f, $o)
    & $put16 ($o + 0x40) ($u.Length + 2)
    $f[$o + 0x42] = $type
    foreach ($k in 0x44, 0x48, 0x4C) { & $put32 ($o + $k) $FREE }
    & $put32 ($o + 0x74) $start
    [BitConverter]::GetBytes([uint64]$size).CopyTo($f, $o + 0x78)
  }
  & $entry 0 'Root Entry' 5 $ENDC 0
  & $entry 1 $streamName 2 2 $streamData.Length
  [Array]::Copy($streamData, 0, $f, 512 * 3, $streamData.Length)
  , $f
}

if ($SelfTest) {
  $script:fails = 0
  function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Output "ok    $name" } else { Write-Output "FAIL  $name"; $script:fails++ }
  }
  function Throws([scriptblock]$sb) { try { & $sb | Out-Null; return $false } catch { return $true } }

  # RLE
  $cases = New-Object System.Collections.ArrayList
  [void]$cases.Add([byte[]]@())
  [void]$cases.Add([byte[]](New-Object byte[] 500))
  [void]$cases.Add([byte[]](0..255 + 0..255 + 0..255))
  [void]$cases.Add([byte[]](@(65) * 10 + @(3, 6, 9) + @(255) * 200))
  [void]$cases.Add([byte[]]@(1, 1, 2, 2, 3, 3, 3))
  [void]$cases.Add([byte[]]@(9))
  foreach ($len in 129, 130, 258, 259) { [void]$cases.Add([byte[]](@(122) * $len)) }
  $okAll = $true
  foreach ($c in $cases) { if (-not (Test-Bytes (Expand-Rle (Compress-Rle $c)) $c)) { $okAll = $false } }
  Check 'RLE round trips (10 cases)' $okAll
  Check 'RLE: zeros shrink' ((Compress-Rle (New-Object byte[] 5000)).Length -lt 100)
  Check 'RLE: truncated literal is an error' (Throws { Expand-Rle ([byte[]]@(5, 1, 2)) })
  Check 'RLE: run with no byte is an error' (Throws { Expand-Rle ([byte[]]@(200)) })

  # pattern
  $p3 = Get-Pattern 70000
  Check 'pattern matches the MAXScript formula' ($p3[0] -eq 5 -and $p3[1] -eq 12 -and $p3[2] -eq 19 -and $p3[256] -eq ((256 * 7 + 13 + 5) % 256) -and $p3[65536] -eq 5)

  # dense chunks inside other data
  $a = Get-Pattern 5000
  $b = Get-Pattern 5000; [Array]::Reverse($b)
  $z = Compress-Rle (New-Object byte[] 4000)
  $junk = [System.Text.Encoding]::ASCII.GetBytes(('junk' * 33))
  $filler = [System.Text.Encoding]::ASCII.GetBytes(('filler' * 9))
  $scene = [byte[]]($junk + (ConvertTo-DenseBlob $a 0 2 0) + $filler + (ConvertTo-DenseBlob $b 1 2 0) + [byte[]]@(121, 121) + (ConvertTo-DenseBlob $z 0 1 1) + (ConvertTo-DenseBlob ([byte[]]@()) 0 1 0))
  $r = Find-DenseChunks $scene
  Check 'dense: four chunks found inside other scene data' ($r.Count -eq 4)
  Check 'dense: payloads, RLE flag and the empty chunk' ((Test-Bytes $r[0].Data $a) -and (Test-Bytes $r[1].Data $b) -and $r[2].Compressed -and (Test-Bytes (Expand-Rle $r[2].Data) (New-Object byte[] 4000)) -and $r[3].Data.Length -eq 0)
  $okAll = $true
  foreach ($n in 1, 8, 9, 10, 17, 18, 1000) {
    $pp = Get-Pattern $n
    $r1 = Find-DenseChunks ([byte[]](@(1) * 64 + (ConvertTo-DenseBlob $pp 0 1 0)))
    if (-not ($r1.Count -eq 1 -and (Test-Bytes $r1[0].Data $pp))) { $okAll = $false }
  }
  Check 'dense: sizes around the 9-byte boundary' $okAll
  $blob = [byte[]](ConvertTo-DenseBlob (Get-Pattern 100) 0 1 0)
  $blob[40] = $blob[40] -bxor 1
  Check 'dense: a corrupted chunk is rejected (checksum)' ((Find-DenseChunks $blob).Count -eq 0)
  Check 'dense: nothing to find in plain data' ((Find-DenseChunks ([System.Text.Encoding]::ASCII.GetBytes(('nothing to see' * 50)))).Count -eq 0)

  # OLE reader on a generated compound file, end to end
  $payload = Get-Pattern 3000
  $sceneBytes = [byte[]]((New-Object byte[] 700) + (ConvertTo-DenseBlob $payload 0 1 0) + (New-Object byte[] 300))
  $ole = New-OleFile 'Scene' $sceneBytes
  $back = Read-OleStream $ole 'Scene'
  Check 'OLE: stream read back byte for byte' (Test-Bytes $back $sceneBytes)
  $rr = Find-DenseChunks $back
  Check 'OLE: payload recovered through the compound file' ($rr.Count -eq 1 -and (Test-Bytes $rr[0].Data $payload))
  Check 'OLE: a missing stream is an error' (Throws { Read-OleStream $ole 'Nope' })
  Check 'OLE: not an OLE file is an error' (Throws { Read-OleStream ([byte[]](New-Object byte[] 600)) 'Scene' })

  if ($script:fails -eq 0) { Write-Output 'self-test: all passed' } else { Write-Output "self-test: $($script:fails) FAILED" }
  exit ([int]($script:fails -ne 0))
}

# ---- command line ----------------------------------------------------------------------------------
if (-not $Path) { Get-Help $MyInvocation.MyCommand.Path -Full | Out-String | Write-Output; exit 2 }

$files = @()
foreach ($p in $Path) {
  if (Test-Path -LiteralPath $p -PathType Container) {
    $files += Get-ChildItem -LiteralPath $p -File -Filter '*.gmax' | Sort-Object Name | ForEach-Object FullName
  } else { $files += (Resolve-Path -LiteralPath $p).Path }
}
$files = @($files | Where-Object { [IO.Path]::GetFileName($_).StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) })
if ($files.Count -eq 0) { Write-Output 'no .gmax files found'; exit 2 }

$chunks = New-Object System.Collections.ArrayList
$failures = 0
foreach ($f in $files) {
  $name = [IO.Path]::GetFileName($f)
  try {
    if ($f -notlike '*.gmax') { throw 'only .gmax scene files are supported' }
    $scene = Read-OleStream ([IO.File]::ReadAllBytes($f)) 'Scene'
    $found = Find-DenseChunks $scene
    if ($found.Count -eq 0) { throw 'no piggyback chunks found in the Scene stream' }
  } catch {
    $failures++
    Write-Output ('FAIL  {0,-40} {1}' -f $name, $_.Exception.Message)
    continue
  }
  foreach ($c in $found) {
    $status = 'ok'
    if ($c.Compressed) { $status = 'ok (rle)' }
    elseif ($Verify -and $c.Count -eq 1) {
      if (Test-Bytes $c.Data (Get-Pattern $c.Data.Length)) { $status = 'verified' } else { $status = 'PATTERN MISMATCH'; $failures++ }
    }
    Write-Output ('{0,-8} {1,-40} chunk {2}/{3}  {4,8} bytes  {5,7} map verts  scene stream {6} B' -f $status, $name, ($c.Index + 1), $c.Count, $c.Data.Length, $c.Verts, $scene.Length)
    [void]$chunks.Add($c)
  }
}

if (-not $Report -and $chunks.Count -gt 0) {
  $expected = $chunks[0].Count
  $ordered = @($chunks | Sort-Object Index)
  $complete = ($ordered.Count -eq $expected)
  if ($complete) { for ($i = 0; $i -lt $expected; $i++) { if ($ordered[$i].Index -ne $i) { $complete = $false } } }
  if ($complete) {
    $ms = New-Object IO.MemoryStream
    foreach ($c in $ordered) { $ms.Write($c.Data, 0, $c.Data.Length) }
    $payload = $ms.ToArray()
    if ($ordered[0].Compressed) {
      $payload = Expand-Rle $payload
      Write-Output ('decompressed RLE payload to {0} bytes' -f $payload.Length)
    }
    if ($Verify -and -not $ordered[0].Compressed) {
      if (Test-Bytes $payload (Get-Pattern $payload.Length)) { Write-Output ('verified joined payload: {0} bytes match the test pattern' -f $payload.Length) }
      else { $failures++; Write-Output ('PATTERN MISMATCH in joined payload ({0} bytes)' -f $payload.Length) }
    }
    if ($Out) { [IO.File]::WriteAllBytes($Out, $payload); Write-Output ('wrote {0} bytes to {1}' -f $payload.Length, $Out) }
    if ($Text) { Write-Output ([Text.Encoding]::UTF8.GetString($payload)) }
  } else {
    Write-Output ('note: inputs are not one complete chunk set (have {0} of {1}); not joining' -f (($ordered | ForEach-Object { $_.Index }) -join ','), $expected)
  }
}
exit ([int]($failures -ne 0))
