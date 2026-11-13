-- ****************************
-- Piggyback: get data out of gmax  (Phase 0 of Docs/character-studio-plan.md)
--
-- gmax cannot write files, so bytes are hidden in the numbers of a generated mesh and carried
-- out in a file gmax CAN write. Read either route back outside gmax with
--   scripts/Tests/tools/extract_piggyback.py   (see its --help)
--
-- Route A - ASP export (PiggybackExport / Encode / Decode):
--   The DSiegeUtils ASP exporter (node names starting "M_") stripifies and reorders triangles
--   and dedupes corners, so face indices do not survive. Vertex positions are written as plain
--   floats (BVTX chunk), so the payload rides there. Each vertex is [seq, hi, lo]:
--     seq  vertex sequence number (0-based) - lets the reader ignore ordering
--     hi   2 data bytes: b1 + b2*256   (0..65535)
--     lo   2 data bytes: b3 + b4*256
--   so 4 payload bytes per vertex. Special vertices:
--     seq 0: [0, magic + 256*chunkIdx, dataByteCount mod 65536]
--            magic 83 = raw payload, 84 = RLE-compressed payload (see PB_Compress)
--     seq 1: [1, checksum (sum of data bytes mod 256) + 256*chunkCount, dataByteCount / 65536]
--     seq 2..: data; trailing filler vertices [seq,0,0] pad the count to a multiple of 3 so
--     every vertex is used by a (non-repeating) triangle. Triangles are [3j+1, 3j+2, 3j+3].
--   The exporter multiplies positions by the scene's meter scale (0.001 seen), so 16-bit fields
--   are used (65535 -> 65.535 is exact in float32) and the reader auto-calibrates the scale
--   from seq 1. In the ASP file hi/lo are not swapped (swapYZ stays false); abs() guards
--   negation. Limit: corner indices are 16-bit, so about 65,535 vertices (~262 KB) per mesh;
--   larger payloads become several files (m_encoded_001, _002, ...).
--
-- Route B - scene file (PiggybackSave, "Dense mode" below):
--   saveMaxFile writes a .gmax scene. No exporter, no Naming Key, no vertex cap, positions are
--   unscaled. The payload sits in a map channel, 9 bytes per map vertex (~75% efficient).
--   This is the route DataOut.ms uses. Verified byte-exact at 1 MB and 5 MB.
--
-- The listener only repaints when a script ends; PB_Log prints and forces a repaint.
-- ****************************

global PB_MAGIC = 83          -- 'S' raw payload
global PB_MAGIC_RLE = 84      -- 'T' RLE-compressed payload
-- Max data bytes per mesh for route A. The ASP exporter indexes corners with 16-bit values
-- (ASPexp.h TriIndexArray = vector<WORD>, NvTriStrip unsigned short), so a mesh can have
-- at most ~65535 vertices = ~262000 payload bytes at 4 bytes per vertex. Verified through the
-- exporter up to 262000 bytes (65502 vertices); 264000 bytes (66002 vertices) produced no file.
-- 256000 (64002 vertices) leaves a margin.
global PB_CHUNK_BYTES = 256000

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

-- Build the vertex and face lists for one chunk
fn PB_ChunkData buffer chunkIdx chunkCount magic =
(
	local n = buffer.count
	local sum = 0
	for i = 1 to n do sum += buffer[i]
	sum = (mod sum 256) as integer

	local dataVerts = (n + 3) / 4
	local total = 2 + dataVerts
	while (mod total 3) != 0 do total += 1

	local verts = #()
	append verts [0, magic + 256 * chunkIdx, mod n 65536]
	append verts [1, sum + 256 * chunkCount, n / 65536]

	for v = 0 to (dataVerts - 1) do
	(
		local b = 4 * v
		local hi = (PB_Byte buffer (b+1)) + (PB_Byte buffer (b+2)) * 256
		local lo = (PB_Byte buffer (b+3)) + (PB_Byte buffer (b+4)) * 256
		append verts [2 + v, hi, lo]
	)
	for k = verts.count to (total - 1) do append verts [k, 0, 0]

	local f = for j = 0 to (total / 3 - 1) collect [3*j+1, 3*j+2, 3*j+3]
	return #(verts, f)
)

-- Build a single chunk mesh from a slice of bytes
fn PB_EncodeChunk buffer chunkIdx chunkCount meshName magic =
(
	local d = PB_ChunkData buffer chunkIdx chunkCount magic
	return (mesh faces:d[2] vertices:d[1] name:meshName)
)

