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
	h.test('локализация: быстрый цикл не округляется до нуля ни в одном языке',function()
		local L,switch=fixture('en-us')
		local label={Destroying=signal()}
		for _,sample in {{.009,'0.009'},{.00125,'0.00125'},{1e-8,'1e-08'},{0,'0'},{.25,'0.25'}} do
			L.set(label,'Cycle: {seconds}s',{seconds=L.number(sample[1])})
			h.equals(label.Text,'Cycle: '..sample[2]..'s')
		end
		L.set(label,'Each apprentice: +{reward} every {seconds}s',{reward=L.number(12),seconds=L.number(1e-8)})
		switch('ru-ru'); assert(label.Text:find('1e%-08'))
	end)
	h.test('локализация: одинаковые кадры не переводятся повторно, изменения и язык обновляют текст',function()
		local changed=signal(); local calls=0
		local cloud={LocaleId='en-us',GetPropertyChangedSignal=function() return changed end,
			FormatByKey=function(_,key,args) calls+=1; return Catalog.format(key,args,'en-us') end}
		local L=fixture('en-us',cloud); local label={Destroying=signal()}
		local args={price=L.number(17)}
		L.set(label,'Buy · {price} pieces',args)
		for _=1,100 do L.set(label,'Buy · {price} pieces',{price=L.number(17)}) end
		h.equals(calls,1); h.equals(label.Text,'Buy · 17 pieces')
		args.price.number=18; L.set(label,'Buy · {price} pieces',args)
		h.equals(calls,2); h.equals(label.Text,'Buy · 18 pieces')
		cloud.LocaleId='ru-ru'; changed.Fire()
		h.equals(label.Text,'Купить · 18 долек'); h.equals(label.AutoLocalize,false)
		L.set(label,'Buy · {price} pieces',{price=L.number(18)})
		h.equals(calls,2)
		cloud.LocaleId='en-us'; changed.Fire()
		h.equals(calls,3); h.equals(label.Text,'Buy · 18 pieces')
		L.set(label,'{amount}',{amount=L.token('Craftsmanship')})
		h.equals(label.Text,'Craftsmanship'); local before=calls
		L.set(label,'{amount}',{amount=L.token('Craftsmanship')}); h.equals(calls,before)
		L.set(label,'{amount}',{amount=L.token('Recipe')}); h.equals(label.Text,'Recipe')
		L.set(label,'{amount}',{}); h.equals(label.Text,'{amount}')
		L.set(label,'While you were away'); before=calls
		L.set(label,'While you were away',{}); h.equals(calls,before)
		label.Destroying:Fire(); changed.Fire(); h.equals(calls,before)
	end)
	h.test('локализация: всплывающая награда сокращает большие числа и сохраняет малые',function()
		local L,switch=fixture('en-us')
		local label={Destroying=signal()}
		for _,sample in {{.25,'+0.25'},{16.2,'+16.2'},{1200,'+1.2K'},{357800,'+357.8K'},{15000000,'+15.0M'}} do
			L.set(label,'+{amount}',{amount=L.number(sample[1])})
			h.equals(label.Text,sample[2])
		end
		switch('ru-ru'); h.equals(label.Text,'+15.0 млн')
		label.Destroying:Fire(); switch('en-us')
		h.equals(label.Text,'+15.0 млн')
	end)
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
		local label={Parent=true,Destroying=signal()}
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
		local label={Parent=true,Destroying=signal()}; L.set(label,'Buy · {price} pieces',{price=17})
		h.equals(label.Text,'Acheter · 17 morceaux'); h.equals(label.AutoLocalize,false)
		cloud.LocaleId='ru-ru'; changed.Fire()
		h.equals(label.Text,'Купить · 17 долек')
	end)
	h.test('локализация: начисления и сообщения безопасности имеют ручной русский перевод',function()
		local L=fixture('ru')
		h.equals(L.text('Trick complete! +{amount}',{amount=8.75}),'Фокус удался! +8.75 долек')
		assert(Catalog.format('Could not renew your save session. Rejoin to continue safely.',nil,'ru'):find('Перезайди'))
	end)
	h.test('локализация: временно снятая подпись обновляется, уничтоженная освобождается',function()
		local L,switch=fixture('en-us')
		local label={Destroying=signal()}
		L.set(label,'While you were away')
		switch('ru-ru'); h.equals(label.Text,'Пока тебя не было')
		label.Destroying:Fire(); switch('en-us')
		h.equals(label.Text,'Пока тебя не было')
	end)
end
