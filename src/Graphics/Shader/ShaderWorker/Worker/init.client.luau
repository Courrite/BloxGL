--!strict
local Shader = require("@game/ReplicatedStorage/BloxGL/Graphics/Shader")

local actor = script.Parent :: Actor

local compiledShaderObjects = {} :: { [ModuleScript]: Shader.Shader }

actor:BindToMessage(
	"ApplyShaderTile",
	function(
		shaderModule: ModuleScript,
		image: EditableImage,
		buf: buffer,
		origin: Vector2,
		windowSize: Vector2,
		downscale: number?
	)
		local imgSize = image.Size

		local shaderObj = compiledShaderObjects[shaderModule]
		if not shaderObj then
			shaderObj = Shader(shaderModule, downscale or 2)
			compiledShaderObjects[shaderModule] = shaderObj
		end

		task.desynchronize()

		if shaderObj then
			shaderObj:ApplyToBuffer(buf, imgSize, origin, windowSize)
		end

		task.synchronize()

		image:WritePixelsBuffer(Vector2.zero, imgSize, buf)
	end
)
