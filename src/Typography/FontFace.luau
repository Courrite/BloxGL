--!strict

local FontAtlas = require("./FontAtlas")
local GlyphInfo = require("./GlyphInfo")
local StbTrueType = require("./StbTrueType")
local SpriteBatch = require("../Graphics/SpriteBatch")
local Texture = require("../Graphics/Texture")

type FontAtlas = FontAtlas.FontAtlas
type GlyphInfo = GlyphInfo.GlyphInfo
type SpriteBatch = SpriteBatch.SpriteBatch
type FontInfo = StbTrueType.FontInfo

local FontFace = {}
FontFace.__index = FontFace

export type FontFace = typeof(setmetatable(
	{} :: {
		FontSize: number,
		Aliased: boolean,
		Atlas: Texture.Texture,

		_scaledFaces: { [number]: FontFace },
		_cache: { [string]: GlyphInfo },
		_glyphTextures: { [string]: Texture.Texture },
		_atlas: FontAtlas,
		_ttfData: buffer,
		_fontInfo: FontInfo,
		_scale: number,
	},
	FontFace
))

local function new(ttfData: buffer, fontSize: number?, aliased: boolean?): FontFace
	local size = fontSize or 16
	local atlas = FontAtlas(Vector2.new(1024, 1024))
	local fontInfo = StbTrueType.CreateFont(ttfData)
	local scale = StbTrueType.ScaleForPixelHeight(fontInfo, size)

	local self = setmetatable({
		FontSize = size,
		Aliased = aliased or false,
		Atlas = atlas.Texture,

		_scaledFaces = {},
		_cache = {},
		_glyphTextures = {},
		_atlas = atlas,
		_ttfData = ttfData,
		_fontInfo = fontInfo,
		_scale = scale,
	}, FontFace) :: FontFace

	return self
end

function FontFace.GetAtPixelScale(self: FontFace, pixelScale: number): FontFace
	if pixelScale <= 1 then
		return self
	end

	local cached = self._scaledFaces[pixelScale]
	if cached then
		return cached
	end

	local face = new(self._ttfData, math.max(1, math.floor(self.FontSize / pixelScale)), self.Aliased)
	self._scaledFaces[pixelScale] = face
	return face
end

function FontFace.GetAtFontSize(self: FontFace, targetSize: number): FontFace
	if targetSize == self.FontSize then
		return self
	end

	local cached = self._scaledFaces[targetSize]
	if cached then
		return cached
	end

	local face = new(self._ttfData, targetSize, self.Aliased)
	self._scaledFaces[targetSize] = face
	return face
end

function FontFace.GetGlyph(self: FontFace, charOrCodepoint: string | number): GlyphInfo
	local codepoint: number = typeof(charOrCodepoint) == "number" and charOrCodepoint
		or (string.byte(charOrCodepoint :: string) or 0)
	local cacheKey: string = tostring(codepoint)
	local cached = self._cache[cacheKey]
	if cached then
		return cached
	end

	local advance = StbTrueType.GetCodepointHMetrics(self._fontInfo, codepoint)
	local sdfBitmap, width, height, originX, originY =
		StbTrueType.MakeCodepointSDF(self._fontInfo, codepoint, self._scale, 12)

	local atlasPos = self._atlas:TryPack(sdfBitmap, Vector2.new(width, height))
	local atlasX = atlasPos and atlasPos.X or 0
	local atlasY = atlasPos and atlasPos.Y or 0

	local glyph: GlyphInfo = {
		AtlasX = atlasX,
		AtlasY = atlasY,
		Width = width,
		Height = height,
		Advance = math.floor(advance * self._scale),
		BearingX = originX,
		BearingY = originY,
		SdfBitmap = sdfBitmap,
	}

	self._cache[cacheKey] = glyph
	return glyph
end

