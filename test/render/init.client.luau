--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxGL = require(ReplicatedStorage:WaitForChild("BloxGL"))

local window = BloxGL.Window(Vector2.new(1920, 1080))
local batch = BloxGL.SpriteBatch(window)

task.wait(3)

local montserratRaw = require("@self/content/fonts/montserrat") -- ttf font binary data converted to hex
local fontBuffer = buffer.fromstring(montserratRaw)
local fontSize = 64
local fontFace = BloxGL.FontFace(fontBuffer, fontSize)

local TextRadialWaveModule = script:WaitForChild("Shaders"):WaitForChild("TextRadialWave") :: ModuleScript

local text = "BloxGL Engine"
local center = Vector2.new(960, 540)
local timeElapsed = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	timeElapsed += deltaTime

	window:Clear(Color3.fromRGB(0, 0, 0))

	batch:Begin()

	local bounds = fontFace:MeasureText(text, fontSize)
	local drawPos = center - Vector2.new(bounds.X / 2, bounds.Y / 2)

	fontFace:DrawText(batch, text, drawPos, Color3.fromRGB(255, 255, 255), fontSize)

	batch:End()

	window:ApplyShader(TextRadialWaveModule, 8)
end)
