--!strict

const function new(pos: Vector2, size: Vector2): ImageLabel
	local label = Instance.new("ImageLabel")

	label.Position = UDim2.fromOffset(pos.X, pos.Y)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.BorderSizePixel = 0
	label.BackgroundColor3 = Color3.new(0, 0, 0)

	return label
end

return new
