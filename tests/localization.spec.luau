--!nonstrict
-- Проверяем настоящую привязку UI: язык меняется без пересоздания раунда,
-- отсутствие облака не оставляет пустой текст и не ломает числа.
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local Catalog=require('../src/shared/LocalizationCatalog')
local Config=require('../src/shared/Config')
local function signal()
	local callbacks={}
	return {Connect=function(_,fn) table.insert(callbacks,fn) end,Fire=function() for _,fn in callbacks do fn() end end}
end
local function fixture(locale,cloud)
	local changed=signal()
	local service={RobloxLocaleId=locale,GetPropertyChangedSignal=function() return changed end,
		GetTranslatorForPlayerAsync=function() if not cloud then error('offline') end; return cloud end}
	local L=luau.load(fs.readFile('src/client/Localization.luau'),{environment={
		game={GetService=function(_,name)
			if name=='LocalizationService' then return service end
			if name=='Players' then return {LocalPlayer={}} end
			return {WaitForChild=function() return {LocalizationCatalog='catalog'} end}
		end},require=function() return Catalog end,task={spawn=function(fn) fn() end},
	},injectGlobals=true})()
	return L,function(nextLocale) service.RobloxLocaleId=nextLocale; changed.Fire() end
end
return function(h)
	h.test('локализация: все русские шаблоны сохраняют параметры английского источника',function()
		for source,translation in Catalog.entries do
			local function tokens(s)
				local t={}; for key in s:gmatch('{([%w_]+)}') do t[key]=true end; return t
			end
			local a,b=tokens(source),tokens(translation)
			for key in a do assert(b[key],source..' lost '..key) end
			for key in b do assert(a[key],source..' added '..key) end
		end
		for _,upgrade in Config.Economy.upgrades do
			assert(Catalog.entries[upgrade.name]); assert(Catalog.entries[upgrade.description])
		end
		for _,label in Config.Trick.cutLabels do assert(Catalog.entries[label]) end
	end)
	h.test('локализация: русский работает без сети, неизвестный язык получает английский',function()
		local L=fixture('ru-ru')
		h.equals(L.text('Buy · {price} pieces',{price=12}),'Купить · 12 долек')
		local fallback=fixture('fr-fr')
		h.equals(fallback.text('Buy · {price} pieces',{price=12}),'Buy · 12 pieces')
	end)
	h.test('локализация: смена языка обновляет статический текст, вложенные слова и крупные числа',function()
		local L,switch=fixture('en-us')
		local label={Parent=true}
		L.set(label,'{upgrade} · {level}',{upgrade=L.token('Craftsmanship'),level=L.number(1200)})
		h.equals(label.Text,'Craftsmanship · 1.2K')
		switch('ru-ru')
		h.equals(label.Text,'Мастерство · 1.2 тыс.')
		h.equals(label.AutoLocalize,false)
		switch('en-us'); h.equals(label.Text,'Craftsmanship · 1.2K')
	end)
	h.test('локализация: облачный перевод получает параметры и реагирует на смену языка Roblox',function()
		local changed=signal()
		local cloud={LocaleId='fr-fr',GetPropertyChangedSignal=function() return changed end,
			FormatByKey=function(_,key,args)
				assert(key=='Buy · {price} pieces'); return 'Acheter · '..args.price..' morceaux'
			end}
		local L=fixture('en-us',cloud)
		local label={Parent=true}; L.set(label,'Buy · {price} pieces',{price=17})
		h.equals(label.Text,'Acheter · 17 morceaux'); h.equals(label.AutoLocalize,false)
		cloud.LocaleId='ru-ru'; changed.Fire()
		h.equals(label.Text,'Купить · 17 долек')
	end)
	h.test('локализация: начисления и сообщения безопасности имеют ручной русский перевод',function()
		local L=fixture('ru')
		h.equals(L.text('Trick complete! +{amount}',{amount=8.75}),'Фокус удался! +8.75 долек')
		assert(Catalog.format('Could not renew your save session. Rejoin to continue safely.',nil,'ru'):find('Перезайди'))
	end)
end
