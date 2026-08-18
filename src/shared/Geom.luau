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

return Geom
