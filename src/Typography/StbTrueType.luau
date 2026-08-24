--!strict

local function readU16BE(buf: buffer, offset: number): number
	local b0 = buffer.readu8(buf, offset)
	local b1 = buffer.readu8(buf, offset + 1)
	return b0 * 256 + b1
end

local function readI16BE(buf: buffer, offset: number): number
	local val = readU16BE(buf, offset)
	return if val >= 32768 then val - 65536 else val
end

local function readU32BE(buf: buffer, offset: number): number
	local b0 = buffer.readu8(buf, offset)
	local b1 = buffer.readu8(buf, offset + 1)
	local b2 = buffer.readu8(buf, offset + 2)
	local b3 = buffer.readu8(buf, offset + 3)
	return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3
end

local function readTag(buf: buffer, offset: number): string
	local char1 = string.char(buffer.readu8(buf, offset))
	local char2 = string.char(buffer.readu8(buf, offset + 1))
	local char3 = string.char(buffer.readu8(buf, offset + 2))
	local char4 = string.char(buffer.readu8(buf, offset + 3))
	return char1 .. char2 .. char3 .. char4
end

export type FontInfo = {
	buffer: buffer,
	tables: { [string]: { offset: number, length: number } },
	unitsPerEm: number,
	indexToLocFormat: number,
	numberOfHMetrics: number,
	cmapOffset: number,
}

local StbTrueType = {}

function StbTrueType.CreateFont(fontBuffer: buffer): FontInfo
	local numTables = readU16BE(fontBuffer, 4)
	local tables: { [string]: { offset: number, length: number } } = {}

	for i = 0, numTables - 1 do
		local entryOffset = 12 + i * 16
		local tag = readTag(fontBuffer, entryOffset)
		local offset = readU32BE(fontBuffer, entryOffset + 8)
		local length = readU32BE(fontBuffer, entryOffset + 12)
		tables[tag] = { offset = offset, length = length }
	end

	local head = tables["head"]
	local hhea = tables["hhea"]
	local cmap = tables["cmap"]

	local unitsPerEm = if head then readU16BE(fontBuffer, head.offset + 18) else 2048
	local indexToLocFormat = if head then readI16BE(fontBuffer, head.offset + 50) else 0
	local numberOfHMetrics = if hhea then readU16BE(fontBuffer, hhea.offset + 34) else 0
	local cmapOffset = if cmap then cmap.offset else 0

	return {
		buffer = fontBuffer,
		tables = tables,
		unitsPerEm = unitsPerEm,
		indexToLocFormat = indexToLocFormat,
		numberOfHMetrics = numberOfHMetrics,
		cmapOffset = cmapOffset,
	}
end

function StbTrueType.ScaleForPixelHeight(fontInfo: FontInfo, pixels: number): number
	return pixels / fontInfo.unitsPerEm
end

function StbTrueType.GetGlyphIndex(fontInfo: FontInfo, codepoint: number): number
	if fontInfo.cmapOffset == 0 then
		return 0
	end

	local buf = fontInfo.buffer
	local numTables = readU16BE(buf, fontInfo.cmapOffset + 2)
	local subtableOffset = 0

	for i = 0, numTables - 1 do
		local pOffset = fontInfo.cmapOffset + 4 + i * 8
		local platformID = readU16BE(buf, pOffset)
		local encodingID = readU16BE(buf, pOffset + 2)
		local offset = readU32BE(buf, pOffset + 4)

		if (platformID == 3 and (encodingID == 1 or encodingID == 10)) or platformID == 0 then
			subtableOffset = fontInfo.cmapOffset + offset
			break
		end
	end

	if subtableOffset == 0 then
		return 0
	end

	local format = readU16BE(buf, subtableOffset)
	if format == 4 then
		local segCount = math.floor(readU16BE(buf, subtableOffset + 6) / 2)
		local endCountOffset = subtableOffset + 14
		local startCountOffset = endCountOffset + segCount * 2 + 2
		local idDeltaOffset = startCountOffset + segCount * 2
		local idRangeOffsetTable = idDeltaOffset + segCount * 2

		for s = 0, segCount - 1 do
			local endCode = readU16BE(buf, endCountOffset + s * 2)
			if endCode >= codepoint then
				local startCode = readU16BE(buf, startCountOffset + s * 2)
				if startCode <= codepoint then
					local idDelta = readI16BE(buf, idDeltaOffset + s * 2)
					local idRangeOffset = readU16BE(buf, idRangeOffsetTable + s * 2)
					if idRangeOffset == 0 then
						return (codepoint + idDelta) % 65536
					else
						local glyphPtr = idRangeOffsetTable + s * 2 + idRangeOffset + (codepoint - startCode) * 2
						local glyphID = readU16BE(buf, glyphPtr)
						return if glyphID ~= 0 then (glyphID + idDelta) % 65536 else 0
					end
				end
				break
			end
		end
	elseif format == 12 then
		local numGroups = readU32BE(buf, subtableOffset + 12)
		for g = 0, numGroups - 1 do
			local gOffset = subtableOffset + 16 + g * 12
			local startCode = readU32BE(buf, gOffset)
			local endCode = readU32BE(buf, gOffset + 4)
			local startGlyphID = readU32BE(buf, gOffset + 8)

			if codepoint >= startCode and codepoint <= endCode then
				return startGlyphID + (codepoint - startCode)
			end
		end
	end

	return 0
