--!strict

local Window = require("@self/Window")
local Texture = require("@self/Graphics/Texture")
local SpriteBatch = require("@self/Graphics/SpriteBatch")
local FontFace = require("@self/Typography/FontFace")
local FontAtlas = require("@self/Typography/FontAtlas")
local GlyphInfo = require("@self/Typography/GlyphInfo")

local TextEffect = require("@self/Typography/TextEffect")

export type Texture = Texture.Texture
export type Window = Window.Window
export type SpriteBatch = SpriteBatch.SpriteBatch
export type FontFace = FontFace.FontFace
export type FontAtlas = FontAtlas.FontAtlas
export type GlyphInfo = GlyphInfo.GlyphInfo
export type TextEffect = TextEffect.TextEffect
export type DrawCharContext = TextEffect.DrawCharContext

return table.freeze({
	Window = Window,
	Texture = Texture,
	SpriteBatch = SpriteBatch,
	FontFace = FontFace,
	FontAtlas = FontAtlas,
	TextEffect = TextEffect,
})
