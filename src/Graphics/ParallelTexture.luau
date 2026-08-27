--!strict
local Texture = require("./Texture")
local Window = require("../Window")

type Window = Window.Window
type Texture = Texture.Texture

local ParallelTexture = {}
ParallelTexture.__index = ParallelTexture

export type ParallelTexture = typeof(setmetatable(
	{} :: {
		Size: Vector2,
		_window: Window,
		_frontTex: Texture,
		_backTex: Texture,
		_frontImg: EditableImage,
		_backImg: EditableImage,
	},
	ParallelTexture
))

local function new(window: Window, size: Vector2): ParallelTexture
	local frontTex = Texture(size)
	local backTex = Texture(size)

	local self = setmetatable({
		Size = size,
		_window = window,
		_frontTex = frontTex,
		_backTex = backTex,
		_frontImg = frontTex:GetEditableImage(),
		_backImg = backTex:GetEditableImage(),
	}, ParallelTexture) :: ParallelTexture

	return self
end

function ParallelTexture.GetTexture(self: ParallelTexture): Texture
	return self._frontTex
end

function ParallelTexture.GetBackImage(self: ParallelTexture): EditableImage
	return self._backImg
end

function ParallelTexture.ApplyShaderParallel(
	self: ParallelTexture,
	shaderModule: ModuleScript,
	origin: Vector2?,
	downscale: number?
)
	self._window:ApplyShaderToImage(shaderModule, self._backImg, origin, downscale)
end

function ParallelTexture.SwapBuffers(self: ParallelTexture)
	local tempTex = self._frontTex
	self._frontTex = self._backTex
	self._backTex = tempTex

	local tempImg = self._frontImg
	self._frontImg = self._backImg
	self._backImg = tempImg
end

return new
