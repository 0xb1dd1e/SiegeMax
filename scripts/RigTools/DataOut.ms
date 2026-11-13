-- ****************************
-- DataOut: get data out of gmax
--
-- gmax cannot write files, so data is saved inside a .gmax scene file (the only file
-- gmax can write freely) as a payload hidden in a map channel. See scripts/Tests/piggyback.ms
-- for the codec and its limits. Read the result outside gmax with:
--
--   scripts\ClaudeLink\Extract-Piggyback.ps1 <file.gmax> [-Out out.bin] [-Text]
--
-- Usage from MAXScript:
--   DataOutSend "bake_idle" bytes               -- an array of integers 0..255
--   DataOutSendString "notes" "any text"
--   DataOutSendFloats "keys" #(1.0, 2.5, ...)   -- stored as 32-bit floats, 4 bytes each
--
-- Each call writes <scene dir>/DataOut_<label>.gmax and returns that path, or undefined on
-- failure. NOTE: saving renames the current scene to that file - check File > Save As before
-- saving your own work.
-- ****************************

-- The codec lives in the Tests folder; load it on first use
global DataOut_Loaded
if DataOut_Loaded == undefined then
(
	fileIn ((GetDir #scripts) + "/Tests/piggyback.ms")
	DataOut_Loaded = true
)

fn DataOut_Clean label =
(
	local out = ""
	for i = 1 to label.count do
	(
		local c = label[i]
		local code = bit.CharAsInt c
		local good = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or c == "_" or c == "-"
		out += (if good then c else "_")
	)
	if out == "" then out = "data"
	return out
)

fn DataOutSend label bytes =
(
	local path = (GetDir #scene) + "/DataOut_" + (DataOut_Clean label) + ".gmax"
	local ok = PiggybackSave bytes path
	if ok then
	(
		PB_Log ("DataOut: " + (bytes.count as string) + " bytes -> " + path)
		PB_Log ("  read with: Extract-Piggyback.ps1 \"" + path + "\"")
		return path
	)
	return undefined
)

fn DataOutSendString label s = DataOutSend label (EncodeString s)

fn DataOutSendFloats label vals = DataOutSend label (EncodeFloats vals)
