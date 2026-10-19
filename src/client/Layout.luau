--!strict
-- Расчёт области всей перестановки отдельно от UI: смена размера окна
-- должна менять только масштаб сцены, не геометрию и не прогресс раунда.
local Layout = {}

-- Начало свободной части верхней панели сообщает Roblox: ширина меню
-- меняется с версией клиента. На очень узком экране оставляем саму сумму.
function Layout.counter(width: number, freeStart: number)
 local left=math.max(128,freeStart+8)
 local available=math.max(1,width-left-76)
 return {x=left,width=available,compact=available<120}
end

function Layout.presentation(width: number, height: number, portraitPadding)
	local landscape = width >= 568 and width >= height * 1.3
	local docked = landscape and width >= 1100
	local left = if landscape then (if docked then 220 else 180) else 0
	local right = if docked then 320 else 0
	return {
		landscape = landscape, docked = docked, left = left, right = right,
		padding = if landscape then {
			left = left + 24, right = right + 24, side = 0, top = 60, bottom = 24, maxScale = 2.5,
		} else portraitPadding,
	}
end

-- Кухня и ателье используют один порог ориентации и одну строку кнопок.
-- Раньше почти квадратный экран получал счётчик и прогулку в одном месте.
function Layout.toolbar(width: number, height: number)
 local mode=Layout.presentation(width,height,nil)
 if mode.landscape then
  return {walk={x=(width-164)/2,y=12,width=164,height=32}}
 end
 local widthOfButton=(width-48)/3
 return {
  journal={x=12,y=90,width=widthOfButton,height=38},
  walk={x=24+widthOfButton,y=90,width=widthOfButton,height=38},
  workshop={x=36+widthOfButton*2,y=90,width=widthOfButton,height=38},
 }
end

function Layout.bounds(recipe, trick, tileWidth: number, tileHeight: number, geom)
	local minX, minY, maxX, maxY = 0, 0, recipe.cols, recipe.rows
	local cut = recipe.cuts[1]
	local line = { a = Vector2.new(cut[1].x, cut[1].y), b = Vector2.new(cut[#cut].x, cut[#cut].y) }
	for _, name in trick.pieceOrder do
		local spec = trick.pieces[name]
		local bounds = spec.bounds
		local polygon = {
			Vector2.new(bounds[1], bounds[2]), Vector2.new(bounds[3], bounds[2]),
			Vector2.new(bounds[3], bounds[4]), Vector2.new(bounds[1], bounds[4]),
		}
		-- У диагональных частей большая часть прямоугольника прозрачна.
		-- Учитываем настоящий полигон, чтобы не уменьшать шоколадку из-за пустоты.
		if spec.clip ~= "rect" then
			polygon = geom.clipPolygon(polygon, line, spec.clip == "upper")
		end
		local offsets={ {dx=0,dy=0},trick.exploded[name],recipe.slides[name] }
		for _,p in (trick.waypoints and trick.waypoints[name]) or {} do table.insert(offsets,p) end
		for _, offset in offsets do
			if offset then
				for _, point in polygon do
					minX = math.min(minX, point.X + offset.dx)
					minY = math.min(minY, point.Y + offset.dy)
					maxX = math.max(maxX, point.X + offset.dx)
					maxY = math.max(maxY, point.Y + offset.dy)
				end
			end
		end
	end
	return { minX = minX * tileWidth, minY = minY * tileHeight, maxX = maxX * tileWidth, maxY = maxY * tileHeight }
end

function Layout.fit(width: number, height: number, bounds, padding)
	if width <= 0 or height <= 0 then
		return nil
	end
	local left, right = padding.left or padding.side, padding.right or padding.side
	local availableWidth = math.max(1, width - left - right)
	local availableHeight = math.max(1, height - padding.top - padding.bottom)
	local spanX = bounds.maxX - bounds.minX
	local spanY = bounds.maxY - bounds.minY
	local scale = math.min(padding.maxScale or 1, availableWidth / spanX, availableHeight / spanY)
	return {
		scale = scale,
		x = left + (availableWidth - spanX * scale) / 2 - bounds.minX * scale,
		y = padding.top + (availableHeight - spanY * scale) / 2 - bounds.minY * scale,
	}
end

return Layout
