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

		_texturePool: { Texture.Texture },
		_activeTransientTextures: { Texture.Texture },
		_lastTime: number?,
	},
	FontFace
))

function new(ttfData: buffer, fontSize: number?, aliased: boolean?): FontFace
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

		_texturePool = {},
		_activeTransientTextures = {},
		_lastTime = nil,
	}, FontFace) :: FontFace

	return self
end

function FontFace.AcquireTransientTexture(self: FontFace, size: Vector2): Texture.Texture
	for i, tex in self._texturePool do
		if tex.Size.X == size.X and tex.Size.Y == size.Y then
			table.remove(self._texturePool, i)
			table.insert(self._activeTransientTextures, tex)
			return tex
		end
	end

	local tex = Texture(size)
	table.insert(self._activeTransientTextures, tex)
	return tex
end

function FontFace.ReleaseTransientTextures(self: FontFace)
	for _, tex in self._activeTransientTextures do
		table.insert(self._texturePool, tex)
	end
	table.clear(self._activeTransientTextures)
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

function FontFace.GetGlyph(self: FontFace, char: string): GlyphInfo
	local cached = self._cache[char]
	if cached then
		return cached
	end

	local codepoint = string.byte(char) or 0
	local advance = StbTrueType.GetCodepointHMetrics(self._fontInfo, codepoint)
	local sdfBitmap, width, height, originX, originY =
		StbTrueType.MakeCodepointSDF(self._fontInfo, codepoint, self._scale, 12)

	local atlasPos = self._atlas:TryPack(sdfBitmap, Vector2.new(width, height))
	local atlasX = if atlasPos then atlasPos.X else 0
	local atlasY = if atlasPos then atlasPos.Y else 0

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

	self._cache[char] = glyph
	return glyph
end

function FontFace.GetGlyphTexture(self: FontFace, char: string, color: Color3): Texture.Texture?
	-- quantize colors to prevent memory bloat during continuous animated color sweeps
	local qr = math.clamp(math.round(color.R * 31) / 31, 0, 1)
	local qg = math.clamp(math.round(color.G * 31) / 31, 0, 1)
	local qb = math.clamp(math.round(color.B * 31) / 31, 0, 1)
	local qColor = Color3.new(qr, qg, qb)

	local key = char .. "_" .. qColor:ToHex()
	local cached = self._glyphTextures[key]
	if cached then
		return cached
	end

	local glyph = self:GetGlyph(char)
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
			local alphaFactor = if self.Aliased
				then (if val >= 128 then 1 else 0)
				else math.clamp((normD - 0.4375) / 0.125, 0, 1)
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

function FontFace.GetGlyphTextureWithFn(
	self: FontFace,
	char: string,
	originPos: Vector2,
	colorFn: (worldPos: Vector2, localNorm: Vector2) -> Color3
): Texture.Texture?
	local glyph = self:GetGlyph(char)
	if glyph.Width == 0 or glyph.Height == 0 or not glyph.SdfBitmap then
		return nil
	end

	local width = glyph.Width
	local height = glyph.Height
	local sdfBitmap = glyph.SdfBitmap

	local tex = self:AcquireTransientTexture(Vector2.new(width, height))
	local buf = buffer.create(width * height * 4)
	local isAliased = self.Aliased
	local invWidth = if width > 1 then 1 / (width - 1) else 0
	local invHeight = if height > 1 then 1 / (height - 1) else 0

	for gy = 0, height - 1 do
		local worldY = originPos.Y + gy
		local normY = if height > 1 then gy * invHeight else 0.5

		for gx = 0, width - 1 do
			local val = sdfBitmap[gy * width + gx + 1] or 0
			if val == 0 then
				continue
			end

			local normD = val / 255
			local alphaFactor = if isAliased
				then (if val >= 128 then 1 else 0)
				else math.clamp((normD - 0.4375) / 0.125, 0, 1)

			if alphaFactor > 0 then
				local worldPos = Vector2.new(originPos.X + gx, worldY)
				local localNorm = Vector2.new(if width > 1 then gx * invWidth else 0.5, normY)
				local col = colorFn(worldPos, localNorm)

				local r = math.clamp(math.floor(col.R * 255), 0, 255)
				local g = math.clamp(math.floor(col.G * 255), 0, 255)
				local b = math.clamp(math.floor(col.B * 255), 0, 255)
				local alpha = math.floor(alphaFactor * 255)

				local offset = (gy * width + gx) * 4
				buffer.writeu8(buf, offset, r)
				buffer.writeu8(buf, offset + 1, g)
				buffer.writeu8(buf, offset + 2, b)
				buffer.writeu8(buf, offset + 3, alpha)
			end
		end
	end

	tex:GetEditableImage():WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), buf)
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
		local c = string.sub(text, i, i)
		if c == " " then
			width += self.FontSize * 0.25
		else
			local glyph = self:GetGlyph(c)
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
		local c = string.sub(text, i, i)
		local adv = 0
		if c == " " then
			adv = self.FontSize * 0.25
		else
			local glyph = self:GetGlyph(c)
			adv = glyph.Advance
		end
		table.insert(result, {
			char = c,
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
	color: (Color3 | number)?,
	outlineSize: (number | Color3)?,
	outlineColor: (Color3 | number)?,
	fontSize: number?
)
	local textColor: Color3 = Color3.fromRGB(255, 255, 255)
	local outSize: number = 0
	local outColor: Color3 = Color3.fromRGB(0, 0, 0)
	local targetFontSize: number = self.FontSize

	if typeof(color) == "Color3" then
		textColor = color
	elseif typeof(color) == "number" then
		targetFontSize = color
	end

	if typeof(outlineSize) == "number" then
		outSize = outlineSize
	elseif typeof(outlineSize) == "Color3" then
		outColor = outlineSize
	end

	if typeof(outlineColor) == "Color3" then
		outColor = outlineColor
	elseif typeof(outlineColor) == "number" then
		targetFontSize = outlineColor
	end

	if typeof(fontSize) == "number" then
		targetFontSize = fontSize
	end

	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		scaledFace:DrawText(sb, text, position, textColor, outSize, outColor)
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
	color: (Color3 | number)?,
	outlineSize: (number | Color3)?,
	outlineColor: (Color3 | number)?,
	fontSize: number?
)
	local targetFontSize = if typeof(fontSize) == "number"
		then fontSize
		elseif typeof(color) == "number" then color
		elseif typeof(outlineColor) == "number" then outlineColor
		else self.FontSize

	local bounds = self:MeasureText(text, targetFontSize)
	local drawPos = centerPos - Vector2.new(bounds.X / 2, bounds.Y / 2)
	self:DrawText(sb, text, drawPos, color, outlineSize, outlineColor, fontSize)
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
		local c = string.sub(text, i, i)

		if c == " " then
			cursorX += self.FontSize * 0.25
			continue
		end

		local glyph = self:GetGlyph(c)
		if glyph.Width == 0 or glyph.Height == 0 then
			cursorX += glyph.Advance
			continue
		end

		local drawW = Vector2.new(glyph.Width, glyph.Height)
		local drawBX = glyph.BearingX
		local drawBY = glyph.BearingY
		local glyphTex = self:GetGlyphTexture(c, color)

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

