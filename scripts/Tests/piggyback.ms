-- ****************************
-- Piggyback: get data out of gmax  (Phase 0 of Docs/character-studio-plan.md)
--
-- gmax cannot write files, so bytes are hidden in the numbers of a generated mesh and carried
-- out in a file gmax CAN write: a .gmax scene saved with saveMaxFile (PiggybackSave, "Dense mode"
-- below). The payload sits in map channel 1, 24 bits per float (9 bytes per map vertex, ~75%
-- efficient). Verified byte-exact at 1 MB and 5 MB per call. scripts/RigTools/DataOut.ms wraps it.
--
-- Read the result outside gmax with scripts/ClaudeLink/Extract-Piggyback.ps1 (pure PowerShell).
--
-- The listener only repaints when a script ends; PB_Log prints and forces a repaint.
-- ****************************

-- Simple PackBits-style RLE. Control byte c:
--   0..127   : copy the next c+1 bytes literally
--   128..255 : repeat the next byte (c - 126) times (2..129)
-- Runs of 3+ identical bytes are encoded as runs; everything else is literal.
fn PB_FlushLit out lit =
(
	if lit.count > 0 then
	(
		append out (lit.count - 1)
		join out lit
		lit.count = 0
	)
)

fn PB_Compress buf =
(
	local out = #()
	local lit = #()
	local n = buf.count
	local i = 1
	while i <= n do
	(
		local j = i
		while j < n and (j - i) < 128 and buf[j + 1] == buf[i] do j += 1
		local r = j - i + 1
		if r >= 3 then
		(
			PB_FlushLit out lit
			append out (r + 126)
			append out buf[i]
			i = j + 1
		)
		else
		(
			append lit buf[i]
			i += 1
			if lit.count == 128 then PB_FlushLit out lit
		)
	)
	PB_FlushLit out lit
	return out
)

-- Returns the expanded bytes, or undefined if the data is malformed
fn PB_Decompress buf =
(
	local out = #()
	local n = buf.count
	local i = 1
	while i <= n do
	(
		local c = buf[i]
		if c < 128 then
		(
			if i + c + 1 > n then return undefined
			for k = 1 to (c + 1) do append out buf[i + k]
			i += c + 2
		)
		else
		(
			if i + 1 > n then return undefined
			local cnt = c - 126
			for k = 1 to cnt do append out buf[i + 1]
			i += 2
		)
	)
	return out
)

fn PB_Byte buffer i = if i <= buffer.count then buffer[i] else 0

-- Put decoded chunks (any order) back together, decompressing if needed. Returns bytes or undefined
fn PB_Assemble chunks =
(
	if chunks.count == 0 then return undefined
	local expected = chunks[1][2]
	if chunks.count != expected then return undefined

	local result = #()
	for i = 0 to (expected - 1) do
	(
		local found = undefined
		for c in chunks do if c[1] == i then found = c
		if found == undefined then return undefined
		join result found[3]
	)
	if chunks[1][4] then result = PB_Decompress result
	return result
)

-- Strings (one byte per character)
fn EncodeString s =
(
	for i = 1 to s.count collect (bit.CharAsInt s[i])
)

fn DecodeString bytes =
(
	local s = ""
	for b in bytes do s += (bit.IntAsChar b)
	return s
)

-- 32-bit IEEE-754 floats, little-endian
fn FloatToBytes v =
(
	if v == 0.0 then return #(0, 0, 0, 0)

	local sign = if v < 0.0 then 1 else 0
	local a = abs v
	local e = (floor ((log a) / (log 2.0))) as integer
	local m = a / (2.0 ^ e)
	if m < 1.0 then (e -= 1; m = a / (2.0 ^ e))
	if m >= 2.0 then (e += 1; m = a / (2.0 ^ e))

	local mant = (floor ((m - 1.0) * 8388608.0 + 0.5)) as integer
	if mant >= 8388608 then (mant = 0; e += 1)

	local be = e + 127
	if be <= 0 then return #(0, 0, 0, sign * 128)
	if be >= 255 then (be = 254; mant = 8388607)

	local b3 = sign * 128 + (be / 2)
	local b2 = (mod be 2 as integer) * 128 + (mant / 65536)
	local b1 = mod (mant / 256) 256 as integer
	local b0 = mod mant 256 as integer
	return #(b0, b1, b2, b3)
)

