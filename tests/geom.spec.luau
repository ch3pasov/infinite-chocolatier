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
		local line = { a = V.new(0, 3.5), b = V.new(5, 1.5) }
		local board = { V.new(0, 0), V.new(5, 0), V.new(5, 5), V.new(0, 5) }
		local upper = Geom.clipPolygon(board, line, true)
		local lower = Geom.clipPolygon(board, line, false)
		harness.near(Geom.polygonArea(upper) + Geom.polygonArea(lower), 25)
	end)

	harness.test("пять исходных частей сохраняют площадь плитки", function()
		local function rect(x0, y0, x1, y1)
			return { V.new(x0, y0), V.new(x1, y0), V.new(x1, y1), V.new(x0, y1) }
		end
		local line = { a = V.new(0, 3.5), b = V.new(5, 1.5) }
		local base = Geom.clipPolygon(rect(0, 0, 5, 5), line, false)
		local upperLeft = Geom.clipPolygon(rect(0, 1, 3, 5), line, true)
		local upperRight = Geom.clipPolygon(rect(3, 0, 5, 5), line, true)
		local area = Geom.polygonArea(base)
			+ Geom.polygonArea(upperLeft)
			+ Geom.polygonArea(upperRight)
			+ 2
			+ 1
		harness.near(area, 25)
	end)

	harness.test("Curry-полоса распределяет площадь одной дольки", function()
		local line = { a = V.new(0, 3.5), b = V.new(5, 1.5) }
		local leftOffset = V.new(2, -1)
		local rightOffset = V.new(-3, 1)
		local leftLine = { a = line.a + leftOffset, b = line.b + leftOffset }
		local rightLine = { a = line.a + rightOffset, b = line.b + rightOffset }
		harness.near(Geom.lineYAtX(leftLine, 2.5), Geom.lineYAtX(rightLine, 2.5))
		harness.near((Geom.lineYAtX(line, 0) - Geom.lineYAtX(leftLine, 0)) * 5, 1)
	end)

	harness.test("верхняя полуплоскость учитывает экранное направление Y", function()
		local line = { a = V.new(0, 4), b = V.new(5, 1.5) }
		harness.equals(Geom.isUpper(line, V.new(2, 1)), true)
		harness.equals(Geom.isUpper(line, V.new(2, 4)), false)
	end)
end