-- Encode a byte array (values 0..255) into one or more meshes.
-- With compress:true the whole payload is RLE-compressed first, but only
-- if that actually makes it smaller (the magic byte records which).
fn Encode buffer baseName:"m_encoded" compress:true =
(
	local meshes = #()
	local magic = PB_MAGIC
	if compress then
	(
		local packed = PB_Compress buffer
		if packed.count < buffer.count then (buffer = packed; magic = PB_MAGIC_RLE)
	)
	local total = buffer.count
	local chunkCount = amax 1 ((total + PB_CHUNK_BYTES - 1) / PB_CHUNK_BYTES)

	for c = 0 to (chunkCount - 1) do
	(
		local first = c * PB_CHUNK_BYTES + 1
		local last = amin total (first + PB_CHUNK_BYTES - 1)
		local slice = for i = first to last collect buffer[i]
		local num = (c + 1) as string
		while num.count < 3 do num = "0" + num
		append meshes (PB_EncodeChunk slice c chunkCount (baseName + "_" + num) magic)
	)
	return meshes
)

fn PB_Int f = (floor ((abs f) + 0.5)) as integer
fn PB_Hi v sc sw = if sw then PB_Int (v.z * sc) else PB_Int (v.y * sc)
fn PB_Lo v sc sw = if sw then PB_Int (v.y * sc) else PB_Int (v.z * sc)

