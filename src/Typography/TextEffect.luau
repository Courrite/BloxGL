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

return TextEffect