end

function StbTrueType.GetCodepointHMetrics(fontInfo: FontInfo, codepoint: number): (number, number)
	local glyphIndex = StbTrueType.GetGlyphIndex(fontInfo, codepoint)
	local hmtx = fontInfo.tables["hmtx"]
	if not hmtx then
		return fontInfo.unitsPerEm, 0
	end

	local buf = fontInfo.buffer
	local advance = 0
	local lsb = 0

	if glyphIndex < fontInfo.numberOfHMetrics then
		local entryOffset = hmtx.offset + glyphIndex * 4
		advance = readU16BE(buf, entryOffset)
		lsb = readI16BE(buf, entryOffset + 2)
	else
		local lastAdvanceOffset = hmtx.offset + (fontInfo.numberOfHMetrics - 1) * 4
		advance = readU16BE(buf, lastAdvanceOffset)
		local lsbOffset = hmtx.offset + fontInfo.numberOfHMetrics * 4 + (glyphIndex - fontInfo.numberOfHMetrics) * 2
		lsb = readI16BE(buf, lsbOffset)
	end

	return advance, lsb
end

function StbTrueType.GetCodepointBitmapBox(
	fontInfo: FontInfo,
	codepoint: number,
	scaleX: number,
	scaleY: number
): (number, number, number, number)
	local glyphIndex = StbTrueType.GetGlyphIndex(fontInfo, codepoint)
	local glyf = fontInfo.tables["glyf"]
	local loca = fontInfo.tables["loca"]

	if not glyf or not loca then
		return 0, 0, 0, 0
	end

	local buf = fontInfo.buffer
	local glyphOffset = 0

	if fontInfo.indexToLocFormat == 0 then
		glyphOffset = glyf.offset + readU16BE(buf, loca.offset + glyphIndex * 2) * 2
	else
		glyphOffset = glyf.offset + readU32BE(buf, loca.offset + glyphIndex * 4)
	end

	local numberOfContours = readI16BE(buf, glyphOffset)
	if numberOfContours == 0 then
		return 0, 0, 0, 0
	end

	local xMin = readI16BE(buf, glyphOffset + 2)
	local yMin = readI16BE(buf, glyphOffset + 4)
	local xMax = readI16BE(buf, glyphOffset + 6)
	local yMax = readI16BE(buf, glyphOffset + 8)

	local x0 = math.floor(xMin * scaleX)
	local y0 = math.floor(-yMax * scaleY)
	local x1 = math.ceil(xMax * scaleX)
	local y1 = math.ceil(-yMin * scaleY)

	return x0, y0, x1, y1
end

type Point = { x: number, y: number, onCurve: boolean }
type Contour = { points: { Point } }
type Segment = { x1: number, y1: number, x2: number, y2: number }

