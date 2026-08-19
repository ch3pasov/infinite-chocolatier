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

	harness.test("точка на дуге возвращается для продолжения жеста", function()
		local path = Geom.path({ V.new(0, 0), V.new(3, 0), V.new(3, 4) })
		harness.equals(Geom.pointAt(path, 0), V.new(0, 0))
		harness.equals(Geom.pointAt(path, 5), V.new(3, 2))
		harness.equals(Geom.pointAt(path, 99), V.new(3, 4))
	end)

	harness.test("диагональ делит прямоугольник без потери площади", function()
		local line = { a = V.new(0, 3.75), b = V.new(5, 1.25) }
		local board = { V.new(0, 0), V.new(5, 0), V.new(5, 5), V.new(0, 5) }
		local upper = Geom.clipPolygon(board, line, true)
		local lower = Geom.clipPolygon(board, line, false)
		harness.near(Geom.polygonArea(upper) + Geom.polygonArea(lower), 25)
	end)

	harness.test("перенос вдоль диагонали не раскрывает внутреннюю щель", function()
		local line = { a = V.new(0, 3.75), b = V.new(5, 1.25) }
		harness.near(Geom.tangentError(line, V.new(1, -0.5)), 0)
	end)

	harness.test("верхняя полуплоскость учитывает экранное направление Y", function()
		local line = { a = V.new(0, 4), b = V.new(5, 1.5) }
		harness.equals(Geom.isUpper(line, V.new(2, 1)), true)
		harness.equals(Geom.isUpper(line, V.new(2, 4)), false)
	end)
end
