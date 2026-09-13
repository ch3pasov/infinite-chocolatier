--!strict
-- Явная перспективная проекция: камера ViewportFrame не сообщает размер
-- своего окна через Camera.ViewportSize. Рисунок и ввод используют одну матрицу.
local Projection = {}

function Projection.lookAt(eye, target)
	local back = (eye-target).Unit
	local right = Vector3.yAxis:Cross(back).Unit
	return CFrame.fromMatrix(eye,right,back:Cross(right),back)
end

function Projection.project(camera, size, fov, world)
	local p = camera:PointToObjectSpace(world)
	local focal = size.Y / (2 * math.tan(math.rad(fov) / 2))
	return Vector2.new(size.X / 2 + p.X * focal / -p.Z, size.Y / 2 - p.Y * focal / -p.Z)
end

function Projection.unproject(camera, size, fov, point, height)
	local focal = size.Y / (2 * math.tan(math.rad(fov) / 2))
	local direction = camera:VectorToWorldSpace(Vector3.new((point.X - size.X / 2) / focal, -(point.Y - size.Y / 2) / focal, -1))
	local origin = camera.Position
	if math.abs(direction.Y) < 1e-8 then return nil end
	local distance = (height - origin.Y) / direction.Y
	if distance <= 0 then return nil end
	return origin + direction * distance
end

function Projection.fit(size, bounds, settings)
	local unit = settings.unitsPerPixel
	local target = Vector3.new((bounds.minX + bounds.maxX) * unit / 2, settings.surfaceHeight,
		(bounds.minY + bounds.maxY) * unit / 2)
	local tilt = math.rad(settings.cameraTilt)
	local direction = Vector3.new(0, math.cos(tilt), math.sin(tilt))
	local points = {}
	for _, x in {bounds.minX, bounds.maxX} do
		for _, z in {bounds.minY, bounds.maxY} do
			for _, y in {0, settings.surfaceHeight + 0.7} do
				table.insert(points, Vector3.new(x * unit, y, z * unit))
			end
		end
	end
	local low, high = 5, 500
	for _ = 1, 40 do
		local distance = (low + high) / 2
		local camera = Projection.lookAt(target + direction * distance, target)
		local fits = true
		for _, p in points do
			local screen = Projection.project(camera, size, settings.fieldOfView, p)
			if screen.X < 24 or screen.X > size.X - 24 or screen.Y < 24 or screen.Y > size.Y - 24 then fits = false end
		end
		if fits then high = distance else low = distance end
	end
	return Projection.lookAt(target + direction * high, target)
end
return Projection