-- Decode one chunk from an array of vertex positions (any order).
-- Returns #(chunkIdx, chunkCount, bytes, isCompressed) or undefined.
-- The position scale (exporter's unit scale) is detected from the data.
fn PB_DecodeVerts verts swapYZ:false =
(
	if verts.count < 3 then return undefined

	-- seq 0 has x = 0 and seq 1 has the next smallest x, which equals the scale
	local xs = for v in verts collect (abs v.x)
	sort xs
	if xs[2] <= 0.0 then return undefined
	local sc = 1.0 / xs[2]

	local lookup = #()
	lookup.count = verts.count
	for v in verts do
	(
		local seq = PB_Int (v.x * sc)
		if seq < verts.count then lookup[seq + 1] = v
	)
	if lookup[1] == undefined or lookup[2] == undefined then return undefined

	local h = lookup[1]
	local hy = PB_Hi h sc swapYZ
	local nLow = PB_Lo h sc swapYZ
	local magic = (mod hy 256) as integer
	if magic != PB_MAGIC and magic != PB_MAGIC_RLE then return undefined
	local chunkIdx = (hy / 256) as integer
	local v2 = PB_Hi lookup[2] sc swapYZ
	local sum = (mod v2 256) as integer
	local chunkCount = (v2 / 256) as integer
	local n = nLow + (PB_Lo lookup[2] sc swapYZ) * 65536

	local bytes = #()
	local dataVerts = (n + 3) / 4
	for v = 0 to (dataVerts - 1) do
	(
		local vt = lookup[3 + v]
		if vt == undefined then return undefined
		local hi = PB_Hi vt sc swapYZ
		local lo = PB_Lo vt sc swapYZ
		join bytes #((mod hi 256) as integer, (hi / 256) as integer, (mod lo 256) as integer, (lo / 256) as integer)
	)
	bytes.count = n

	local check = 0
	for b in bytes do check += b
	if (mod check 256) != sum then return undefined

	return #(chunkIdx, chunkCount, bytes, (magic == PB_MAGIC_RLE))
)

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

-- Decode one mesh or an array of chunk meshes (any order). Returns bytes or undefined
fn Decode piggybacked =
(
	local meshes = if classOf piggybacked == Array then piggybacked else #(piggybacked)
	local chunks = #()
	for m in meshes do
	(
		local verts = for i = 1 to m.numverts collect (getVert m i)
		local c = PB_DecodeVerts verts
		if c == undefined then return undefined
		append chunks c
	)
	return (PB_Assemble chunks)
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

-- In-memory round trip test (no export involved)
fn TestIt =
(
	local ok = true

	-- Strings of several lengths (covers all padding cases)
	for msg in #("This is my secret message!", "a", "ab", "abc", "abcd") do
	(
		local meshes = Encode (EncodeString msg)
		local outMsg = DecodeString (Decode meshes)
		format " In: %\nOut: %\n" msg outMsg
		if outMsg != msg then ok = false
		delete meshes
	)

	-- All byte values, larger than the vertex count, forcing multiple chunks
	local oldChunk = PB_CHUNK_BYTES
	PB_CHUNK_BYTES = 1000
	local big = for i = 0 to 2999 collect (mod (i * 7) 256 as integer)
	local meshes = Encode big
	local back = Decode meshes
	if back == undefined or back.count != big.count then ok = false
	else for i = 1 to big.count do if back[i] != big[i] then ok = false
	format "Multi-chunk: % meshes, %\n" meshes.count (if ok then "ok" else "FAILED")
	delete meshes
	PB_CHUNK_BYTES = oldChunk

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

	-- Compressed encode/decode through the meshes (zeros compress, so magic 84 is used)
	local zeros = for i = 1 to 5000 collect 0
	local zm = Encode zeros
	local zback = Decode zm
	local zsame = (zback != undefined and zback.count == zeros.count)
	format "Compressed mesh: % verts for % bytes, %\n" zm[1].numverts zeros.count (if zsame then "ok" else "FAILED")
	if not zsame then ok = false
	delete zm

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

-- Encode bytes and export the chunk meshes with the DSiegeUtils exporter.
-- Meshes get a standard material because the quad-menu export path refuses unmaterialed objects.
fn PiggybackExport buffer =
(
	local meshes = undefined
	try (disableSceneRedraw()) catch ()
	with undo off with redraw off
	(
	meshes = Encode buffer
	for m in meshes do
	(
		if m.material == undefined then m.material = standardMaterial name:"pb_mat"
		select m
		format "Exporting %...\n" m.name
		-- Destination comes from the Naming Key (BuildASPLocation) under %out%/art, not a dialog.
		-- The node name prefix picks the exporter: M_ -> ASP, T_ -> SNO, A_ -> PRS.
		local n = dsExportSelected noPrompt:true canStomp:true makePath:true
		format "  exported % file(s)\n" n
	)
	)
	try (enableSceneRedraw()) catch ()
	return meshes
)

-- Quick test: export a short text message through the ASP exporter
fn TestExport =
(
	return (PiggybackExport (EncodeString "This is my secret message!"))
)


-- Deterministic test payload (the Python extractor's --verify uses the same formula)
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

-- Export one single-chunk mesh per size to find the ASP exporter's limits.
-- Files: m_pbtest<size>_001.ASP in the art/meshes output folder.
fn LimitTest sizes =
(
	local oldChunk = PB_CHUNK_BYTES
	-- Same speed-ups as ASPImport.ms / StitchTools.ms: nothing is drawn or kept for undo
	try (disableSceneRedraw()) catch ()
	with undo off with redraw off
	(
	for s in sizes do
	(
		PB_Log ("size " + (s as string) + " bytes: building...")
		PB_CHUNK_BYTES = s + 1
		local t0 = timestamp()
		local data = PB_TestPattern s
		PB_Log ("  pattern built in " + ((timestamp() - t0) as string) + " ms")
		t0 = timestamp()
		local meshes = Encode data baseName:("m_pbtest" + (s as string))
		PB_Log ("  encoded to " + (meshes[1].numverts as string) + " verts in " + ((timestamp() - t0) as string) + " ms; exporting...")
		for m in meshes do
		(
			m.material = standardMaterial name:"pb_mat"
			select m
			t0 = timestamp()
			local n = try (dsExportSelected noPrompt:true canStomp:true makePath:true) catch ("ERROR: dsExportSelected failed (gmax has no getCurrentException; the Listener shows the message if run raw)")
			PB_Log ("  export result: " + (n as string) + " in " + ((timestamp() - t0) as string) + " ms")
		)
		delete meshes
		clearUndoBuffer()
	)
	)
	try (enableSceneRedraw()) catch ()
	PB_CHUNK_BYTES = oldChunk
	PB_Log "LimitTest done"
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

-- Encode bytes and save them in a .gmax scene file with saveMaxFile (route B, dense layout).
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
-- Files: piggyback_dense_<size>.gmax in the scene folder; check each with extract_piggyback.py --verify.
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
Then read the output files outside gmax with scripts/Tests/tools/extract_piggyback.py.

-- 1. in-memory checks, no files (expect PASS)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); TestIt(); TestDense(); setListenerSel #(0,0)

-- 2. route A: export a small payload through DSiegeUtils (file goes to %out%/art/meshes)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); TestExport(); setListenerSel #(0,0)
delete (for o in objects where (matchPattern o.name pattern:"m_encoded_*") collect o)

-- 3. route A limit probe (264000 bytes = 66002 vertices is past the 16-bit cap and produces no file)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); LimitTest #(260000, 262000, 264000); setListenerSel #(0,0)

-- 4. route B: save a 1 MB payload in a scene file, and a size probe
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); TestSaveDense 1000000; setListenerSel #(0,0)
clearlistener(); filein ((GetDir #scripts) +"\\Tests\\piggyback.ms"); LimitTestSave #(1000000, 5000000); setListenerSel #(0,0)

-- 5. the DataOut wrapper (writes DataOut_hello.gmax in the scene folder)
clearlistener(); filein ((GetDir #scripts) +"\\RigTools\\DataOut.ms"); DataOutSendString "hello" "Hello from gmax!"; setListenerSel #(0,0)
*/
