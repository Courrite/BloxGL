--!strict

local Window = require("@self/Window")
local Texture = require("@self/Graphics/Texture")
local SpriteBatch = require("@self/Graphics/SpriteBatch")
local Shader = require("@self/Graphics/Shader")
local FontFace = require("@self/Typography/FontFace")
local FontAtlas = require("@self/Typography/FontAtlas")
local GlyphInfo = require("@self/Typography/GlyphInfo")

export type Texture = Texture.Texture
export type Window = Window.Window
export type SpriteBatch = SpriteBatch.SpriteBatch
export type Shader = Shader.Shader
export type FontFace = FontFace.FontFace
export type FontAtlas = FontAtlas.FontAtlas
export type GlyphInfo = GlyphInfo.GlyphInfo

return table.freeze({
	Window = Window,
	Texture = Texture,
	SpriteBatch = SpriteBatch,
	Shader = Shader,
	FontFace = FontFace,
	FontAtlas = FontAtlas,
})
