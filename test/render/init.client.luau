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

local padding = Vector2.new(60, 60)
local textBounds = fontFace:MeasureText(text, fontSize)
local textTexSize = textBounds + padding * 2

local textTexture = BloxGL.Texture(textTexSize)
local textImage = textTexture:GetEditableImage()

local TIME_UNIFORM = 1

local textRadialShader = BloxGL.Shader(
	function(
		worldX: number,
		worldY: number,
		normX: number,
		normY: number,
		r: number,
		g: number,
		b: number,
		a: number,
		uniforms
	)
		local timeVal = (uniforms[TIME_UNIFORM] :: number) or 0

		local dispY = math.sin(normX * 14 + timeVal * 4) * 14

		if a == 0 then
			return 0, 0, 0, 0, 0, dispY
		end

		local dx = normX - 0.5
		local dy = normY - 0.5
		local dist = math.sqrt(dx * dx + dy * dy) -- distance from the center
		local normD = dist * 2.0

		local phase = (normD * 6 - timeVal * 3)
		local rWave = (math.sin(phase) * 0.5 + 0.5)
		local gWave = (math.sin(phase + 2.094) * 0.5 + 0.5) -- + 2pi/3
		local bWave = (math.sin(phase + 4.188) * 0.5 + 0.5) -- + 4pi/3

		local nr = math.floor(rWave * 255)
		local ng = math.floor(gWave * 255)
		local nb = math.floor(bWave * 255)

		return nr, ng, nb, a, 0, dispY
	end
)

RunService.RenderStepped:Connect(function(deltaTime: number)
	timeElapsed += deltaTime

	textRadialShader:SetUniform(TIME_UNIFORM, timeElapsed)

	textImage:DrawRectangle(Vector2.zero, textTexSize, Color3.new(0, 0, 0), 1, Enum.ImageCombineType.Overwrite)

	local charOffsets = fontFace:GetCharacterOffsets(text, fontSize)
	for _, item in charOffsets do
		if item.char == " " then
			continue
		end
		local glyph = fontFace:GetGlyph(item.char)
		local glyphTex = fontFace:GetGlyphTexture(item.char, Color3.fromRGB(255, 255, 255))
		if glyphTex then
			local drawPos = padding + Vector2.new(item.xOffset + glyph.BearingX, glyph.BearingY)
			textImage:DrawImage(drawPos, glyphTex:GetEditableImage(), Enum.ImageCombineType.AlphaBlend)
		end
	end

	local drawPos = center - textTexSize / 2
	textRadialShader:ApplyToImage(textImage, drawPos, nil, window.Size)

	window:Clear(Color3.fromRGB(15, 15, 25))

	batch:Begin()
	batch:Draw(textTexture, drawPos)
	batch:End()
end)
