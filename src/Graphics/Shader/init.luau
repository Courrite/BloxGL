--!strict
--!native

local Shader = {}
Shader.__index = Shader

local readu32 = buffer.readu32
local writeu32 = buffer.writeu32
local band = bit32.band
local rshift = bit32.rshift
local lshift = bit32.lshift

export type PixelCallback = (
	worldX: number,
	worldY: number,
	normX: number,
	normY: number,
	r: number,
	g: number,
	b: number,
	a: number,
	uniforms: { [number]: any }
) -> (number, number, number, number, number?, number?)

export type Shader = typeof(setmetatable(
	{} :: {
		_callback: PixelCallback?,
		_uniforms: { [number]: any },
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

function Shader.SetUniform(self: Shader, location: number, value: any)
	self._uniforms[location] = value
end

function Shader.GetUniform(self: Shader, location: number): any?
	return self._uniforms[location]
end

function Shader.GetUniforms(self: Shader): { [number]: any }
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
	customUniforms: { [number]: any }?,
	tileOffset: Vector2?,
	tileSize: Vector2?,
	fullSrcBuf: buffer?
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

	local tOff = tileOffset or Vector2.zero
	local tSize = tileSize or dimensions

	local minGX = math.floor(tOff.X)
	local minGY = math.floor(tOff.Y)
	local tileW = math.floor(tSize.X)
	local tileH = math.floor(tSize.Y)
	local maxGX = math.min(width - 1, minGX + tileW - 1)
	local maxGY = math.min(height - 1, minGY + tileH - 1)

	local srcBuf: buffer
	if fullSrcBuf then
		srcBuf = fullSrcBuf
	else
		local neededLen = buffer.len(buf)
		if not self._scratchBuf or buffer.len(self._scratchBuf) < neededLen then
			self._scratchBuf = buffer.create(neededLen)
		end
		srcBuf = self._scratchBuf :: buffer
		buffer.copy(srcBuf, 0, buf, 0, neededLen)
	end

	local boundsW = windowSize and windowSize.X or dimensions.X
	local boundsH = windowSize and windowSize.Y or dimensions.Y
	local invBoundsW = boundsW > 1 and 1 / (boundsW - 1) or 0
	local invBoundsH = boundsH > 1 and 1 / (boundsH - 1) or 0

	local uniforms = customUniforms or self._uniforms
	local org = origin or Vector2.zero
	local originX = org.X
	local originY = org.Y

	local INV_255 = 1 / 255
	local scale = self._downscale

	local stepNormX = scale * invBoundsW
	local startWorldX = originX + minGX
	local startNormX = startWorldX * invBoundsW

	for gy = minGY, maxGY, scale do
		local worldY = originY + gy
		local normY = worldY * invBoundsH
		local localGY = gy - minGY
		local rowOffset = gy * width

		local worldX = startWorldX
		local normX = startNormX

		for gx = minGX, maxGX, scale do
			local srcOffset = (rowOffset + gx) * 4
			local rgba = readu32(srcBuf, srcOffset)

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

				local sr, sg, sb, sa
				if rawGX < 0 or rawGX > width - 1 or rawGY < 0 or rawGY > height - 1 then
					sr, sg, sb, sa = 0, 0, 0, 0
				else
					local sampleOffset = (rawGY * width + rawGX) * 4
					local sRgba = readu32(srcBuf, sampleOffset)
					sr = band(sRgba, 0xFF)
					sg = band(rshift(sRgba, 8), 0xFF)
					sb = band(rshift(sRgba, 16), 0xFF)
					sa = rshift(sRgba, 24)
				end

				nr = (sr * INV_255) * nr
				ng = (sg * INV_255) * ng
				nb = (sb * INV_255) * nb
				na = sa
			end

			local outR = math.clamp(math.floor(nr), 0, 255)
			local outG = math.clamp(math.floor(ng), 0, 255)
			local outB = math.clamp(math.floor(nb), 0, 255)
			local outA = math.clamp(math.floor(na), 0, 255)

			local outRgba = bit32.bor(outR, lshift(outG, 8), lshift(outB, 16), lshift(outA, 24))

			local localGX = gx - minGX
			local dstOffset = (localGY * tileW + localGX) * 4

			if scale == 1 then
				writeu32(buf, dstOffset, outRgba)
			else
				for dy = 0, scale - 1 do
					local targetY = localGY + dy
					if targetY >= tileH then
						break
					end
					local targetRow = targetY * tileW
					for dx = 0, scale - 1 do
						local targetX = localGX + dx
						if targetX >= tileW then
							break
						end
						writeu32(buf, (targetRow + targetX) * 4, outRgba)
					end
				end
			end

			worldX += scale
			normX += stepNormX
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
