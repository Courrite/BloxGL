--!strict
--!native
--!optimize 2

local TIME_UNIFORM = 1
local BOUNDS_UNIFORM = 2

return function(
	worldX: number,
	worldY: number,
	normX: number,
	normY: number,
	r: number,
	g: number,
	b: number,
	a: number,
	uniforms: { [number]: any }?
)
	local bounds = uniforms and uniforms[BOUNDS_UNIFORM]
	if bounds then
		if normX < bounds[1] or normY < bounds[2] or normX > bounds[3] or normY > bounds[4] then
			return 0, 0, 0, 0, 0, 0
		end
	end

	local timeVal = uniforms and uniforms[TIME_UNIFORM] or os.clock()

	local pulse = math.sin(timeVal * 7.0)
	local isGlitching = pulse > 0.65

	local scanlineNoise = math.sin(normY * 60.0 + timeVal * 30.0)
	local glitchX = isGlitching and (scanlineNoise * 0.025) or (math.sin(normY * 10.0 + timeVal * 2.0) * 0.004)
	local glitchY = isGlitching and (math.cos(normX * 40.0 + timeVal * 20.0) * 0.008) or 0

	local phase = normX * 8.0 + timeVal * 3.0
	local rTint = math.sin(phase) * 0.5 + 0.5
	local gTint = math.sin(phase + 2.094395) * 0.5 + 0.5
	local bTint = math.sin(phase + 4.188790) * 0.5 + 0.5

	local rOut = math.clamp(180 + rTint * 75, 0, 255)
	local gOut = math.clamp(100 + gTint * 155, 0, 255)
	local bOut = math.clamp(200 + bTint * 55, 0, 255)

	return rOut, gOut, bOut, a, glitchX, glitchY
end
