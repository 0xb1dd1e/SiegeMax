--***************************************************
fn VectorsAreEqual v1 v2 tol =
(
	local v = length (v1-v2)
	return v <= tol
)

--***************************************************
fn IsRedundantPosition a b c tol = 
(
	local delta1 = b[1] - a[1]
	local delta2 = c[1] - a[1]
	local alpha = delta1/delta2
	local interp = (a[2] * (1-alpha)) + (c[2]*alpha)
	local eq = (VectorsAreEqual interp b[2] tol)
--	format "%, %, % [%] = %\n" a[2] b[2] c[2] interp eq
	return eq
)

--***************************************************
fn dscb_ReducePosKeyList kl tol =
(
	
	local keepers = #()	
	
	if (kl.count > 0) then
	(
	
		local i = 1
		local j = 3
		
		keepers = #(kl[1])
		
		while j <= kl.count do
		(
			if not (IsRedundantPosition kl[i] kl[j-1] kl[j] tol) then
			(
				append keepers  kl[j-1]
				i = j-1
			)
			j += 1
		)
		if kl.count > 1 then
		(
			if not (VectorsAreEqual keepers[keepers.count][2] kl[kl.count][2] tol) then
			(
				append keepers  kl[kl.count]
			)
		)
	)
	
	return keepers 
)


--***************************************************
fn QuatsAreEqual q1 q2 tol =
(
	local ir = (inverse q1) * q2
	if (abs ir.x) < tol then ir.x = 0
	if (abs ir.y) < tol then ir.y = 0
	if (abs ir.z) < tol then ir.z = 0
	if ((abs ir.w)-1) < tol then ir.w = 1
	return IsIdentity ir
)

--***************************************************
fn IsRedundantRotation a b c tol = 
(
	if a[2].w < 0 then a[2] = -a[2]
	if b[2].w < 0 then b[2] = -b[2]
	if c[2].w < 0 then c[2] = -c[2]
	
	local delta1 = b[1] - a[1]
	local delta2 = c[1] - a[1]
	local alpha = delta1/delta2
	local interp = slerp a[2] c[2] alpha
	local eq = QuatsAreEqual interp b[2] tol
--	if (eq) then
--	(
--		format "%: %, %, % [%] = %\n" b[1] a[2] b[2] c[2] interp eq
--	)
	
	
	return eq 
)

--***************************************************
fn IsApproaching180Degrees a b = 
(
	if a.w < 0 then a = -a
	if b.w < 0 then b = -b
	
	diffq = (inverse a) * b
	
--	format "DIFF ANG %\n" diffq.angle

	dqa = diffq.angle
	
	while (dqa > 180.0) do
	(
		dqa -= 360.0 
	)
	
	while (dqa < -180.0) do
	(
		dqa += 360.0
	)
	
	return (180.0-(abs dqa)) < 2.0
	
)

--***************************************************
fn dscb_ReduceRotKeyList kl tol =
(
	local keepers = #()
	
	if (kl.count > 0) then
	(
	
		keepers = #(kl[1])
		
		local all_equal = true
		
		for k = 2 to kl.count do
		(
			if not (QuatsAreEqual kl[1][2] kl[k][2] 0) then
			(
				all_equal = false
			)
		)
		
		if (not all_equal) then 
		(
		
			local i = 1
			local j = 3

			while j <= kl.count do
			(

				-- Assume we don't need to keep this, then collect the error
				local keep = (IsApproaching180Degrees kl[i][2] kl[j][2])
				
				--if (keep) then
				--(
				--	format "The rotation delta is close to 180 degrees, keeping key @ %\n" (kl[j-1][1])
				--)				
				
				if ( keep or (not (IsRedundantRotation kl[i] kl[j-1] kl[j] tol))) then
				(
					append keepers  kl[j-1]
					i = j-1
				)
				j += 1

			)
			
			if (kl.count) > 1 then
			(
				if not (QuatsAreEqual keepers[keepers.count][2] kl[kl.count][2] tol) then
				(
					append keepers  kl[kl.count]
				)
			)
		)
	)

	return keepers 
)