fn BytesToFloat b0 b1 b2 b3 =
(
	local sign = if b3 >= 128 then -1.0 else 1.0
	local be = (mod b3 128 as integer) * 2 + (b2 / 128)
	local mant = (mod b2 128 as integer) * 65536 + b1 * 256 + b0
	if be == 0 then return 0.0
	return (sign * (1.0 + mant / 8388608.0) * (2.0 ^ (be - 127)))
)

fn EncodeFloats vals =
(
	local out = #()
	for v in vals do join out (FloatToBytes v)
	return out
)

fn DecodeFloats bytes =
(
	for i = 0 to (bytes.count / 4 - 1) collect
		(BytesToFloat bytes[4*i+1] bytes[4*i+2] bytes[4*i+3] bytes[4*i+4])
)

-- In-memory checks of the helpers (strings, RLE, floats); no files involved. See also TestDense.
fn TestIt =
(
	local ok = true

	-- Strings of several lengths
	for msg in #("This is my secret message!", "a", "ab", "abc", "abcd") do
	(
		local outMsg = DecodeString (EncodeString msg)
		format " In: %\nOut: %\n" msg outMsg
		if outMsg != msg then ok = false
	)

	-- RLE: runs, long runs (>129), literals longer than 128, mixed, and incompressible data
	local rleCases = #()
	append rleCases (for i = 1 to 500 collect 0)
	append rleCases (for i = 1 to 300 collect ((mod (i * 7) 256) as integer))
	append rleCases (join (for i = 1 to 10 collect 65) (join (for i = 1 to 5 collect (i * 3)) (for i = 1 to 200 collect 255)))
	append rleCases #(1, 1, 2, 2, 3, 3, 3)
	append rleCases #(9)
	for c in rleCases do
	(
		local packed = PB_Compress c
		local unpacked = PB_Decompress packed
		local same = (unpacked != undefined and unpacked.count == c.count)
		if same then for i = 1 to c.count do if unpacked[i] != c[i] then same = false
		format "RLE % -> % bytes: %\n" c.count packed.count (if same then "ok" else "FAILED")
		if not same then ok = false
	)

	-- Floats
	local fin = #(1.0, -2.5, 0.0, 3.14159, 1000.125, -0.001)
	local fout = DecodeFloats (EncodeFloats fin)
	for i = 1 to fin.count do
	(
		format "float % -> %\n" fin[i] fout[i]
		if abs (fin[i] - fout[i]) > abs (fin[i]) * 1e-6 then ok = false
	)

	format "TestIt: %\n" (if ok then "PASS" else "FAIL")
	return ok
)

-- Deterministic test payload (Extract-Piggyback.ps1 -Verify uses the same formula)
fn PB_TestPattern n =
(
	for i = 0 to (n - 1) collect ((mod (i * 7 + (i / 256) * 13 + 5) 256) as integer)
)

-- Print a line and force the listener to show it now (it normally only repaints when a script ends)
fn PB_Log msg =
(
	format "%\n" msg
	try (flush stdout) catch ()
	try (windows.processPostedMessages()) catch ()
)

-- ****************************
-- Dense mode (scene files only): payload rides in a custom map channel
--
-- Map vertices are 3 floats each and their count is independent of the geometry, so one
-- triangle of geometry carries the whole chunk. Every float holds a 24-bit integer
-- (exact in float32), i.e. 3 payload bytes per float, 9 per map vertex.
--   map vert 1: [5259844 ("PBD"), byteCount, checksum (sum of bytes mod 2^24)]
--   map vert 2: [chunkIdx, chunkCount, flags]      flags bit0 = payload is RLE-compressed
--   map vert 3..: data, 9 bytes each (zero padded)
-- A chunk holds up to 2^24 - 1 bytes. Positions are unscaled in a scene file, so no
-- calibration is needed. The extractor finds chunks by searching for the header float.
-- ****************************

-- gmax only allows map channels -2..1 (alpha, illum, vertex color, UV), not the 0..99 of full Max.
-- Channel 1 (UVs) is used for the payload; use 0 (vertex color) if UVs ever get in the way.
global PB_MAPCHAN = 1
global PB_DENSE_MAGIC = 5259844       -- 'P'*65536 + 'B'*256 + 'D'
global PB_DENSE_CHUNK_BYTES = 4000000 -- must stay below 16777216

