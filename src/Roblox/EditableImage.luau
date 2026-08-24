--!strict

local AssetService = game:GetService("AssetService")

const function new(size: Vector2): EditableImage
	return AssetService:CreateEditableImage({
		Size = size,
	})
end

return new
