--!strict

local TIME_UNIFORM = 1

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
	local timeVal = uniforms and uniforms[TIME_UNIFORM] or os.clock()

	local dx = normX - 0.5
	local dy = normY - 0.5
	local distSq = dx * dx + dy * dy
	local dist = math.sqrt(distSq)
	local normD = dist * 2.0

	local invDist = dist > 0.0001 and 1 / dist or 0
	local dirX = dx * invDist
	local dirY = dy * invDist

	local rippleFactor = math.sin(normD * 20.0 - timeVal * 5.0) * 0.02
	local waveY = math.sin(normX * 12 + timeVal * 3.5) * 0.025

	local dispNormX = dirX * rippleFactor
	local dispNormY = dirY * rippleFactor + waveY

	local phase = (normD * 5 - timeVal * 2.5)
	local rWave = (math.sin(phase) * 0.5 + 0.5)
	local gWave = (math.sin(phase + 2.094) * 0.5 + 0.5)
	local bWave = (math.sin(phase + 4.188) * 0.5 + 0.5)

	return math.floor(rWave * 255), math.floor(gWave * 255), math.floor(bWave * 255), a, dispNormX, dispNormY
end
