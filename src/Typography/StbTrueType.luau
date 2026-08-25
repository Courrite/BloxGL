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

local function distanceToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number): number
	local vx = bx - ax
	local vy = by - ay
	local lenSq = vx * vx + vy * vy
	if lenSq == 0 then
		local dx = px - ax
		local dy = py - ay
		return math.sqrt(dx * dx + dy * dy)
	end
	local wx = px - ax
	local wy = py - ay
	local t = math.clamp((wx * vx + wy * vy) / lenSq, 0, 1)
	local nx = ax + t * vx
	local ny = ay + t * vy
	local dx = px - nx
	local dy = py - ny
	return math.sqrt(dx * dx + dy * dy)
end

local function flattenQuadratic(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	steps: number,
	outSegments: { { ax: number, ay: number, bx: number, by: number } }
)
	local prevX, prevY = ax, ay
	for i = 1, steps do
		local t = i / steps
		local invT = 1 - t
		-- binomial expansion of quadratic bezier formula: (1-t)^2 * A + 2t(1-t) * B + t^2 * C
		local x = invT * invT * ax + 2 * invT * t * bx + t * t * cx
		local y = invT * invT * ay + 2 * invT * t * by + t * t * cy

		table.insert(outSegments, { ax = prevX, ay = prevY, bx = x, by = y })
		prevX, prevY = x, y
	end
end

local function getGlyphSegments(
	contours: { { points: { Point } } },
	scaleX: number,
	scaleY: number,
	originX: number,
	originY: number
)
	local segments: { { ax: number, ay: number, bx: number, by: number } } = {}

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
				table.insert(segments, {
					ax = (currentP.x * scaleX) - originX,
					ay = (-currentP.y * scaleY) - originY,
					bx = (pt.x * scaleX) - originX,
					by = (-pt.y * scaleY) - originY,
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

				flattenQuadratic(
					(currentP.x * scaleX) - originX,
					(-currentP.y * scaleY) - originY,
					(ctrlP.x * scaleX) - originX,
					(-ctrlP.y * scaleY) - originY,
					(endP.x * scaleX) - originX,
					(-endP.y * scaleY) - originY,
					8,
					segments
				)
				currentP = endP
			end
		end

		if currentP.x ~= startP.x or currentP.y ~= startP.y then
			table.insert(segments, {
				ax = (currentP.x * scaleX) - originX,
				ay = (-currentP.y * scaleY) - originY,
				bx = (startP.x * scaleX) - originX,
				by = (-startP.y * scaleY) - originY,
			})
		end
	end

	return segments
end

function StbTrueType.MakeCodepointSDF(
	fontInfo: FontInfo,
	codepoint: number,
	scale: number,
	padding: number?
): ({ number }, number, number, number, number)
	local pad = padding or 12
	local scaleX = scale
	local scaleY = scale

	local x0, y0, x1, y1 = StbTrueType.GetCodepointBitmapBox(fontInfo, codepoint, scaleX, scaleY)
	local glyphWidth = math.max(0, math.ceil(x1) - math.floor(x0)) + 2
	local glyphHeight = math.max(0, math.ceil(y1) - math.floor(y0)) + 2

	if glyphWidth == 0 or glyphHeight == 0 then
		return {}, 0, 0, 0, 0
	end

	local width = glyphWidth + pad * 2
	local height = glyphHeight + pad * 2
	local originX = x0 - pad
	local originY = y0 - pad

	local contours = getGlyphContours(fontInfo, StbTrueType.GetGlyphIndex(fontInfo, codepoint))
	local segments = getGlyphSegments(contours, scaleX, scaleY, originX, originY)

	local bufferOut = table.create(width * height, 0)
	local maxDist = pad

	for py = 0, height - 1 do
		local pixelY = py + 0.5
		for px = 0, width - 1 do
			local pixelX = px + 0.5

			local minDist = 1e9
			local inside = false

			for _, seg in segments do
				local d = distanceToSegment(pixelX, pixelY, seg.ax, seg.ay, seg.bx, seg.by)
				if d < minDist then
					minDist = d
				end

				-- ray casting along +x (right) to determine winding (inside vs outside)
				-- check if the segment crosses the height of the pixel
				if (seg.ay <= pixelY and seg.by > pixelY) or (seg.by <= pixelY and seg.ay > pixelY) then
					-- find where the x coordinate where line segment crosses the height, where height is pixelY
					local crossX = seg.ax + (pixelY - seg.ay) / (seg.by - seg.ay) * (seg.bx - seg.ax)
					-- is crossX to the right of the pixel
					if crossX > pixelX then
						inside = not inside
					end
				end
			end

			local signedDist = if inside then -minDist else minDist
			local normD = math.clamp(-signedDist / maxDist, -1, 1)
			local byteVal = math.clamp(math.floor((normD * 0.5 + 0.5) * 255 + 0.5), 0, 255)

			bufferOut[py * width + px + 1] = byteVal
		end
	end

	return bufferOut, width, height, x0 - pad, y0 - pad
end

return StbTrueType
