--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxGL = require(ReplicatedStorage:WaitForChild("BloxGL"))

local window = BloxGL.Window(Vector2.new(1920, 1080))
local batch = BloxGL.SpriteBatch(window)

local montserratRaw = require("@self/content/fonts/montserrat") -- ttf font binary data converted to hex
local fontBuffer = buffer.fromstring(montserratRaw)
local fontSize = 64
local fontFace = BloxGL.FontFace(fontBuffer, fontSize)

local text = "BloxGL Engine"
local center = Vector2.new(960, 540)
local timeElapsed = 0

local textEffects = {
	BloxGL.TextEffect.Wave(10, 15),
	BloxGL.TextEffect.DropShadow(Vector2.new(4, 6), Color3.fromRGB(10, 12, 22)),
	BloxGL.TextEffect.RainbowRadialGradient(Vector2.new(960, 540), 250, 0.75),
}

RunService.RenderStepped:Connect(function(deltaTime: number)
	timeElapsed += deltaTime

	window:Clear(Color3.fromRGB(0, 0, 0))

	batch:Begin()

	local bounds = fontFace:MeasureText(text, fontSize)
	local drawPos = center - Vector2.new(bounds.X / 2, bounds.Y / 2)

	fontFace:DrawTextWithEffects(batch, text, drawPos, Color3.new(1, 1, 1), fontSize, textEffects, timeElapsed)

	batch:End()
end)