local function getGlyphContours(fontInfo: FontInfo, glyphIndex: number): { Contour }
	local contours: { Contour } = {}

	local glyf = fontInfo.tables["glyf"]
	local loca = fontInfo.tables["loca"]
	if not glyf or not loca then
		return contours
	end

	local buf = fontInfo.buffer
	local glyphOffset = 0
	local nextOffset = 0

	if fontInfo.indexToLocFormat == 0 then
		glyphOffset = glyf.offset + readU16BE(buf, loca.offset + glyphIndex * 2) * 2
		nextOffset = glyf.offset + readU16BE(buf, loca.offset + (glyphIndex + 1) * 2) * 2
	else
		glyphOffset = glyf.offset + readU32BE(buf, loca.offset + glyphIndex * 4)
		nextOffset = glyf.offset + readU32BE(buf, loca.offset + (glyphIndex + 1) * 4)
	end

	if glyphOffset >= nextOffset then
		return contours
	end

	local numberOfContours = readI16BE(buf, glyphOffset)

	if numberOfContours > 0 then
		local endPtsOfContours: { number } = table.create(numberOfContours)
		for c = 0, numberOfContours - 1 do
			endPtsOfContours[c + 1] = readU16BE(buf, glyphOffset + 10 + c * 2)
		end

		local numPoints = endPtsOfContours[numberOfContours] + 1
		local insLenOffset = glyphOffset + 10 + numberOfContours * 2
		local instructionLength = readU16BE(buf, insLenOffset)
		local flagsOffset = insLenOffset + 2 + instructionLength

		local flags: { number } = table.create(numPoints)
		local ptr = flagsOffset
		local i = 1
		while i <= numPoints do
			local flag = buffer.readu8(buf, ptr)
			ptr += 1
			flags[i] = flag
			i += 1
			if bit32.band(flag, 8) ~= 0 then
				local count = buffer.readu8(buf, ptr)
				ptr += 1
				for _ = 1, count do
					if i <= numPoints then
						flags[i] = flag
						i += 1
					end
				end
			end
		end

		local xPoints: { number } = table.create(numPoints)
		local currX = 0
		for k = 1, numPoints do
			local f = flags[k]
			local xShort = bit32.band(f, 2) ~= 0
			local xSame = bit32.band(f, 16) ~= 0
			if xShort then
				local dx = buffer.readu8(buf, ptr)
				ptr += 1
				if not xSame then
					dx = -dx
				end
				currX += dx
			elseif not xSame then
				local dx = readI16BE(buf, ptr)
				ptr += 2
				currX += dx
			end
			xPoints[k] = currX
		end

		local yPoints: { number } = table.create(numPoints)
		local currY = 0
		for k = 1, numPoints do
			local f = flags[k]
			local yShort = bit32.band(f, 4) ~= 0
			local ySame = bit32.band(f, 32) ~= 0
			if yShort then
				local dy = buffer.readu8(buf, ptr)
				ptr += 1
				if not ySame then
					dy = -dy
				end
				currY += dy
			elseif not ySame then
				local dy = readI16BE(buf, ptr)
				ptr += 2
				currY += dy
			end
			yPoints[k] = currY
		end

		local startIdx = 1
		for c = 1, numberOfContours do
			local endIdx = endPtsOfContours[c] + 1
			local contourPoints: { Point } = {}
			for k = startIdx, endIdx do
				table.insert(contourPoints, {
					x = xPoints[k],
					y = yPoints[k],
					onCurve = bit32.band(flags[k], 1) ~= 0,
				})
			end
			table.insert(contours, { points = contourPoints })
			startIdx = endIdx + 1
		end
	elseif numberOfContours < 0 then
		local ptr = glyphOffset + 10
		local MORE_COMPONENTS = 0x0020
		local ARG_1_AND_2_ARE_WORDS = 0x0001
		local ARGS_ARE_XY_VALUES = 0x0002
		local WE_HAVE_A_SCALE = 0x0008
		local WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
		local WE_HAVE_A_TWO_BY_TWO = 0x0080

		while true do
			local compFlags = readU16BE(buf, ptr)
			ptr += 2
			local subGlyphIndex = readU16BE(buf, ptr)
			ptr += 2

			local arg1: number, arg2: number
			if bit32.band(compFlags, ARG_1_AND_2_ARE_WORDS) ~= 0 then
				arg1 = readI16BE(buf, ptr)
				ptr += 2
				arg2 = readI16BE(buf, ptr)
				ptr += 2
			else
				arg1 = buffer.readi8(buf, ptr)
				ptr += 1
				arg2 = buffer.readi8(buf, ptr)
				ptr += 1
			end

			local mtxA, mtxB, mtxC, mtxD = 1, 0, 0, 1
			if bit32.band(compFlags, WE_HAVE_A_SCALE) ~= 0 then
				local scale = readI16BE(buf, ptr) / 16384
				ptr += 2
				mtxA = scale
				mtxD = scale
			elseif bit32.band(compFlags, WE_HAVE_AN_X_AND_Y_SCALE) ~= 0 then
				mtxA = readI16BE(buf, ptr) / 16384
				ptr += 2
				mtxD = readI16BE(buf, ptr) / 16384
				ptr += 2
			elseif bit32.band(compFlags, WE_HAVE_A_TWO_BY_TWO) ~= 0 then
				mtxA = readI16BE(buf, ptr) / 16384
				ptr += 2
				mtxB = readI16BE(buf, ptr) / 16384
				ptr += 2
				mtxC = readI16BE(buf, ptr) / 16384
				ptr += 2
				mtxD = readI16BE(buf, ptr) / 16384
				ptr += 2
			end

			local dx = 0
			local dy = 0
			if bit32.band(compFlags, ARGS_ARE_XY_VALUES) ~= 0 then
				dx = arg1
				dy = arg2
			end

			local subContours = getGlyphContours(fontInfo, subGlyphIndex)
			for _, subContour in subContours do
				local transformedPoints: { Point } = {}
				for _, p in subContour.points do
					local newX = mtxA * p.x + mtxC * p.y + dx
					local newY = mtxB * p.x + mtxD * p.y + dy
					table.insert(transformedPoints, {
						x = newX,
						y = newY,
						onCurve = p.onCurve,
					})
				end
				table.insert(contours, { points = transformedPoints })
			end

			if bit32.band(compFlags, MORE_COMPONENTS) == 0 then
				break
			end
		end
	end

	return contours
