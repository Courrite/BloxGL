--!strict

local Texture = require("./Texture")
local Window = require("../Window")

type Order = {
	texture: Texture.Texture,
	position: Vector2,
	size: Vector2,
	transparency: number,
	combineType: Enum.ImageCombineType,
}

local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch

export type SpriteBatch = typeof(setmetatable(
	{} :: {
		_window: Window.Window,
		_queue: { Order },
		_pixelCache: { [Color3]: Texture.Texture },
	},
	SpriteBatch
))

local function new(targetWindow: Window.Window): SpriteBatch
	return setmetatable({
		_window = targetWindow,
		_queue = {},
		_pixelCache = {},
	}, SpriteBatch) :: SpriteBatch
end

function SpriteBatch.Begin(self: SpriteBatch)
	table.clear(self._queue)
end

function SpriteBatch.Draw(
	self: SpriteBatch,
	texture: Texture.Texture,
	position: Vector2?,
	size: Vector2?,
	transparency: number?,
	combineType: Enum.ImageCombineType?
)
	table.insert(self._queue, {
		texture = texture,
		position = position or Vector2.zero,
		size = size or texture.Size,
		transparency = transparency or 0,
		combineType = combineType or Enum.ImageCombineType.AlphaBlend,
	})
end

function SpriteBatch.DrawRectangle(
	self: SpriteBatch,
	position: Vector2,
	size: Vector2,
	color: Color3,
	transparency: number?,
	combineType: Enum.ImageCombineType?
)
	local pixel: Texture.Texture = self._pixelCache[color]
	if not pixel then
		local p = Texture(Vector2.one)
		p:GetEditableImage():DrawRectangle(Vector2.zero, Vector2.one, color, 0, Enum.ImageCombineType.Overwrite)
		self._pixelCache[color] = p
		pixel = p
	end

	self:Draw(pixel, position, size, transparency, combineType)
end

function SpriteBatch.Flush(self: SpriteBatch)
	local quads = self._window:GetQuads()
	local images = self._window:GetImages()

	for _, order in self._queue do
		local pos = order.position
		local size = order.size
		local mode = order.combineType
		local editableImg = order.texture:GetEditableImage()

		for i, quad in quads do
			local tilePos = quad[1]
			local tileSize = quad[2]

			-- AABB overlap test against target tile quad
			if
				(pos.X < tilePos.X + tileSize.X)
				and (pos.X + size.X > tilePos.X)
				and (pos.Y < tilePos.Y + tileSize.Y)
				and (pos.Y + size.Y > tilePos.Y)
			then
				images[i]:DrawImage(pos - tilePos, editableImg, mode)
			end
		end
	end

	table.clear(self._queue)
end

function SpriteBatch.End(self: SpriteBatch)
	self:Flush()
end

return new
