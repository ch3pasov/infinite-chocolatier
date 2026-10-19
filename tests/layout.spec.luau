--!nostrict
-- Проверяем все крайние и промежуточные положения частей, а не только
-- цельную плитку: иначе награда и верхний кусок пропадут на узком экране.
local Layout = require("../src/client/Layout")
local Config = require("../src/shared/Config")
local Recipe = require("../src/shared/Recipe")
local Geom = require("../src/shared/Geom")

return function(harness)
	harness.test('счётчик не пересекает расширенную панель Roblox и кнопку звука',function()
		for _,width in {296,336,400,520} do
			for _,freeStart in {120,164,192} do
				local counter=Layout.counter(width,freeStart)
				assert(counter.x>=freeStart+8)
				assert(counter.x+counter.width<=width-76)
			end
		end
		harness.equals(Layout.counter(400,164).compact,false)
		harness.equals(Layout.counter(296,164).compact,true)
	end)
	local recipe = Recipe.build(Config.Recipe)
	local tileWidth, tileHeight = 66, 104
	local bounds = Layout.bounds(recipe, Config.Trick, tileWidth, tileHeight, Geom)
	local padding = Config.Board.viewportPadding

	harness.test("горизонтальная сцена отделена от боковых панелей во всех размерах", function()
		for _, viewport in { {568, 320}, {844, 390}, {1024, 768}, {1100, 720}, {1440, 900}, {2560, 1440} } do
			local mode = Layout.presentation(viewport[1], viewport[2], padding)
			assert(mode.landscape)
			local fit = Layout.fit(viewport[1], viewport[2], bounds, mode.padding)
			assert(fit.x + bounds.minX * fit.scale >= mode.left + 24 - 1e-6)
			assert(fit.x + bounds.maxX * fit.scale <= viewport[1] - mode.right - 24 + 1e-6)
			assert(fit.y + bounds.minY * fit.scale >= 60 - 1e-6)
			assert(fit.y + bounds.maxY * fit.scale <= viewport[2] - 24 + 1e-6)
		end
	end)
 harness.test("строка кнопок использует тот же порог, что счётчик и сцена",function()
  for _,size in {{320,568},{390,844},{1280,1033},{1024,768},{568,320},{844,390}} do
   local mode=Layout.presentation(size[1],size[2],padding)
   local toolbar=Layout.toolbar(size[1],size[2]); local walk=toolbar.walk
   assert(walk.x>=12 and walk.x+walk.width<=size[1]-12)
   if mode.landscape then
    assert(walk.x>=mode.left and walk.y+walk.height+16<=mode.padding.top)
   else
    local journal,shop=toolbar.journal,toolbar.workshop
    assert(journal.x+journal.width+12<=walk.x+.001)
    assert(walk.x+walk.width+12<=shop.x+.001)
    assert(walk.y>60 and walk.y+walk.height+24<=mode.padding.top)
   end
  end
 end)

	harness.test("вертикальный телефон сохраняет прежние поля, большой экран увеличивает плитку", function()
		local phone = Layout.presentation(390, 844, padding)
		harness.equals(phone.landscape, false)
		harness.equals(phone.padding, padding)
		local desktop = Layout.presentation(1920, 1080, padding)
		harness.equals(desktop.docked, true)
		local old = Layout.fit(1920, 1080, bounds, padding)
		local new = Layout.fit(1920, 1080, bounds, desktop.padding)
		assert(new.scale > old.scale * 1.4)
	end)

	harness.test("область сцены включает внешнюю дольку и верхнюю часть", function()
		harness.near(bounds.minX, -1.95 * tileWidth)
		harness.near(bounds.minY, -1.8 * tileHeight)
		harness.near(bounds.maxX, 5 * tileWidth)
		harness.near(bounds.maxY, 5 * tileHeight)
	end)

	harness.test("вся перестановка помещается между счётчиком и подсказкой", function()
		for _, viewport in { {320, 568}, {375, 667}, {390, 844}, {568, 320}, {844, 390}, {768, 1024}, {1280, 720}, {2560, 1440} } do
			local fit = Layout.fit(viewport[1], viewport[2], bounds, padding)
			assert(fit.scale > 0 and fit.scale <= 1)
			for _, name in Config.Trick.pieceOrder do
				local spec = Config.Trick.pieces[name]
				local piece = spec.bounds
				local polygon = {
					Vector2.new(piece[1], piece[2]), Vector2.new(piece[3], piece[2]),
					Vector2.new(piece[3], piece[4]), Vector2.new(piece[1], piece[4]),
				}
				if spec.clip ~= "rect" then
					polygon = Geom.clipPolygon(polygon, { a = Vector2.new(0, 3.5), b = Vector2.new(5, 1.5) }, spec.clip == "upper")
				end
				local exploded = Config.Trick.exploded[name]
				local assembled = recipe.slides[name] or { dx = 0, dy = 0 }
				for _, endpoints in { { {dx = 0, dy = 0}, exploded }, { exploded, assembled } } do
					for step = 0, 10 do
						local t = step / 10
						local dx = endpoints[1].dx * (1 - t) + endpoints[2].dx * t
						local dy = endpoints[1].dy * (1 - t) + endpoints[2].dy * t
						for _, point in polygon do
							local x = fit.x + (point.X + dx) * tileWidth * fit.scale
							local y = fit.y + (point.Y + dy) * tileHeight * fit.scale
							assert(x >= padding.side - 1e-6 and x <= viewport[1] - padding.side + 1e-6, name)
							assert(y >= padding.top - 1e-6 and y <= viewport[2] - padding.bottom + 1e-6, name)
						end
					end
				end
			end
		end
	end)

	harness.test("уменьшение окна обратимо и не меняет пропорции плитки", function()
		local before = Layout.fit(1280, 720, bounds, padding)
		Layout.fit(320, 568, bounds, padding)
		local after = Layout.fit(1280, 720, bounds, padding)
		harness.near(before.scale, after.scale)
		harness.near(before.x, after.x)
		harness.near(before.y, after.y)
		harness.near(tileWidth * after.scale / (tileHeight * after.scale), tileWidth / tileHeight)
	end)

	harness.test("нулевой размер при создании интерфейса не даёт деления на ноль", function()
		harness.equals(Layout.fit(0, 720, bounds, padding), nil)
		harness.equals(Layout.fit(1280, 0, bounds, padding), nil)
	end)
end
