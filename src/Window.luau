--!strict

local EditableImage = require("./Roblox/EditableImage")
local ScreenGui = require("./Roblox/ScreenGui")
local ImageLabel = require("./Roblox/ImageLabel")

local Window = {}
Window.__index = Window

const EDITABLE_IMAGE_SIZE_LIMIT = 1024

local function CalculateEditableImagesNeededForMatrix(x: number, y: number): { { Vector2 } }
	local cols = math.ceil(x / EDITABLE_IMAGE_SIZE_LIMIT)
	local rows = math.ceil(y / EDITABLE_IMAGE_SIZE_LIMIT)

	local quads: { { Vector2 } } = {}

	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local posX = EDITABLE_IMAGE_SIZE_LIMIT * i
			local posY = EDITABLE_IMAGE_SIZE_LIMIT * j

			-- clamp the width and height to the remaining width/height of the canvas
			local width = math.min(EDITABLE_IMAGE_SIZE_LIMIT, x - posX)
			local height = math.min(EDITABLE_IMAGE_SIZE_LIMIT, y - posY)

			table.insert(quads, {
				Vector2.new(posX, posY),
				Vector2.new(width, height),
			})
		end
	end

	return quads
end

function Window.Clear(self: Window, color: Color3)
	for idx, image in self._images do
		local size = self._quads[idx][2]
		image:DrawRectangle(Vector2.zero, size, color, 0, Enum.ImageCombineType.Overwrite)
	end
end

function Window.GetQuads(self: Window): { { Vector2 } }
	return self._quads
end

function Window.GetImages(self: Window): { EditableImage }
	return self._images
end

export type Window = typeof(setmetatable(
	{} :: {
		Size: Vector2,
		_quads: { { Vector2 } },
		_images: { EditableImage },
	},
	Window
))

local function new(size: Vector2): Window
	local self = setmetatable({
		Size = size,
		_quads = {},
		_images = {},
	}, Window) :: Window

	local quads = CalculateEditableImagesNeededForMatrix(size.X, size.Y)
	self._quads = quads

	for i, quad in quads do
		local quadSize = quad[2]
		self._images[i] = EditableImage(quadSize)
	end

	local screenGui = ScreenGui()
	for i, quad in self._quads do
		local quadPos = quad[1]
		local quadSize = quad[2]

		local label = ImageLabel(quadPos, quadSize)
		label.ImageContent = Content.fromObject(self._images[i])
		label.Parent = screenGui
	end

	return self
end

return new
