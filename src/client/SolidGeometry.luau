--!strict
-- Выпуклые профили выдавливаются без EditableMesh и разрешений на ассеты.
-- Цельные блоки покрывают плоские центры, клинья — только наклонные края.
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
	-- Разбиваем выпуклый профиль вертикальными полосами. Плоский центр
	-- дольки становится одним Part, а не веером из тонких клиньев.
	local xs={}
	for _,p in polygon do table.insert(xs,p.X) end
	table.sort(xs)
	local function extent(x)
		local lo,hi=math.huge,-math.huge
		for i,a in polygon do
			local b=polygon[i%#polygon+1]
			if math.abs(b.X-a.X)>1e-8 and x>=math.min(a.X,b.X)-1e-7 and x<=math.max(a.X,b.X)+1e-7 then
				local y=a.Y+(b.Y-a.Y)*(x-a.X)/(b.X-a.X)
				lo=math.min(lo,y); hi=math.max(hi,y)
			end
		end
		return lo,hi
	end
	local function triangle(a,b,c)
		for _,w in Solid.wedges(world(a),world(b),world(c),top-bottom) do table.insert(result,w) end
	end
	for i=1,#xs-1 do
		local left,right=xs[i],xs[i+1]
		if right-left>1e-7 then
			local loL,hiL=extent(left)
			local loR,hiR=extent(right)
			local lo,hi=math.max(loL,loR),math.min(hiL,hiR)
			if hi>=lo then
				if hi-lo>1e-7 then
					table.insert(result,{kind='Part',size=Vector3.new((right-left)*unit,top-bottom,(hi-lo)*unit),
						frame=CFrame.new((left+right)*unit/2,(bottom+top)/2,(lo+hi)*unit/2)})
				end
				triangle(Vector2.new(left,loL),Vector2.new(right,loR),Vector2.new(if loL<loR then left else right,lo))
				triangle(Vector2.new(left,hiL),Vector2.new(right,hiR),Vector2.new(if hiL>hiR then left else right,hi))
			else
				triangle(Vector2.new(left,loL),Vector2.new(right,loR),Vector2.new(right,hiR))
				triangle(Vector2.new(left,loL),Vector2.new(right,hiR),Vector2.new(left,hiL))
			end
		end
	end
	return result
end
return Solid
