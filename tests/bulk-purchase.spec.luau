--!nonstrict
-- Пакет обязан стоить ровно столько же, сколько одиночные покупки,
-- и не покупать частичный набор при нехватке денег.
local E=require("../src/shared/Economy")
local Config=require("../src/shared/Config")
return function(h)
 h.test("пакеты десяти уровней совпадают с последовательными покупками всех бесконечных улучшений",function()
  for _,id in {"craft","speed","recipe","cafes"} do
   for _,level in {0,1,7,20} do
    local seed={slices=Config.Economy.maxValue,collectionVersion=2,owned={workers_1=true},levels={kitchen=1,[id]=level}}
    local bulk=E.load(seed); local single=E.load(seed)
    local price,count=E.quote(bulk,id,10); h.equals(count,10)
    local sum=0
    for _=1,10 do sum+=E.price(single,id); assert(E.buy(single,id)) end
    h.equals(price,sum); assert(E.buy(bulk,id,10))
    h.equals(bulk.slices,single.slices); h.equals(bulk.levels[id],single.levels[id])
    h.equals(bulk.levels.workers,single.levels.workers)
   end
  end
 end)
 h.test("дорогой пакет отклоняется целиком, MAX берёт только доступные уровни",function()
  local d=E.load({slices=100})
  local price=E.quote(d,"craft",10); assert(price>100)
  h.equals(E.buy(d,"craft",10),false); h.equals(d.slices,100); h.equals(d.levels.craft,0)
  local single=E.load(d); local count=0
  while E.buy(single,"craft") do count+=1 end
  local total,quoted=E.quote(d,"craft","max"); h.equals(quoted,count)
  assert(E.buy(d,"craft","max")); h.equals(d.slices,100-total)
  h.equals(d.slices,single.slices); h.equals(d.levels.craft,count)
  local _,none=E.quote(d,"craft","max"); h.equals(none,0)
  h.equals(E.buy(d,"craft","max"),false)
 end)
 h.test("MAX ограничен даже на предельном балансе, десять предельных цен не сжимаются в одну",function()
  for _,id in {"craft","speed","recipe","cafes"} do
   local d=E.load({slices=Config.Economy.maxValue,collectionVersion=2,owned={workers_1=true},levels={kitchen=1}})
   local _,count=E.quote(d,id,"max"); assert(count>0 and count<100)
   assert(E.buy(d,id,"max")); assert(d.slices<E.price(d,id))
   d.levels[id]=200; d.slices=Config.Economy.maxValue
   h.equals(E.quote(d,id,10),Config.Economy.maxValue*10)
   h.equals(E.buy(d,id,10),false); assert(E.buy(d,id,"max"))
   h.equals(d.levels[id],201); h.equals(d.slices,0)
  end
 end)
 h.test("конечные предметы, закрытые кафе и недопустимые количества не покупаются пакетами",function()
  local d=E.load({slices=100000})
  for _,id in {"kitchen","workers_1","clock_1","cafes","speed","missing"} do h.equals(E.buy(d,id,10),false) end
  for _,quantity in {0,-1,3,1000,math.huge,0/0,"10",{},true} do h.equals(E.buy(d,"craft",quantity),false) end
  h.equals(d.slices,100000); h.equals(d.levels.craft,0)
  assert(E.buy(d,"kitchen")); assert(E.buy(d,"workers_1")); assert(E.buy(d,"clock_1"))
  local equipped=d.equipped.clock
  h.equals(E.buy(d,"clock_1",10),false); h.equals(d.equipped.clock,equipped)
 end)
end
