--!nonstrict
local Report = require("../src/shared/DiagnosticReport")
return function(h)
	h.test("репорт учитывает назначения без модели и отличает их от скрытых станций",function()
		local report=Report.build({actors={
			{assigned=7,appearance=7,status='ready',visible=true},
			{assigned=8,appearance=0,status='loading',visible=true},
			{assigned=9,appearance=0,status='retrying',visible=true},
			{assigned=10,appearance=0,status='fallback',visible=true},
			{assigned=0,appearance=0,status='failed',visible=true},
			{assigned=11,appearance=0,status='failed',visible=false},
		}})
		assert(report:find('Client friend rigs loaded/assigned: 1/5',1,true))
		assert(report:find('Visible actor loads ready/loading/retrying/fallback/failed: 1/1/1/1/1',1,true))
		local empty=Report.build({actors={}})
		assert(empty:find('Client friend rigs loaded/assigned: 0/0',1,true))
		assert(empty:find('Visible actor loads ready/loading/retrying/fallback/failed: 0/0/0/0/0',1,true))
	end)
	h.test("репорт различает старую версию, бонус престижа и ещё не загруженный профиль", function()
		local pending = Report.build({version = 52, studio = false})
		assert(pending:find("Version: 52", 1, true))
		assert(pending:find("Ready: false", 1, true))
		assert(pending:find("Save: ?", 1, true))
		local state = {ready = true, stars = 7600, prestigeDisabled = true, slices = 123.45, levels = {craft = 7, cafes = 3}}
		local report = Report.build({version = 53, state = state, stateAge = 1.25})
		assert(report:find("Prestige bonus: OFF", 1, true))
		assert(report:find("Stars: 7600", 1, true))
		assert(report:find("Level craft: 7", 1, true))
		assert(report:find("Pieces: 123.45", 1, true))
		state.slices = 200
		assert(report:find("Pieces: 123.45", 1, true), "Готовый снимок не меняется с приходом нового состояния")
	end)
	h.test("репорт ограничивает ошибки и не копирует посторонние поля профиля", function()
		local report = Report.build({
			state = {sessionToken = "SECRET", nested = {private = "SECRET"}},
			errors = {string.rep("a", 5000), "line1\nline2", "third", "fourth"},
		})
		assert(not report:find("SECRET", 1, true))
		assert(not report:find("fourth", 1, true))
		assert(not report:find(string.rep("a", 901), 1, true))
		assert(report:find("line1 line2", 1, true))
		assert(#report < 2000)
	end)
end
