--!nonstrict
-- Проверяем сделки и перенос профиля, а не только подписи нового магазина.
local E=require('../src/shared/Economy')
local C=require('../src/shared/KitchenCatalog')
local Config=require('../src/shared/Config')
local L=require('../src/shared/LocalizationCatalog')
return function(h)
 h.test('кухня оплачивается один раз, бесплатный найм нельзя получить до оплаты',function()
  local d=E.load({slices=25})
  h.equals(E.buy(d,'workers_1'),false); h.equals(E.buy(d,'clock_1'),false)
  assert(E.buy(d,'kitchen')); h.equals(d.slices,0); h.equals(d.levels.workers,0)
  h.equals(E.buy(d,'kitchen'),false)
  d=E.load(d); assert(E.buy(d,'workers_1')); h.equals(d.levels.workers,1)
  assert(E.buy(d,'workers_1')); assert(E.buy(d,'workers_1'))
  h.equals(d.levels.workers,1); h.equals(d.slices,0)
 end)
 h.test('стажёра можно сменить, но нельзя скрыть повторным выбором',function()
  local d=E.load({slices=10000,levels={kitchen=1}})
  assert(E.buy(d,'workers_1')); assert(E.buy(d,'workers_2'))
  local rate=E.rate(d); local balance=d.slices
  for _,id in {'workers_2','workers_1','workers_1'} do
   assert(E.buy(d,id)); h.equals(d.equipped.workers,id)
   h.equals(E.load(d).equipped.workers,id)
   h.equals(d.levels.workers,2); h.near(E.rate(d),rate); h.equals(d.slices,balance)
  end
 end)
 h.test('ранее скрытый стажёр восстанавливается без бесплатных покупок',function()
  local d=E.load({slices=10000,levels={kitchen=1}})
  assert(E.buy(d,'workers_3'))
  local rate=E.rate(d); local balance=d.slices
  d.equipped.workers=nil
  local loaded=E.load(d)
  h.equals(loaded.equipped.workers,'workers_3'); h.equals(loaded.owned.workers_1,false)
  h.equals(loaded.levels.workers,1); h.near(E.rate(loaded),rate); h.equals(loaded.slices,balance)
  h.equals(E.load({}).equipped.workers,nil)
 end)
 h.test('предметы независимы: дорогие часы можно купить первыми, выбор не меняет бонус',function()
  local d=E.load({slices=10000,levels={kitchen=1,workers=1}})
  assert(E.buy(d,'clock_5')); h.equals(d.levels.clock,1)
  h.equals(d.owned.clock_1,false); h.equals(d.equipped.clock,'clock_5')
  assert(E.buy(d,'clock_2')); h.equals(d.levels.clock,2)
  local rate=E.rate(d); local balance=d.slices
  assert(E.buy(d,'clock_5')); h.equals(d.equipped.clock,'clock_5')
  assert(E.buy(d,'clock_5')); h.equals(d.equipped.clock,nil)
  h.near(E.rate(d),rate); h.near(d.slices,balance)
 end)
 h.test('старые пять уровней дают пять предметов, лишние ученики и скрытый декор сохраняются',function()
  local d=E.load({slices=123,levels={workers=73,clock=5,temper=3,plant=1},decor={plant=false}})
  h.equals(d.levels.kitchen,1); h.equals(d.levels.workers,73); h.equals(d.legacyWorkers,68)
  for i=1,5 do assert(d.owned['clock_'..i]) end
  h.equals(d.equipped.clock,'clock_5'); h.equals(d.equipped.temper,'temper_3')
  h.equals(d.equipped.plant,nil); h.equals(d.owned.plant,true)
  local loaded=E.load(d); h.equals(loaded.levels.workers,73); h.near(E.rate(loaded),E.rate(d))
 end)
 h.test('сохранение коллекции не превращает количество покупок в последовательные уровни',function()
  local d=E.load({slices=10000,levels={kitchen=1}})
  assert(E.buy(d,'temper_5')); assert(E.buy(d,'temper_2'))
  local loaded=E.load(d)
  h.equals(loaded.owned.temper_1,false); h.equals(loaded.owned.temper_2,true)
  h.equals(loaded.owned.temper_5,true); h.equals(loaded.equipped.temper,'temper_2')
  local snapshot=E.snapshot(d); snapshot.owned.temper_5=false; snapshot.equipped.temper=nil
  assert(d.owned.temper_5); h.equals(d.equipped.temper,'temper_2')
 end)
 h.test('старые идентификаторы уровней нельзя купить в обход конечного каталога',function()
  local d=E.load({slices=1e12,levels={kitchen=1}})
  for _,id in {'workers','temper','library','clock','clock_6','workers_6'} do h.equals(E.buy(d,id),false) end
  h.equals(d.slices,1e12)
 end)
 h.test('повторяемые навыки продолжаются после старых предельных уровней',function()
  local d=E.load({slices=Config.Economy.maxValue,levels={craft=50,speed=50,recipe=40,workers=1}})
  for _,id in {'craft','speed','recipe'} do
   d.slices=Config.Economy.maxValue
   local before=d.levels[id]; assert(E.buy(d,id)); h.equals(d.levels[id],before+1)
  end
 end)
 h.test('престиж сбрасывает всю коллекцию и старых стажёров, новый найм снова требует оплаты',function()
  local d=E.load({slices=1e6,earned=5000,productionRemainder=.8,levels={workers=73,clock=5,craft=4}})
  for _,item in C.items do if not d.owned[item.id] then assert(E.buy(d,item.id)) end end
  assert(E.prestige(d)); d=E.load(d)
  for _,spec in Config.Economy.upgrades do h.equals(d.levels[spec.id],0) end
  for _,item in C.items do h.equals(d.owned[item.id],false) end
  h.equals(next(d.equipped),nil); h.equals(d.legacyWorkers,0)
  h.equals(d.productionRemainder,0); h.equals(E.rate(d),0)
  h.equals(E.tick(d,14400),0); h.equals(E.buy(d,'workers_1'),false)
  h.equals(E.price(d,'kitchen'),25)
  E.credit(d,25); assert(E.buy(d,'kitchen')); assert(E.buy(d,'workers_1'))
  h.equals(d.slices,0); h.equals(d.levels.workers,1)
 end)
 h.test('названия и эффекты всех предметов имеют русский перевод',function()
  for _,item in C.items do assert(L.entries[item.name],item.name); assert(L.entries[item.description],item.description) end
 end)
end
