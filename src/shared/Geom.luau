--!strict
-- Чистая геометрия: модуль не знает о Roblox-сервисах и UI.

local Geom = {}

export type Segment = {
	a: Vector2,
	b: Vector2,
	len: number,
	start: number,
}

export type Path = {
	segments: { Segment },
	length: number,
}

export type Line = {
	a: Vector2,
	b: Vector2,
}

function Geom.path(points: { Vector2 }): Path
	local segments: { Segment } = {}
	local total = 0

	for index = 1, #points - 1 do
		local a = points[index]
		local b = points[index + 1]
		local len = (b - a).Magnitude
		if len > 0 then
			table.insert(segments, {
				a = a,
				b = b,
				len = len,
				start = total,
			})
			total += len
		end
	end

	return { segments = segments, length = total }
end

function Geom.project(path: Path, point: Vector2): (number, number)
	local nearestDistance = math.huge
	local nearestArc = 0

	for _, segment in path.segments do
		local delta = segment.b - segment.a
		local t = 0
		if segment.len > 0 then
			t = math.clamp((point - segment.a):Dot(delta) / (segment.len * segment.len), 0, 1)
		end
		local projected = segment.a + delta * t
		local distance = (point - projected).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestArc = segment.start + segment.len * t
		end
	end

	return nearestDistance, nearestArc
end

function Geom.pointAt(path: Path, arc: number): Vector2
	if #path.segments == 0 then
		return Vector2.zero
	end

	local target = math.clamp(arc, 0, path.length)
	for _, segment in path.segments do
		if target <= segment.start + segment.len then
			return segment.a + (segment.b - segment.a) * ((target - segment.start) / segment.len)
		end
	end

	local last = path.segments[#path.segments]
	return last.b
end

function Geom.cross(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

function Geom.lineSide(line: Line, point: Vector2): number
	return Geom.cross(line.b - line.a, point - line.a)
end

function Geom.isUpper(line: Line, point: Vector2, epsilon: number?): boolean
	-- В экранных координатах Y растёт вниз. Для нашего реза слева снизу
	-- направо вверх верхняя полуплоскость находится с отрицательной стороны.
	return Geom.lineSide(line, point) <= (epsilon or 0)
end

function Geom.lineYAtX(line: Line, x: number): number
	local dx = line.b.X - line.a.X
	if math.abs(dx) < 1e-9 then
		return line.a.Y
	end
	local t = (x - line.a.X) / dx
	return line.a.Y + (line.b.Y - line.a.Y) * t
end

function Geom.tangentError(line: Line, offset: Vector2): number
	local direction = line.b - line.a
	if direction.Magnitude < 1e-9 then
		return offset.Magnitude
	end
	-- Ноль означает, что перенос идёт строго вдоль шва и не открывает
	-- фальшивую щель между двумя половинами.
	return math.abs(Geom.cross(direction, offset)) / direction.Magnitude
end

local function segmentLineIntersection(from: Vector2, to: Vector2, line: Line): Vector2
	local fromSide = Geom.lineSide(line, from)
	local toSide = Geom.lineSide(line, to)
	local denominator = fromSide - toSide
	if math.abs(denominator) < 1e-9 then
		return from
	end
	return from + (to - from) * (fromSide / denominator)
end

function Geom.clipPolygon(polygon: { Vector2 }, line: Line, keepUpper: boolean): { Vector2 }
	local result: { Vector2 } = {}
	if #polygon == 0 then
		return result
	end

	local function inside(point: Vector2): boolean
		local side = Geom.lineSide(line, point)
		return if keepUpper then side <= 1e-7 else side >= -1e-7
	end

	local previous = polygon[#polygon]
	local previousInside = inside(previous)
	for _, current in polygon do
		local currentInside = inside(current)
		if currentInside ~= previousInside then
			table.insert(result, segmentLineIntersection(previous, current, line))
		end
		if currentInside then
			table.insert(result, current)
		end
		previous = current
		previousInside = currentInside
	end

	return result
end

function Geom.polygonArea(polygon: { Vector2 }): number
	local twiceArea = 0
	for index, point in polygon do
		local nextPoint = polygon[index % #polygon + 1]
		twiceArea += Geom.cross(point, nextPoint)
	end
	return math.abs(twiceArea) * 0.5
end

return Geom
