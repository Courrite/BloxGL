--!strict

local Shader = {}
Shader.__index = Shader

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
	},
	Shader
))

local function new(callback: PixelCallback?): Shader
	return setmetatable({
		_callback = callback,
		_uniforms = {},
		_scratchBuf = nil,
	}, Shader) :: Shader
end

function Shader.SetUniform(self: Shader, location: number, value: UniformValue)
	self._uniforms[location] = value
end

function Shader.GetUniform(self: Shader, location: number): UniformValue?
	return self._uniforms[location]
end

function Shader.ApplyToBuffer(
	self: Shader,
	buf: buffer,
	dimensions: Vector2,
	origin: Vector2,
	clipRect: Rect?,
	windowSize: Vector2?
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

	local startX = 0
	local startY = 0
	local endX = width - 1
	local endY = height - 1

	if clipRect then
		startX = math.clamp(math.floor(clipRect.Min.X), 0, width - 1)
		startY = math.clamp(math.floor(clipRect.Min.Y), 0, height - 1)
		endX = math.clamp(math.floor(clipRect.Max.X), 0, width - 1)
		endY = math.clamp(math.floor(clipRect.Max.Y), 0, height - 1)
	end

	local boundsW = if windowSize then windowSize.X else dimensions.X
	local boundsH = if windowSize then windowSize.Y else dimensions.Y
	local invBoundsW = if boundsW > 1 then 1 / (boundsW - 1) else 0
	local invBoundsH = if boundsH > 1 then 1 / (boundsH - 1) else 0

	local uniforms = self._uniforms
	local originX = origin.X
	local originY = origin.Y

	local neededLen = buffer.len(buf)
	if not self._scratchBuf or buffer.len(self._scratchBuf) < neededLen then
		self._scratchBuf = buffer.create(neededLen)
	end
	local srcBuf = self._scratchBuf :: buffer
	buffer.copy(srcBuf, 0, buf, 0, neededLen)

	for gy = startY, endY do
		local worldY = originY + gy
		local normY = worldY * invBoundsH
		local rowOffset = gy * width

		for gx = startX, endX do
			local offset = (rowOffset + gx) * 4
			local worldX = originX + gx
			local normX = worldX * invBoundsW

			local r = buffer.readu8(srcBuf, offset)
			local g = buffer.readu8(srcBuf, offset + 1)
			local b = buffer.readu8(srcBuf, offset + 2)
			local a = buffer.readu8(srcBuf, offset + 3)

			local nr, ng, nb, na, dispX, dispY = callback(worldX, worldY, normX, normY, r, g, b, a, uniforms)

			if (dispX and dispX ~= 0) or (dispY and dispY ~= 0) then
				local sampleGX = math.clamp(math.floor(gx + (dispX or 0)), 0, width - 1)
				local sampleGY = math.clamp(math.floor(gy + (dispY or 0)), 0, height - 1)
				local sampleOffset = (sampleGY * width + sampleGX) * 4

				local sr = buffer.readu8(srcBuf, sampleOffset)
				local sg = buffer.readu8(srcBuf, sampleOffset + 1)
				local sb = buffer.readu8(srcBuf, sampleOffset + 2)
				local sa = buffer.readu8(srcBuf, sampleOffset + 3)

				nr, ng, nb, na = callback(worldX, worldY, normX, normY, sr, sg, sb, sa, uniforms)
			end

			buffer.writeu8(buf, offset, math.clamp(math.floor(nr), 0, 255))
			buffer.writeu8(buf, offset + 1, math.clamp(math.floor(ng), 0, 255))
			buffer.writeu8(buf, offset + 2, math.clamp(math.floor(nb), 0, 255))
			buffer.writeu8(buf, offset + 3, math.clamp(math.floor(na), 0, 255))
		end
	end
end

function Shader.ApplyToImage(self: Shader, img: EditableImage, origin: Vector2?, clipRect: Rect?, windowSize: Vector2?)
	local size = img.Size
	local org = origin or Vector2.zero
	local buf = img:ReadPixelsBuffer(Vector2.zero, size)
	self:ApplyToBuffer(buf, size, org, clipRect, windowSize)
	img:WritePixelsBuffer(Vector2.zero, size, buf)
end

return new
