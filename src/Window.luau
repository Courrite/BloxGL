--!strict
local Players = game:GetService("Players")

local ShaderWorker = script.Parent.Graphics.Shader.ShaderWorker

local EditableImage = require("./Roblox/EditableImage")
local ScreenGui = require("./Roblox/ScreenGui")
local ImageLabel = require("./Roblox/ImageLabel")

local plr = Players.LocalPlayer
local scripts = plr.PlayerScripts

local Window = {}
Window.__index = Window

local EDITABLE_IMAGE_SIZE_LIMIT = 1024

local function CalculateEditableImagesNeededForMatrix(x: number, y: number): { { Vector2 } }
	local cols = math.ceil(x / EDITABLE_IMAGE_SIZE_LIMIT)
	local rows = math.ceil(y / EDITABLE_IMAGE_SIZE_LIMIT)

	local quads: { { Vector2 } } = {}

	local targetW = math.ceil(x / cols)
	local targetH = math.ceil(y / rows)

	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local posX = targetW * i
			local posY = targetH * j

			local width = math.min(targetW, x - posX)
			local height = math.min(targetH, y - posY)

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

function Window.ApplyShaderAsync(self: Window, module: ModuleScript, downscale: number?)
	for i, relatedActors in self._actors do
		local img = self._images[i]
		local fullSize = img.Size
		local fullBuf = img:ReadPixelsBuffer(Vector2.zero, fullSize)
		local quadOrigin = self._quads[i][1]

		for j, actor in relatedActors do
			local tile = self._subTiles[j]
			if tile and tile[2].X > 0 and tile[2].Y > 0 then
				actor:SendMessage(
					"ApplyShaderTile",
					module,
					img,
					fullBuf,
					quadOrigin,
					self.Size,
					downscale,
					tile[1],
					tile[2]
				)
			end
		end
	end
end

function Window.ApplyShaderToImageAsync(
	self: Window,
	module: ModuleScript,
	img: EditableImage,
	origin: Vector2?,
	downscale: number?
)
	local fullSize = img.Size
	local fullBuf = img:ReadPixelsBuffer(Vector2.zero, fullSize)
	local org = origin or Vector2.zero

	local actors = self._actors[1]
	if actors then
		for j, actor in actors do
			local tile = self._subTiles[j]
			if tile and tile[2].X > 0 and tile[2].Y > 0 then
				actor:SendMessage("ApplyShaderTile", module, img, fullBuf, org, self.Size, downscale, tile[1], tile[2])
			end
		end
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
		_actors: { { Actor } },
		_subTiles: { { Vector2 } },
	},
	Window
))

local function new(size: Vector2): Window
	local self = setmetatable({
		Size = size,

		_quads = {},
		_images = {},
		_actors = {},
		_subTiles = {},
		_pixelBuffers = {},
	}, Window) :: Window

	local quads = CalculateEditableImagesNeededForMatrix(size.X, size.Y)
	self._quads = quads

	local width = size.X
	local quadHeight = math.ceil(size.Y / 4)

	self._subTiles = {
		{ Vector2.new(0, 0), Vector2.new(width, quadHeight) },
		{ Vector2.new(0, quadHeight), Vector2.new(width, quadHeight) },
		{ Vector2.new(0, quadHeight * 2), Vector2.new(width, quadHeight) },
		{ Vector2.new(0, quadHeight * 3), Vector2.new(width, size.Y - quadHeight * 3) },
	}

	for i, quad in quads do
		local quadSize = quad[2]
		self._images[i] = EditableImage(quadSize)

		self._actors[i] = {}

		for j = 1, 4 do
			local actor = ShaderWorker:Clone()
			actor.Parent = scripts
			actor.Worker.Enabled = true

			self._actors[i][j] = actor
		end
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
