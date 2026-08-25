--!strict

local SpriteBatch = require("../Graphics/SpriteBatch")
local GlyphInfo = require("./GlyphInfo")

type SpriteBatch = SpriteBatch.SpriteBatch
type GlyphInfo = GlyphInfo.GlyphInfo

export type DrawCharContext = {
	batch: SpriteBatch,
	fontFace: any, -- FontFace
	char: string,
	charIndex: number,
	totalChars: number,
	normalizedX: number,
	basePosition: Vector2,
	position: Vector2,
	color: Color3,
	transparency: number,
	shear: Vector2,
	time: number,
	colorFn: ((worldPos: Vector2, localNorm: Vector2) -> Color3)?,
}

export type TextEffect = {
	Apply: (self: TextEffect, ctx: DrawCharContext) -> (),
}

local TextEffect = {}

function TextEffect.Slant(slantX: number?, slantY: number?): TextEffect
	local sX = slantX or 0.4
	local sY = slantY or 0

	return {
		Apply = function(_, ctx: DrawCharContext)
			ctx.shear += Vector2.new(sX, sY)
		end,
	}
end

function TextEffect.DropShadow(offset: Vector2?, shadowColor: Color3?): TextEffect
	local off = offset or Vector2.new(4, 6)
	local col = shadowColor or Color3.fromRGB(10, 12, 22)

	return {
		Apply = function(_, ctx: DrawCharContext)
			local glyph = ctx.fontFace:GetGlyph(ctx.char)
			if glyph.Width > 0 and glyph.Height > 0 then
				local shadowTex = ctx.fontFace:GetGlyphTexture(ctx.char, col)
				if shadowTex then
					if ctx.shear.X ~= 0 or ctx.shear.Y ~= 0 then
						shadowTex = shadowTex:Shear(ctx.shear.X, ctx.shear.Y)
					end
					ctx.batch:Draw(shadowTex, ctx.position + off, nil, ctx.transparency)
				end
			end
		end,
	}
end

function TextEffect.Wave(frequency: number?, amplitude: number?): TextEffect
	local freq = frequency or 5
	local amp = amplitude or 1

	return {
		Apply = function(_, ctx: DrawCharContext)
			local yOffset = math.sin(ctx.normalizedX * freq + ctx.time) * amp
			ctx.position += Vector2.new(0, yOffset)
		end,
	}
end

function TextEffect.RadialGradient(colors: { Color3 }, center: Vector2?, radius: number?): TextEffect
	local col = colors or { Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 255) }
	local centerPos = center or Vector2.zero
	local maxRadius = radius or 250

	local function lerpColor(c1: Color3, c2: Color3, t: number): Color3
		return c1:Lerp(c2, t)
	end

	local function sampleColorArray(_colors: { Color3 }, t: number): Color3
		if #_colors == 0 then
			return Color3.new(1, 1, 1)
		elseif #_colors == 1 then
			return _colors[1]
		end

		t = math.clamp(t, 0, 1)
		local scaledT = t * (#_colors - 1)
		local index = math.floor(scaledT) + 1
		local fraction = scaledT - math.floor(scaledT)

		if index >= #_colors then
			return _colors[#_colors]
		end

		return lerpColor(_colors[index], _colors[index + 1], fraction)
	end

	return {
		Apply = function(_, ctx: DrawCharContext)
			ctx.colorFn = function(worldPos: Vector2, _localNorm: Vector2): Color3
				local d = (worldPos - centerPos).Magnitude
				local t = math.clamp(d / maxRadius, 0, 1)
				return sampleColorArray(col, t)
			end
		end,
	}
end

function TextEffect.RainbowRadialGradient(center: Vector2?, radius: number?, speed: number?): TextEffect
	local centerPos = center or Vector2.zero
	local maxRadius = radius or 250
	local animSpeed = speed or 0.5

	return {
		Apply = function(_, ctx: DrawCharContext)
			ctx.colorFn = function(worldPos: Vector2, _localNorm: Vector2): Color3
				local d = (worldPos - centerPos).Magnitude
				local normD = d / maxRadius
				local hue = (normD - ctx.time * animSpeed) % 1
				if hue < 0 then
					hue += 1
				end
				return Color3.fromHSV(hue, 0.9, 1.0)
			end
		end,
	}
end

return TextEffect