-- Build one dense chunk mesh from a slice of bytes
fn PB_DenseChunk buffer chunkIdx chunkCount flags meshName =
(
	local n = buffer.count
	local chk = 0
	for i = 1 to n do
	(
		chk += buffer[i]
		if chk >= 16777216 then chk -= 16777216
	)
	local nv = amax 3 (2 + (n + 8) / 9)

	local m = mesh vertices:#([0,0,0], [1,0,0], [0,1,0]) faces:#([1,2,3]) name:meshName
	meshop.setMapSupport m PB_MAPCHAN true
	meshop.defaultMapFaces m PB_MAPCHAN
	meshop.setNumMapVerts m PB_MAPCHAN nv keep:true

	meshop.setMapVert m PB_MAPCHAN 1 [PB_DENSE_MAGIC, n, chk]
	meshop.setMapVert m PB_MAPCHAN 2 [chunkIdx, chunkCount, flags]
	for v = 3 to nv do
	(
		local b = 9 * (v - 3)
		local a1 = (PB_Byte buffer (b+1)) + (PB_Byte buffer (b+2)) * 256 + (PB_Byte buffer (b+3)) * 65536
		local a2 = (PB_Byte buffer (b+4)) + (PB_Byte buffer (b+5)) * 256 + (PB_Byte buffer (b+6)) * 65536
		local a3 = (PB_Byte buffer (b+7)) + (PB_Byte buffer (b+8)) * 256 + (PB_Byte buffer (b+9)) * 65536
		meshop.setMapVert m PB_MAPCHAN v [a1, a2, a3]
	)
	return m
)

-- Encode a byte array into one or more dense chunk meshes (RLE only if it helps)
fn PB_DenseEncode buffer baseName:"m_dense" compress:true chunkBytes:PB_DENSE_CHUNK_BYTES =
(
	local meshes = #()
	local flags = 0
	if compress then
	(
		local packed = PB_Compress buffer
		if packed.count < buffer.count then (buffer = packed; flags = 1)
	)
	local total = buffer.count
	local chunkCount = amax 1 ((total + chunkBytes - 1) / chunkBytes)
	for c = 0 to (chunkCount - 1) do
	(
		local first = c * chunkBytes + 1
		local last = amin total (first + chunkBytes - 1)
		local slice = for i = first to last collect buffer[i]
		local num = (c + 1) as string
		while num.count < 3 do num = "0" + num
		append meshes (PB_DenseChunk slice c chunkCount flags (baseName + "_" + num))
	)
	return meshes
)

-- Read one dense chunk back from its mesh. Returns #(chunkIdx, chunkCount, bytes, isCompressed) or undefined
fn PB_DenseDecodeMesh m =
(
	if not (meshop.getMapSupport m PB_MAPCHAN) then return undefined
	local nv = meshop.getNumMapVerts m PB_MAPCHAN
	if nv < 3 then return undefined

	local h1 = meshop.getMapVert m PB_MAPCHAN 1
	local h2 = meshop.getMapVert m PB_MAPCHAN 2
	if (h1.x as integer) != PB_DENSE_MAGIC then return undefined
	local n = h1.y as integer
	local chk = h1.z as integer

	local bytes = #()
	local dataVerts = (n + 8) / 9
	if nv < 2 + dataVerts then return undefined
	for v = 3 to (2 + dataVerts) do
	(
		local p = meshop.getMapVert m PB_MAPCHAN v
		for k = 1 to 3 do
		(
			local a = (p[k] as integer)
			append bytes ((mod a 256) as integer)
			append bytes ((mod (a / 256) 256) as integer)
			append bytes (a / 65536)
		)
	)
	bytes.count = n

	local check = 0
	for b in bytes do
	(
		check += b
		if check >= 16777216 then check -= 16777216
	)
	if check != chk then return undefined
	return #((h2.x as integer), (h2.y as integer), bytes, ((bit.and (h2.z as integer) 1) == 1))
)

fn PB_DenseDecode meshes =
(
	local list = if classOf meshes == Array then meshes else #(meshes)
	local chunks = #()
	for m in list do
	(
		local c = PB_DenseDecodeMesh m
		if c == undefined then return undefined
		append chunks c
	)
	return (PB_Assemble chunks)
)

