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

local ShadersFolder = script:WaitForChild("Shaders") :: Folder
local glitch = ShadersFolder:WaitForChild("glitch") :: ModuleScript
local textShader = BloxGL.Shader(glitch, 1)

local text = "BloxGL Engine"
local center = Vector2.new(960, 540)
local timeElapsed = 0

local padding = Vector2.new(60, 60)
local textBounds = fontFace:MeasureText(text, fontSize)
local textTexSize = textBounds + padding * 2

local textTexture = BloxGL.Texture(textTexSize)
local textImage = textTexture:GetEditableImage()

RunService.RenderStepped:Connect(function(deltaTime: number)
	timeElapsed += deltaTime

	window:Clear(Color3.fromRGB(0, 0, 0))

	textImage:DrawRectangle(Vector2.zero, textTexSize, Color3.new(0, 0, 0), 0, Enum.ImageCombineType.Overwrite)

	local charOffsets = fontFace:GetCharacterOffsets(text, fontSize)
	local baselineY = padding.Y + fontSize * 0.75
	for _, item in charOffsets do
		if item.char == " " then
			continue
		end
		local glyphTex = fontFace:GetGlyphTexture(item.char, Color3.fromRGB(255, 255, 255))
		if glyphTex then
			local glyph = fontFace:GetGlyph(item.char)
			local charDrawPos = Vector2.new(padding.X + item.xOffset + glyph.BearingX, baselineY + glyph.BearingY)
			textImage:DrawImage(charDrawPos, glyphTex:GetEditableImage(), Enum.ImageCombineType.AlphaBlend)
		end
	end

	local drawPos = center - textTexSize / 2

	local wavePad = Vector2.new(45, 45)
	local minWorld = drawPos + padding - wavePad
	local maxWorld = drawPos + padding + textBounds + wavePad
	textShader:SetUniform(2, {
		minWorld.X / window.Size.X,
		minWorld.Y / window.Size.Y,
		maxWorld.X / window.Size.X,
		maxWorld.Y / window.Size.Y,
	})

	local textCenterNorm = center / window.Size
	textShader:SetUniform(3, { textCenterNorm.X, textCenterNorm.Y })

	textShader:ApplyToImage(textImage, drawPos, window.Size)

	batch:Begin()
	batch:Draw(textTexture, drawPos)
	batch:End()
end)