end

function StbTrueType.MakeCodepointBitmap(
	fontInfo: FontInfo,
	codepointOrWidth: number,
	scaleXOrHeight: number?,
	scaleYParam: number?,
	widthParam: number?,
	heightParam: number?,
	x0Param: number?,
	y0Param: number?
): { number }
	local codepoint: number
	local scaleX: number
	local scaleY: number
	local width: number
	local height: number
	local x0: number
	local y0: number

	if widthParam ~= nil and heightParam ~= nil then
		codepoint = codepointOrWidth
		scaleX = scaleXOrHeight or 1
		scaleY = scaleYParam or scaleX
		width = widthParam
		height = heightParam
		x0 = x0Param or 0
		y0 = y0Param or 0
	else
		codepoint = 0
		scaleX = 1
		scaleY = 1
		width = codepointOrWidth
		height = scaleXOrHeight or 0
		x0 = 0
		y0 = 0
	end

	local bitmap: { number } = table.create(width * height, 0)
	if width <= 0 or height <= 0 then
		return bitmap
	end

	local glyphIndex = StbTrueType.GetGlyphIndex(fontInfo, codepoint)
	local contours = getGlyphContours(fontInfo, glyphIndex)
	if #contours == 0 then
		return bitmap
	end

	local lineSegments: { Segment } = {}
	for _, contour in contours do
		local pts = contour.points
		local nP = #pts
		if nP < 2 then
			continue
		end

		local startIndex = 1
		local firstPt = pts[1]
		local startP: { x: number, y: number }

		if firstPt.onCurve then
			startP = { x = firstPt.x, y = firstPt.y }
			startIndex = 2
		else
			local lastPt = pts[nP]
			if lastPt.onCurve then
				startP = { x = lastPt.x, y = lastPt.y }
				startIndex = 1
			else
				startP = { x = (firstPt.x + lastPt.x) / 2, y = (firstPt.y + lastPt.y) / 2 }
				startIndex = 1
			end
		end

		local currentP = startP
		local i = 0
		while i < nP do
			local idx = (startIndex - 1 + i) % nP + 1
			local pt = pts[idx]

			if pt.onCurve then
				table.insert(lineSegments, {
					x1 = currentP.x,
					y1 = currentP.y,
					x2 = pt.x,
					y2 = pt.y,
				})
				currentP = { x = pt.x, y = pt.y }
				i += 1
			else
				local ctrlP = pt
				local nextIdx = (idx % nP) + 1
				local nextPt = pts[nextIdx]
				local endP: { x: number, y: number }

				if nextPt.onCurve then
					endP = { x = nextPt.x, y = nextPt.y }
					i += 2
				else
					endP = { x = (ctrlP.x + nextPt.x) / 2, y = (ctrlP.y + nextPt.y) / 2 }
					i += 1
				end

				local STEPS = 5
				local prevX, prevY = currentP.x, currentP.y
				for s = 1, STEPS do
					local t = s / STEPS
					local invT = 1 - t
					local w0 = invT * invT
					local w1 = 2 * invT * t
					local w2 = t * t
					local bx = w0 * currentP.x + w1 * ctrlP.x + w2 * endP.x
					local by = w0 * currentP.y + w1 * ctrlP.y + w2 * endP.y
					table.insert(lineSegments, {
						x1 = prevX,
						y1 = prevY,
						x2 = bx,
						y2 = by,
					})
					prevX, prevY = bx, by
				end
				currentP = endP
			end
		end

		if currentP.x ~= startP.x or currentP.y ~= startP.y then
			table.insert(lineSegments, {
				x1 = currentP.x,
				y1 = currentP.y,
				x2 = startP.x,
				y2 = startP.y,
			})
		end
	end

	local bitmapSegments: { Segment } = {}
	for _, seg in lineSegments do
		local bx1 = seg.x1 * scaleX - x0
		local by1 = -seg.y1 * scaleY - y0
		local bx2 = seg.x2 * scaleX - x0
		local by2 = -seg.y2 * scaleY - y0

		if by1 ~= by2 then
			table.insert(bitmapSegments, {
				x1 = bx1,
				y1 = by1,
				x2 = bx2,
				y2 = by2,
			})
		end
	end

	local subpixelHits: { number } = table.create(width * height, 0)
	local subYOffsets = { 0.125, 0.375, 0.625, 0.875 }
	local subXOffsets = { 0.125, 0.375, 0.625, 0.875 }

	for y = 0, height - 1 do
		for _, syOffset in subYOffsets do
			local sampleY = y + syOffset

			local intersections: { { x: number, dir: number } } = {}
			for _, seg in bitmapSegments do
				local yMin = math.min(seg.y1, seg.y2)
				local yMax = math.max(seg.y1, seg.y2)
				if sampleY >= yMin and sampleY < yMax then
					local t = (sampleY - seg.y1) / (seg.y2 - seg.y1)
					local xInt = seg.x1 + t * (seg.x2 - seg.x1)
					local dir = if seg.y2 > seg.y1 then 1 else -1
					table.insert(intersections, { x = xInt, dir = dir })
				end
			end

			if #intersections >= 2 then
				table.sort(intersections, function(a, b)
					return a.x < b.x
				end)

				local winding = 0
				for k = 1, #intersections - 1 do
					winding += intersections[k].dir
					if winding ~= 0 then
						local xStart = intersections[k].x
						local xEnd = intersections[k + 1].x

						local minPx = math.clamp(math.floor(xStart), 0, width - 1)
						local maxPx = math.clamp(math.floor(xEnd), 0, width - 1)

						for px = minPx, maxPx do
							for _, sxOffset in subXOffsets do
								local sampleX = px + sxOffset
								if sampleX >= xStart and sampleX < xEnd then
									local index = y * width + px + 1
									subpixelHits[index] += 1
								end
							end
						end
					end
				end
			end
		end
	end

	for i = 1, width * height do
		local hits = subpixelHits[i]
		if hits > 0 then
			bitmap[i] = math.clamp(math.floor((hits / 16) * 255), 0, 255)
		end
	end

	return bitmap
end

return StbTrueType
