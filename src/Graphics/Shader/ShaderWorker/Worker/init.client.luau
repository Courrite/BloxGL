--!strict
local Shader = require("@game/ReplicatedStorage/BloxGL/Graphics/Shader")

local actor = script.Parent :: Actor

local compiledShaderObjects = {} :: { [ModuleScript]: Shader.Shader }

actor:BindToMessage(
	"ApplyShaderTile",
	function(
		shaderModule: ModuleScript,
		image: EditableImage,
		fullBuf: buffer,
		origin: Vector2,
		windowSize: Vector2,
		downscale: number?,
		tileOffset: Vector2?,
		tileSize: Vector2?
	)
		local imgSize = image.Size
		local tOff = tileOffset or Vector2.zero
		local tSize = tileSize or imgSize

		local shaderObj = compiledShaderObjects[shaderModule]
		if not shaderObj then
			shaderObj = Shader(shaderModule, downscale or 2)
			compiledShaderObjects[shaderModule] = shaderObj
		else
			shaderObj:SetDownscale(downscale or 2)
		end

		local subBuf = buffer.create(math.floor(tSize.X) * math.floor(tSize.Y) * 4)

		task.desynchronize()

		if shaderObj then
			shaderObj:ApplyToBuffer(subBuf, imgSize, origin, windowSize, nil, tOff, tSize, fullBuf)
		end

		task.synchronize()

		image:WritePixelsBuffer(tOff, tSize, subBuf)
	end
)
