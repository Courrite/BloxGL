--!strict

local Shader = {}
Shader.__index = Shader

local readu32 = buffer.readu32
local writeu32 = buffer.writeu32
local band = bit32.band
local rshift = bit32.rshift
local lshift = bit32.lshift

export type UniformValue = number | Vector2 | { Vector2 }

export type PixelCallback = (
	worldX: number,
	worldY: number,
	normX: number,
	normY: number,
	r: number,
	g: number,
	b: number,
	a: number,
	uniforms: { [number]: UniformValue }
) -> (number, number, number, number, number?, number?)

export type Shader = typeof(setmetatable(
	{} :: {
		_callback: PixelCallback?,
		_uniforms: { [number]: UniformValue },
		_scratchBuf: buffer?,
		_downscale: number,
	},
	Shader
))

local function new(module: ModuleScript, downscale: number?): Shader
	local callback: PixelCallback = (require)(module)

	return setmetatable({
		_callback = callback,
		_uniforms = {},
		_scratchBuf = nil,
		_downscale = math.max(1, math.floor(downscale or 2)),
	}, Shader) :: Shader
end

function Shader.SetUniform(self: Shader, location: number, value: UniformValue)
	self._uniforms[location] = value
end

function Shader.GetUniform(self: Shader, location: number): UniformValue?
	return self._uniforms[location]
end

function Shader.GetUniforms(self: Shader): { [number]: UniformValue }
	return self._uniforms
end

function Shader.SetDownscale(self: Shader, downscale: number)
	self._downscale = math.max(1, math.floor(downscale))
end

function Shader.ApplyToBuffer(
	self: Shader,
	buf: buffer,
	dimensions: Vector2,
	origin: Vector2?,
	windowSize: Vector2?,
	customUniforms: { [number]: UniformValue }?
)
	local callback = self._callback
	if not callback then
		return
	end

	local width = math.floor(dimensions.X)
	local height = math.floor(dimensions.Y)
	if width <= 0 or height <= 0 then
		return
	end

	local neededLen = buffer.len(buf)
	if not self._scratchBuf or buffer.len(self._scratchBuf) < neededLen then
		self._scratchBuf = buffer.create(neededLen)
	end
	local srcBuf = self._scratchBuf :: buffer
	buffer.copy(srcBuf, 0, buf, 0, neededLen)

	local boundsW = windowSize and windowSize.X or dimensions.X
	local boundsH = windowSize and windowSize.Y or dimensions.Y
	local invBoundsW = boundsW > 1 and 1 / (boundsW - 1) or 0
	local invBoundsH = boundsH > 1 and 1 / (boundsH - 1) or 0

	local uniforms = customUniforms or self._uniforms
	local org = origin or Vector2.zero
	local originX = org.X
	local originY = org.Y

	local INV_255 = 1 / 255
	local maxGX = width - 1
	local maxGY = height - 1
	local scale = self._downscale

	for gy = 0, maxGY, scale do
		local worldY = originY + gy
		local normY = worldY * invBoundsH

		for gx = 0, maxGX, scale do
			local offset = (gy * width + gx) * 4
			local rgba = readu32(srcBuf, offset)

			local worldX = originX + gx
			local normX = worldX * invBoundsW

			local r = band(rgba, 0xFF)
			local g = band(rshift(rgba, 8), 0xFF)
			local b = band(rshift(rgba, 16), 0xFF)
			local a = rshift(rgba, 24)

			local nr, ng, nb, na, dispNormX, dispNormY = callback(worldX, worldY, normX, normY, r, g, b, a, uniforms)

			if (dispNormX and dispNormX ~= 0) or (dispNormY and dispNormY ~= 0) then
				local sampleWorldX = (normX + (dispNormX or 0)) * boundsW
				local sampleWorldY = (normY + (dispNormY or 0)) * boundsH

				local rawGX = math.floor(sampleWorldX - originX)
				local rawGY = math.floor(sampleWorldY - originY)

				local sampleGX = rawGX < 0 and 0 or rawGX > maxGX and maxGX or rawGX
				local sampleGY = rawGY < 0 and 0 or rawGY > maxGY and maxGY or rawGY
				local sampleOffset = (sampleGY * width + sampleGX) * 4

				local sRgba = readu32(srcBuf, sampleOffset)
				local sr = band(sRgba, 0xFF)
				local sg = band(rshift(sRgba, 8), 0xFF)
				local sb = band(rshift(sRgba, 16), 0xFF)
				local sa = rshift(sRgba, 24)

				nr = (sr * INV_255) * nr
				ng = (sg * INV_255) * ng
				nb = (sb * INV_255) * nb
				na = sa
			end

			local outR = nr < 0 and 0 or nr > 255 and 255 or nr
			local outG = ng < 0 and 0 or ng > 255 and 255 or ng
			local outB = nb < 0 and 0 or nb > 255 and 255 or nb
			local outA = na < 0 and 0 or na > 255 and 255 or na

			local outRgba = bit32.bor(outR, lshift(outG, 8), lshift(outB, 16), lshift(outA, 24))

			for dy = 0, scale - 1 do
				local targetY = gy + dy
				if targetY > maxGY then
					break
				end
				local targetRow = targetY * width
				for dx = 0, scale - 1 do
					local targetX = gx + dx
					if targetX > maxGX then
						break
					end
					writeu32(buf, (targetRow + targetX) * 4, outRgba)
				end
			end
		end
	end
end

function Shader.ApplyToImage(self: Shader, img: EditableImage, origin: Vector2?, windowSize: Vector2?)
	local size = img.Size
	local org = origin or Vector2.zero
	local buf = img:ReadPixelsBuffer(Vector2.zero, size)
	self:ApplyToBuffer(buf, size, org, windowSize)
	img:WritePixelsBuffer(Vector2.zero, size, buf)
end

return new