-- In-memory check of the dense codec: no file involved
fn TestDense =
(
	local ok = true
	local cases = #(0, 1, 8, 9, 10, 1000, 25000)
	for size in cases do
	(
		local data = PB_TestPattern size
		local meshes = PB_DenseEncode data compress:false baseName:"m_densetest"
		local back = PB_DenseDecode meshes
		local same = (back != undefined and back.count == data.count)
		if same then for i = 1 to data.count do if back[i] != data[i] then same = false
		PB_Log ("dense " + (size as string) + " bytes -> " + ((meshop.getNumMapVerts meshes[1] PB_MAPCHAN) as string) + " map verts: " + (if same then "ok" else "FAILED"))
		if not same then ok = false
		delete meshes
	)

	-- multi-chunk and compression
	local zeros = for i = 1 to 20000 collect 0
	local meshes = PB_DenseEncode zeros chunkBytes:700
	local back = PB_DenseDecode meshes
	local same = (back != undefined and back.count == zeros.count)
	PB_Log ("dense zeros (rle, " + (meshes.count as string) + " chunk(s)): " + (if same then "ok" else "FAILED"))
	if not same then ok = false
	delete meshes

	local data = PB_TestPattern 3000
	meshes = PB_DenseEncode data compress:false chunkBytes:1000
	back = PB_DenseDecode meshes
	same = (back != undefined and back.count == 3000 and meshes.count == 3)
	PB_Log ("dense 3 chunks: " + (if same then "ok" else "FAILED"))
	if not same then ok = false
	delete meshes

	PB_Log ("TestDense: " + (if ok then "PASS" else "FAIL"))
	return ok
)

-- Encode bytes and save them in a .gmax scene file with saveMaxFile (dense layout).
-- The payload meshes are added to the current scene, the scene is saved, and the meshes are
-- deleted again. The extractor finds the payload by signature, so the rest of the scene in
-- the file is harmless. NOTE: saveMaxFile changes the current scene's file name; check
-- File > Save As before saving your own work. Returns true on success.
fn PiggybackSave buffer filename chunkBytes:PB_DENSE_CHUNK_BYTES compress:true =
(
	local meshes = undefined
	local saved = false
	-- Same speed-ups as ASPImport.ms / StitchTools.ms: nothing is drawn or kept for undo
	try (disableSceneRedraw()) catch ()
	with undo off with redraw off
	(
		try
		(
			meshes = PB_DenseEncode buffer baseName:"m_pbsave" chunkBytes:chunkBytes compress:compress
			PB_Log ("saving " + (meshes.count as string) + " mesh(es) to " + filename)
			saveMaxFile filename
			saved = true
		)
		catch (PB_Log "PiggybackSave failed (gmax has no getCurrentException; run it without the try to see the message)")
		if meshes != undefined then delete meshes
		clearUndoBuffer()
	)
	try (enableSceneRedraw()) catch ()
	return saved
)

-- Size probe for the scene route: one scene file per size, with timings.
-- Files: piggyback_dense_<size>.gmax in the scene folder; check each with Extract-Piggyback.ps1 -Verify.
-- Compression is off (the pattern has no runs, and compressing would double the memory used).
-- MAXScript itself runs out of memory building the test array at about 20 MB, even with a 500 MB heap.
fn LimitTestSave sizes =
(
	for s in sizes do
	(
		local f = (GetDir #scene) + "/piggyback_dense_" + (s as string) + ".gmax"
		PB_Log ("size " + (s as string) + " bytes: building pattern...")
		local t0 = timestamp()
		local data = PB_TestPattern s
		PB_Log ("  pattern built in " + ((timestamp() - t0) as string) + " ms; encoding and saving...")
		t0 = timestamp()
		local ok = PiggybackSave data f compress:false
		PB_Log ("  saved: " + (ok as string) + " in " + ((timestamp() - t0) as string) + " ms -> " + f)
		data = undefined
		gc()
	)
	PB_Log "LimitTestSave done"
)

-- Writes <scene dir>/piggyback_dense.gmax with a patterned payload of the given size
fn TestSaveDense size =
(
	local f = (GetDir #scene) + "/piggyback_dense.gmax"
	PB_Log ("TestSaveDense " + (size as string) + " bytes -> " + f)
	return (PiggybackSave (PB_TestPattern size) f)
)


/*
Run from the Listener (paste a line into the top pane, or drive it with scripts/ClaudeLink).
Then read the output files outside gmax with scripts/ClaudeLink/Extract-Piggyback.ps1.

-- 1. in-memory checks, no files (expect PASS)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); TestIt(); TestDense(); setListenerSel #(0,0)

-- 2. save a 1 MB payload in a scene file (piggyback_dense.gmax in the scene folder), and a size probe
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); TestSaveDense 1000000; setListenerSel #(0,0)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); LimitTestSave #(1000000, 5000000); setListenerSel #(0,0)

-- 3. the DataOut wrapper (writes DataOut_hello.gmax in the scene folder)
clearlistener(); filein ((GetDir #scripts) +"\\RigTools\\DataOut.ms"); DataOutSendString "hello" "Hello from gmax!"; setListenerSel #(0,0)
*/
