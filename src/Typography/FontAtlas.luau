--!strict

local Texture = require("../Graphics/Texture")

local FontAtlas = {}
FontAtlas.__index = FontAtlas

export type FontAtlas = typeof(setmetatable(
	{} :: {
		Size: Vector2,
		Texture: Texture.Texture,

		_buffer: buffer,
		_currentX: number,
		_currentY: number,
		_rowHeight: number,
	},
	FontAtlas
))

local function new(size: Vector2): FontAtlas
	local self = setmetatable({
		Size = size,
		Texture = Texture(size),

		_buffer = buffer.create(size.X * size.Y * 4),
		_currentX = 0,
		_currentY = 0,
		_rowHeight = 0,
	}, FontAtlas) :: FontAtlas
	return self
end

function FontAtlas.TryPack(self: FontAtlas, bitmap: { number }, size: Vector2): Vector2?
	if self._currentX + size.X > self.Size.X then
		self._currentX = 0
		self._currentY += self._rowHeight
		self._rowHeight = 0
	end

	if self._currentY + size.Y > self.Size.Y then
		return nil
	end

	local atlasX = self._currentX
	local atlasY = self._currentY

	-- NOTE: gy loop is outside gx loop because 2d image buffers use row-major memory layout
	local atlasWidth = self.Size.X
	local glyphW = math.floor(size.X)
	local glyphH = math.floor(size.Y)
	local subBuf = buffer.create(glyphW * glyphH * 4)

	for gy = 0, glyphH - 1 do
		for gx = 0, glyphW - 1 do
			local alpha = bitmap[gy * glyphW + gx + 1] or 0
			local px = atlasX + gx
			local py = atlasY + gy
			local offset = (py * atlasWidth + px) * 4

			buffer.writeu8(self._buffer, offset, alpha)
			buffer.writeu8(self._buffer, offset + 1, alpha)
			buffer.writeu8(self._buffer, offset + 2, alpha)
			buffer.writeu8(self._buffer, offset + 3, alpha)

			local subOffset = (gy * glyphW + gx) * 4
			buffer.writeu8(subBuf, subOffset, alpha)
			buffer.writeu8(subBuf, subOffset + 1, alpha)
			buffer.writeu8(subBuf, subOffset + 2, alpha)
			buffer.writeu8(subBuf, subOffset + 3, alpha)
		end
	end

	-- advance packing cursor
	self._currentX += size.X
	self._rowHeight = math.max(self._rowHeight, size.Y)

	local editableImage = self.Texture:GetEditableImage()
	editableImage:WritePixelsBuffer(Vector2.new(atlasX, atlasY), size, subBuf)

	return Vector2.new(atlasX, atlasY)
end

return new