function FontFace.GetGlyphTexture(self: FontFace, charOrCodepoint: string | number, color: Color3): Texture.Texture?
	-- quantize colors to prevent memory bloat during continuous animated color sweeps
	local qr = math.clamp(math.round(color.R * 31) / 31, 0, 1)
	local qg = math.clamp(math.round(color.G * 31) / 31, 0, 1)
	local qb = math.clamp(math.round(color.B * 31) / 31, 0, 1)
	local qColor = Color3.new(qr, qg, qb)

	local codepoint: number = typeof(charOrCodepoint) == "number" and charOrCodepoint
		or (string.byte(charOrCodepoint :: string) or 0)
	local key = codepoint .. "_" .. qColor:ToHex()
	local cached = self._glyphTextures[key]
	if cached then
		return cached
	end

	local glyph = self:GetGlyph(codepoint)
	if glyph.Width == 0 or glyph.Height == 0 or not glyph.SdfBitmap then
		return nil
	end

	local width = glyph.Width
	local height = glyph.Height
	local sdfBitmap = glyph.SdfBitmap

	local tex = Texture(Vector2.new(width, height))
	local r = math.floor(qColor.R * 255)
	local g = math.floor(qColor.G * 255)
	local b = math.floor(qColor.B * 255)

	local buf = buffer.create(width * height * 4)
	for gy = 0, height - 1 do
		for gx = 0, width - 1 do
			local val = sdfBitmap[gy * width + gx + 1] or 0
			if val == 0 then
				continue
			end

			local normD = val / 255
			local alphaFactor = self.Aliased and (val >= 128 and 1 or 0) or math.clamp((normD - 0.4375) / 0.125, 0, 1)
			local alpha = math.floor(alphaFactor * 255)

			local offset = (gy * width + gx) * 4
			buffer.writeu8(buf, offset, r)
			buffer.writeu8(buf, offset + 1, g)
			buffer.writeu8(buf, offset + 2, b)
			buffer.writeu8(buf, offset + 3, alpha)
		end
	end

	tex:GetEditableImage():WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), buf)
	self._glyphTextures[key] = tex
	return tex
end

function FontFace.MeasureText(self: FontFace, text: string, fontSize: number?): Vector2
	local targetFontSize: number = fontSize or self.FontSize
	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		return scaledFace:MeasureText(text)
	end

	local width = 0
	for i = 1, #text do
		local code = string.byte(text, i)
		if code == 0x20 then
			width += self.FontSize * 0.25
		else
			local glyph = self:GetGlyph(code)
			width += glyph.Advance
		end
	end
	return Vector2.new(width, self.FontSize)
end

type CharLayout = {
	char: string,
	xOffset: number,
	advance: number,
}

function FontFace.GetCharacterOffsets(self: FontFace, text: string, fontSize: number?): ({ CharLayout }, number)
	local targetFontSize: number = fontSize or self.FontSize
	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		return scaledFace:GetCharacterOffsets(text)
	end

	local result: { CharLayout } = {}
	local currentX = 0
	for i = 1, #text do
		local code = string.byte(text, i)
		local adv = 0
		if code == 0x20 then
			adv = self.FontSize * 0.25
		else
			local glyph = self:GetGlyph(code)
			adv = glyph.Advance
		end
		table.insert(result, {
			char = string.char(code),
			xOffset = currentX,
			advance = adv,
		})
		currentX += adv
	end
	return result, currentX
end

