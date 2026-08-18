return function(harness)
	local Geom = require("../src/shared/Geom")
	local V = Vector2

	harness.test("длина пути складывается из звеньев", function()
		local path = Geom.path({ V.new(0, 0), V.new(3, 0), V.new(3, 4) })
		harness.near(path.length, 7)
	end)

	harness.test("проекция возвращает расстояние и дугу", function()
		local path = Geom.path({ V.new(0, 0), V.new(10, 0) })
		local distance, arc = Geom.project(path, V.new(4, 3))
		harness.near(distance, 3)
		harness.near(arc, 4)
	end)

	harness.test("вырожденные звенья не ломают путь", function()
		local path = Geom.path({ V.new(0, 0), V.new(0, 0), V.new(5, 0) })
		harness.equals(#path.segments, 1)
	end)
end
