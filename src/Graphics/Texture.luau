--!strict

local AssetService = game:GetService("AssetService")

local Texture = {}
Texture.__index = Texture

export type Texture = typeof(setmetatable(
	{} :: {
		Size: Vector2,
		Width: number,
		Height: number,
		
		_editableImage: EditableImage,
		_shearCache: { [string]: Texture },
	},
	Texture
))

local function new(arg: Vector2 | Content): Texture
	local editableImage: EditableImage

	if typeof(arg) == "Vector2" then
		editableImage = AssetService:CreateEditableImage({
			Size = arg,
		})
	elseif typeof(arg) == "Content" then
		editableImage = AssetService:CreateEditableImageAsync(arg)
	else
		error("Invalid argument type")
	end

	local self = setmetatable({
		Size = editableImage.Size,
		Width = editableImage.Size.X,
		Height = editableImage.Size.Y,
		_editableImage = editableImage,
		_shearCache = {},
	}, Texture) :: Texture

	return self
end

function Texture.GetEditableImage(self: Texture): EditableImage
	return self._editableImage
end

function Texture.Shear(self: Texture, slantX: number, slantY: number?): Texture
	local sX = slantX or 0
	local sY = slantY or 0
	if sX == 0 and sY == 0 then
		return self
	end

	local qSX = math.round(sX * 20) / 20
	local qSY = math.round(sY * 20) / 20
	local cacheKey = tostring(qSX) .. "_" .. tostring(qSY)

	local cached = self._shearCache[cacheKey]
	if cached then
		return cached
	end

	local srcImg = self._editableImage
	local srcSize = srcImg.Size
	local extraW = math.ceil(srcSize.Y * math.abs(qSX))
	local extraH = math.ceil(srcSize.X * math.abs(qSY))
	local targetW = srcSize.X + extraW
	local targetH = srcSize.Y + extraH

	local outTex = new(Vector2.new(targetW, targetH)) :: Texture
	local srcBuf = srcImg:ReadPixelsBuffer(Vector2.zero, srcSize)
	local targetBuf = buffer.create(targetW * targetH * 4)

	for gy = 0, srcSize.Y - 1 do
		for gx = 0, srcSize.X - 1 do
			local srcOffset = (gy * srcSize.X + gx) * 4
			local a = buffer.readu8(srcBuf, srcOffset + 3)
			if a > 0 then
				local r = buffer.readu8(srcBuf, srcOffset)
				local g = buffer.readu8(srcBuf, srcOffset + 1)
				local b = buffer.readu8(srcBuf, srcOffset + 2)

				local offsetX = if qSX >= 0 then (srcSize.Y - 1 - gy) * qSX else gy * -qSX
				local offsetY = if qSY >= 0 then gx * qSY else (srcSize.X - 1 - gx) * -qSY

				local tx = math.clamp(math.floor(gx + offsetX), 0, targetW - 1)
				local ty = math.clamp(math.floor(gy + offsetY), 0, targetH - 1)

				local targetOffset = (ty * targetW + tx) * 4
				buffer.writeu8(targetBuf, targetOffset, r)
				buffer.writeu8(targetBuf, targetOffset + 1, g)
				buffer.writeu8(targetBuf, targetOffset + 2, b)

				local existingAlpha = buffer.readu8(targetBuf, targetOffset + 3)
				if a > existingAlpha then
					buffer.writeu8(targetBuf, targetOffset + 3, a)
				end
			end
		end
	end

	outTex:GetEditableImage():WritePixelsBuffer(Vector2.zero, Vector2.new(targetW, targetH), targetBuf)
	self._shearCache[cacheKey] = outTex
	return outTex
end

function Texture.Destroy(self: Texture)
	if not self._editableImage then
		return
	end

	for _, cached in self._shearCache do
		cached:Destroy()
	end
	table.clear(self._shearCache)
	self._editableImage:Destroy()
end

return (new :: any) :: ((size: Vector2) -> Texture) & ((content: Content) -> Texture)