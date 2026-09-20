--!nonstrict
-- Фиксированный набор полей делает репорт воспроизводимым и не копирует весь
-- профиль: новые служебные поля не попадут в сообщение случайно.
local Report = {}

local function value(v)
	if v == nil then return "?" end
	if type(v) == "number" then return string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "") end
	return tostring(v):gsub("[\r\n]", " ")
end

function Report.build(s)
	local lines = {"Infinite Chocolatier · report 1"}
	local function field(name, v) table.insert(lines, name .. ": " .. value(v)) end
	field("Version", s.version)
	field("Studio", s.studio == true)
	field("Server", s.server)
	field("Captured UTC", s.utc)
	field("Screen", s.screen)
	field("Input", s.input)
	field("Locale", s.locale)
	field("Mode", s.mode)
	field("Phase", s.phase)
	field("Cut", s.cut)
	field("Cut progress", s.progress)
	field("State age (s)", s.stateAge)
	local state = s.state or {}
	field("Ready", state.ready == true)
	field("Save", state.saveStatus)
	field("Pieces", state.slices)
	field("Earned", state.earned)
	field("Stars", state.stars)
	field("Prestige bonus", if not s.state then "?" else if state.prestigeDisabled then "OFF" else "ON")
	field("Income/s", state.rate)
	field("Manual reward", state.manual)
	field("Cycle (s)", state.cycleSeconds)
	for _, key in {"kitchen", "craft", "speed", "recipe", "cafes", "workers"} do
		field("Level " .. key, (state.levels or {})[key])
	end
	field("First apprentice", (state.owned or {}).workers_1 == true)
	field("Friend list", s.friends)
	field("Client friend rigs loaded/assigned", s.appearances)
	for index, message in s.errors or {} do
		if index > 3 then break end
		-- Ограничение сохраняет читаемость при повторяющейся ошибке движка.
		field("Client error " .. index, string.sub(message, 1, 900))
	end
	return table.concat(lines, "\n")
end

return Report
