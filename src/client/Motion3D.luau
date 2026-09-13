--!strict
-- Все положения — параллельные переносы неизменных частей по столу.
local Motion = {}
local function point(p) return Vector2.new(p.dx,p.dy) end
function Motion.pose(name, phase, t, layout, slides, passageY)
	local start=point(layout[name])
	local finish=point(slides[name] or {dx=0,dy=0})
	local large=name=='upperLeft' or name=='upperRight'
	local strip=name=='stripDouble' or name=='stripSingle'
	if phase=='explode' then
		-- Правую часть сначала выводим из диагонали, затем отводим вбок:
		-- прямой выезд вправо пересёк бы неподвижное основание.
		if name=='upperRight' and start.X>1 then
			local corner=Vector2.new(0,start.Y)
			if t<0.4 then return Vector2.zero:Lerp(corner,t/0.4) end
			return corner:Lerp(start,(t-0.4)/0.6)
		end
		-- Малые части быстрее освобождают верхнюю кромку для больших.
		return Vector2.zero:Lerp(start,math.clamp(if strip then t*2 else t,0,1))
	elseif phase=='large' then
		if name=='upperLeft' then return start:Lerp(finish,t) end
		if name=='upperRight' then
			local corner=Vector2.new(start.X,passageY)
			local waiting=Vector2.new(finish.X,passageY)
			if t<0.4 then return start:Lerp(corner,t/0.4) end
			return corner:Lerp(waiting,(t-0.4)/0.6)
		end
	elseif phase=='join' then
		if name=='upperRight' then return Vector2.new(finish.X,passageY):Lerp(finish,t) end
		if large then return finish end
	elseif phase=='strip' then
		if large then return finish end
		if strip then return start:Lerp(finish,t) end
	end
	return start
end
function Motion.offset(_name,raw,_active,settings,_slides,_tileWidth,_tileHeight)
	return Vector3.new(raw.X*settings.unitsPerPixel,0,raw.Y*settings.unitsPerPixel)
end
return Motion
