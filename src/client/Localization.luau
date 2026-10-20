--!nonstrict
-- Ручной русский перевод доступен сразу и без сети. Для остальных языков
-- используем облачную таблицу Roblox; сбой перевода не блокирует игру.
local Service=game:GetService("LocalizationService")
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog=require(Shared.LocalizationCatalog)
local L={}
local locale=Service.RobloxLocaleId or "en-us"
local translator=nil
-- Подпись живёт до Destroy(), даже если на неё нет других Lua-ссылок.
-- Слабая таблица теряла статические заголовки раньше смены языка.
local bindings={}

function L.token(source) return {source=source} end
function L.number(value) return {number=value} end

local function number(value)
	-- Быстрый производственный цикл остаётся положительным во всех окнах,
	-- включая каталог и наблюдение, а не только страницу расчётов.
	if value~=0 and math.abs(value)<.01 then return string.format('%.3g',value) end
	for _,unit in {{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}} do
		if value>=unit[1] then return string.format("%.1f",value/unit[1])..Catalog.format(unit[2],nil,locale) end
	end
	return (string.format("%.2f",value):gsub("0+$",""):gsub("%.$",""))
end

function L.text(source,args)
	local values={}
	for key,value in args or {} do
		values[key]=if type(value)=="table" then (if value.source then L.text(value.source) else number(value.number))
			elseif type(value)=="number" then number(value) else value
	end
	if string.sub(string.lower(locale),1,2)~="ru" and translator then
		local ok,result=pcall(function() return translator:FormatByKey(source,values) end)
		if ok and result~="" then return result, string.sub(string.lower(locale),1,2)~="en" end
	end
	return Catalog.format(source,values,locale), string.sub(string.lower(locale),1,2)=="ru"
end

local function render(label,binding)
	if binding.prompt then
		-- Встроенная подсказка не должна повторно переводить готовый текст
		-- и имена игроков. Обе строки обновляются вместе с языком интерфейса.
		if label.AutoLocalize~=false then label.AutoLocalize=false end
		local action=L.text(binding.source,binding.args)
		if label.ActionText~=action then label.ActionText=action end
		if binding.objectSource then
			local object=L.text(binding.objectSource,binding.args)
			if label.ObjectText~=object then label.ObjectText=object end
		end
		return
	end
	-- Русский не отдаём повторно машинному переводчику. Английские исходники
	-- остаются доступны автоматическому сбору текста Roblox.
	local result,translated=L.text(binding.source,binding.args)
	label.AutoLocalize=not translated
	label.Text=result
end

local function sameArgs(a,b)
	for key,value in a or {} do
		local other=b and b[key]
		if type(value)=="table" then
			if type(other)~="table" or value.source~=other.source or value.number~=other.number then return false end
		elseif value~=other then return false end
	end
	for key in b or {} do if not a or a[key]==nil then return false end end
	return true
end

local function bind(label,source,args,prompt,objectSource)
	local binding=bindings[label]
	if binding and binding.source==source and binding.objectSource==objectSource and sameArgs(binding.args,args) then return end
	if not binding then
		binding={}; bindings[label]=binding
		label.Destroying:Connect(function() bindings[label]=nil end)
	end
	-- Кухня обновляет подписи покадрово. Не вызываем облачный переводчик
	-- повторно для прежнего текста; копия параметров замечает и изменение
	-- ранее переданной таблицы. Смена языка обновляет все привязки в refresh.
	binding.source=source; binding.args=nil; binding.prompt=prompt; binding.objectSource=objectSource
	if args then
		binding.args={}
		for key,value in args do binding.args[key]=if type(value)=="table" then table.clone(value) else value end
	end
	render(label,binding)
end

function L.set(label,source,args) bind(label,source,args) end

-- ObjectText без шаблона остаётся буквальным: это имя игрока или название
-- игры. Привязка живёт до Destroy(), в том числе у серверных стрелок кафе.
function L.prompt(prompt,actionSource,objectSource,args)
	bind(prompt,actionSource,args,true,objectSource)
end

local function refresh()
	locale=if translator then translator.LocaleId else Service.RobloxLocaleId
	for label,binding in bindings do
		render(label,binding)
	end
end

Service:GetPropertyChangedSignal("RobloxLocaleId"):Connect(refresh)
task.spawn(function()
	local ok,result=pcall(function() return Service:GetTranslatorForPlayerAsync(Players.LocalPlayer) end)
	if ok then
		translator=result
		translator:GetPropertyChangedSignal("LocaleId"):Connect(refresh)
		refresh()
	end
end)
return L
