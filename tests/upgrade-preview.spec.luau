--!nonstrict
-- Сравниваем обещание карточки с реальной покупкой, включая пакет и
-- админский режим. Предпросмотр не должен менять деньги или сохранение.
local E=require("../src/shared/Economy")
local Config=require("../src/shared/Config")
local serde=require("@lune/serde")
return function(h)
 h.test("прирост в карточке совпадает с покупкой при множителях и разных количествах",function()
  for _,disabled in {false,true} do
   for _,id in {"craft","speed","recipe","cafes"} do
    for _,quantity in {1,10,"max"} do
     local d=E.load({slices=1e10,stars=12,collectionVersion=2,
      owned={workers_1=true,temper_1=true,clock_2=true,library_3=true},
      levels={kitchen=1,cafes=2,craft=4,recipe=3,speed=2}})
     d.ignorePrestige=disabled
     local state=E.snapshot(d); state.prestigeDisabled=disabled
     local before=serde.encode("json",state)
     local p=assert(E.preview(state,id,quantity))
     h.equals(serde.encode("json",state),before)
     local manual,rate,workers=E.manual(d),E.rate(d),d.levels.workers
     h.near(p.cycleBefore,E.cycleSeconds(d)); assert(E.buy(d,id,quantity))
     h.near(p.manualGain,E.manual(d)-manual)
     h.near(p.rateGain,E.rate(d)-rate)
     h.near(p.cycleAfter,E.cycleSeconds(d)); h.equals(p.workersGain,d.levels.workers-workers)
     h.equals(p.waitSeconds,nil)
    end
   end
  end
 end)
 h.test("ожидание покупки учитывает выплаты целыми циклами и незавершённый цикл",function()
  local d=E.load({slices=.4,productionRemainder=.75,collectionVersion=2,owned={workers_1=true},levels={kitchen=1}})
  local price=E.price(d,"craft"); local missing=price-d.slices
  assert(missing>0)
  local p=E.preview(d,"craft",1); assert(p.waitSeconds>0)
  local almost=E.load(d); E.tick(almost,p.waitSeconds-.001); assert(almost.slices<price)
  local ready=E.load(d); E.tick(ready,p.waitSeconds); assert(ready.slices>=price)
  local zero=E.load({}); h.equals(E.preview(zero,"craft",1).waitSeconds,nil)
  h.equals(E.preview(d,"kitchen",1),nil); h.equals(E.preview(d,"missing",1),nil)
  h.equals(E.preview(d,"craft",-5),nil)
 end)
 h.test("пустой MAX показывает один будущий уровень, но не обещает невозможный пакет",function()
  local d=E.load({slices=0,collectionVersion=2,owned={workers_1=true},levels={kitchen=1}})
  local p=E.preview(d,"craft","max"); h.equals(p.manualGain,1)
  h.equals(d.levels.craft,0); h.equals(d.slices,0)
  d.levels.craft=200; d.slices=Config.Economy.maxValue
  h.equals(E.preview(d,"craft",10).waitSeconds,nil)
 end)
end
