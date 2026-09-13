--!strict
-- Выпуклые профили выдавливаются без EditableMesh и разрешений на ассеты.
-- Каждый треугольник покрывается двумя прямоугольными клиньями без щелей.
local Solid = {}

function Solid.outline(x, y, w, h, corner)
	local r = math.min(corner, w / 2, h / 2)
	if r <= 0 then
		return {Vector2.new(x,y), Vector2.new(x+w,y), Vector2.new(x+w,y+h), Vector2.new(x,y+h)}
	end
	return {Vector2.new(x+r,y), Vector2.new(x+w-r,y), Vector2.new(x+w,y+r), Vector2.new(x+w,y+h-r),
		Vector2.new(x+w-r,y+h), Vector2.new(x+r,y+h), Vector2.new(x,y+h-r), Vector2.new(x,y+r)}
end

function Solid.wedges(a, b, c, thickness)
	local ab, ac, bc = b-a, c-a, c-b
	if ab:Dot(ab) > ac:Dot(ac) and ab:Dot(ab) > bc:Dot(bc) then a,c = c,a
	elseif ac:Dot(ac) > bc:Dot(bc) then a,b = b,a end
	ab,ac,bc = b-a,c-a,c-b
	if ac:Cross(ab).Magnitude < 1e-8 then return {} end
	local right = ac:Cross(ab).Unit
	local back = bc.Unit
	local up = bc:Cross(right).Unit
	local height = math.abs(ab:Dot(up))
	local result = {}
	local first, second = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if first > 1e-7 then table.insert(result, {size=Vector3.new(thickness,height,first), frame=CFrame.fromMatrix((a+b)/2,right,up,back)}) end
	if second > 1e-7 then table.insert(result, {size=Vector3.new(thickness,height,second), frame=CFrame.fromMatrix((a+c)/2,-right,up,-back)}) end
	return result
end

function Solid.prism(polygon, bottom, top, unit)
	local result = {}
	if #polygon < 3 then return result end
	local function world(p) return Vector3.new(p.X*unit,(bottom+top)/2,p.Y*unit) end
	for i=2,#polygon-1 do
		for _, wedge in Solid.wedges(world(polygon[1]),world(polygon[i]),world(polygon[i+1]),top-bottom) do
			table.insert(result,wedge)
		end
	end
	return result
end
return Solid
