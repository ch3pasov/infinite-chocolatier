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
	-- Русский не отдаём повторно машинному переводчику. Английские исходники
	-- остаются доступны автоматическому сбору текста Roblox.
	local result,translated=L.text(binding.source,binding.args)
	label.AutoLocalize=not translated
	label.Text=result
end

function L.set(label,source,args)
	local binding=bindings[label]
	if not binding then
		binding={}; bindings[label]=binding
		label.Destroying:Connect(function() bindings[label]=nil end)
	end
	binding.source=source; binding.args=args
	render(label,binding)
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