function FontFace.DrawChar(
	self: FontFace,
	sb: SpriteBatch,
	char: string,
	position: Vector2,
	color: Color3?,
	outlineSize: number?,
	outlineColor: Color3?,
	fontSize: number?
)
	local targetFontSize = fontSize or self.FontSize
	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		scaledFace:DrawChar(sb, char, position, color, outlineSize, outlineColor)
		return
	end

	local glyph = self:GetGlyph(char)
	if glyph.Width == 0 or glyph.Height == 0 then
		return
	end

	local charColor = color or Color3.fromRGB(255, 255, 255)
	local drawW = Vector2.new(glyph.Width, glyph.Height)
	local drawBX = glyph.BearingX
	local drawBY = glyph.BearingY
	local outSize = outlineSize or 0
	local outColor = outlineColor or Color3.fromRGB(0, 0, 0)

	if outSize > 0 then
		local outTex = self:GetGlyphTexture(char, outColor)
		if outTex then
			for dx = -outSize, outSize do
				for dy = -outSize, outSize do
					if dx ~= 0 or dy ~= 0 then
						sb:Draw(outTex, Vector2.new(position.X + drawBX + dx, position.Y + drawBY + dy), drawW)
					end
				end
			end
		end
	end

	local glyphTex = self:GetGlyphTexture(char, charColor)
	if glyphTex then
		sb:Draw(glyphTex, Vector2.new(position.X + drawBX, position.Y + drawBY), drawW)
	end
end

function FontFace.DrawText(
	self: FontFace,
	sb: SpriteBatch,
	text: string,
	position: Vector2,
	color: Color3?,
	fontSize: number?,
	outlineSize: number?,
	outlineColor: Color3?
)
	local textColor: Color3 = color or Color3.fromRGB(255, 255, 255)
	local targetFontSize: number = fontSize or self.FontSize
	local outSize: number = outlineSize or 0
	local outColor: Color3 = outlineColor or Color3.fromRGB(0, 0, 0)

	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		scaledFace:DrawText(sb, text, position, textColor, targetFontSize, outSize, outColor)
		return
	end

	if outSize > 0 then
		self:_drawTextInternal(sb, text, position, outSize, outColor)
	end

	self:_drawTextInternal(sb, text, position, 0, textColor)
end

function FontFace.DrawTextCentered(
	self: FontFace,
	sb: SpriteBatch,
	text: string,
	centerPos: Vector2,
	color: Color3?,
	fontSize: number?,
	outlineSize: number?,
	outlineColor: Color3?
)
	local targetFontSize = fontSize or self.FontSize
	local bounds = self:MeasureText(text, targetFontSize)
	local drawPos = centerPos - Vector2.new(bounds.X / 2, bounds.Y / 2)
	self:DrawText(sb, text, drawPos, color, targetFontSize, outlineSize, outlineColor)
end

function FontFace._drawTextInternal(
	self: FontFace,
	sb: SpriteBatch,
	text: string,
	position: Vector2,
	outlineSize: number,
	color: Color3
)
	local cursorX = position.X

	for i = 1, #text do
		local code = string.byte(text, i)

		if code == 0x20 then
			cursorX += self.FontSize * 0.25
			continue
		end

		local glyph = self:GetGlyph(code)
		if glyph.Width == 0 or glyph.Height == 0 then
			cursorX += glyph.Advance
			continue
		end

		local drawW = Vector2.new(glyph.Width, glyph.Height)
		local drawBX = glyph.BearingX
		local drawBY = glyph.BearingY
		local glyphTex = self:GetGlyphTexture(code, color)

		if outlineSize > 0 then
			for dx = -outlineSize, outlineSize do
				for dy = -outlineSize, outlineSize do
					if dx == 0 and dy == 0 then
						continue
					end
					local drawPos = Vector2.new(cursorX + drawBX + dx, position.Y + drawBY + dy)
					if glyphTex then
						sb:Draw(glyphTex, drawPos, drawW)
					end
				end
			end
		else
			local drawPos = Vector2.new(cursorX + drawBX, position.Y + drawBY)
			if glyphTex then
				sb:Draw(glyphTex, drawPos, drawW)
			end
		end

		cursorX += glyph.Advance
	end
end

function FontFace.Destroy(self: FontFace)
	for _, face in self._scaledFaces do
		face:Destroy()
	end
	table.clear(self._scaledFaces)
	table.clear(self._cache)
	for _, tex in self._glyphTextures do
		tex:Destroy()
	end
	table.clear(self._glyphTextures)
end

return new