function FontFace.DrawTextWithEffects(
	self: FontFace,
	sb: SpriteBatch,
	text: string,
	position: Vector2,
	color: Color3?,
	fontSize: number?,
	effects: { any }?,
	time: number?
)
	local targetFontSize = fontSize or self.FontSize
	if targetFontSize ~= self.FontSize then
		local scaledFace = self:GetAtFontSize(targetFontSize)
		scaledFace:DrawTextWithEffects(sb, text, position, color, targetFontSize, effects, time)
		return
	end

	local currentTime = time or 0
	if currentTime ~= self._lastTime then
		self:ReleaseTransientTextures()
		self._lastTime = currentTime
	end

	local charOffsets, totalWidth = self:GetCharacterOffsets(text)
	local baseColor = color or Color3.fromRGB(255, 255, 255)
	local numChars = #charOffsets

	for i, item in charOffsets do
		if item.char == " " then
			continue
		end

		local glyph = self:GetGlyph(item.char)
		if glyph.Width == 0 or glyph.Height == 0 then
			continue
		end

		local glyphOffset = Vector2.new(glyph.BearingX, glyph.BearingY)
		local charPos = position + Vector2.new(item.xOffset, 0) + glyphOffset

		local ctx = {
			batch = sb,
			fontFace = self,
			char = item.char,
			charIndex = i,
			totalChars = numChars,
			normalizedX = if totalWidth > 0 then item.xOffset / totalWidth else 0,
			basePosition = charPos,
			position = charPos,
			color = baseColor,
			transparency = 0,
			shear = Vector2.zero,
			time = currentTime,
			colorFn = nil :: ((worldPos: Vector2, localNorm: Vector2) -> Color3)?,
		}

		if effects then
			for _, effect in effects do
				effect:Apply(ctx)
			end
		end

		local fgTex
		if ctx.colorFn then
			fgTex = self:GetGlyphTextureWithFn(ctx.char, ctx.position, ctx.colorFn)
		else
			fgTex = self:GetGlyphTexture(ctx.char, ctx.color)
		end

		if fgTex then
			if ctx.shear.X ~= 0 or ctx.shear.Y ~= 0 then
				if ctx.colorFn then
					local qSX = math.round(ctx.shear.X * 20) / 20
					local qSY = math.round(ctx.shear.Y * 20) / 20
					local extraW = math.ceil(fgTex.Height * math.abs(qSX))
					local extraH = math.ceil(fgTex.Width * math.abs(qSY))
					local targetW = fgTex.Width + extraW
					local targetH = fgTex.Height + extraH
					local shearedTex = self:AcquireTransientTexture(Vector2.new(targetW, targetH))
					fgTex = fgTex:ShearTo(shearedTex, ctx.shear.X, ctx.shear.Y)
				else
					fgTex = fgTex:Shear(ctx.shear.X, ctx.shear.Y)
				end
			end
			sb:Draw(fgTex, ctx.position, nil, ctx.transparency)
		end
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
	for _, tex in self._texturePool do
		tex:Destroy()
	end
	table.clear(self._texturePool)
	for _, tex in self._activeTransientTextures do
		tex:Destroy()
	end
	table.clear(self._activeTransientTextures)
end

return new
