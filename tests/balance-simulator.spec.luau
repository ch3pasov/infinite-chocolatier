--!nonstrict
local Sim=require('../tools/balance/Simulator')
local E=require('../src/shared/Economy')
return function(h)
 h.test('симулятор первого захода считает настоящие ручные фокусы и заказы',function()
  local result=Sim.run({strategy='none',seconds=32,roundSeconds=8})
  h.equals(result.manualRounds,4); h.equals(result.final.slices,5)
  h.equals(result.final.ordersCompleted,1); h.equals(result.final.stars,0)
  h.equals(#result.purchases,0); h.equals(next(result.milestones),nil)
 end)
 h.test('симулятор оплачивает уровни по отдельности и выдерживает паузу покупок',function()
  local result=Sim.run({seconds=1,initial={slices=100},choose=function(data)
   return if data.levels.craft<3 then 'craft' else nil
  end})
  h.equals(#result.purchases,3)
  h.near(result.purchases[1].seconds,0); h.near(result.purchases[2].seconds,.2); h.near(result.purchases[3].seconds,.4)
  h.equals(result.purchases[1].price,3); h.equals(result.purchases[2].price,5); h.equals(result.purchases[3].price,8)
  h.equals(result.final.slices,84); h.equals(result.final.manual,4)
 end)
 h.test('симулятор отделяет оплату книги от бесплатного найма и не режет после перехода в простой',function()
  local result=Sim.run({strategy='idle',seconds=10,initial={collectionVersion=2,slices=0,levels={kitchen=1}}})
  h.equals(result.purchases[1].id,'workers_1'); h.equals(result.purchases[1].price,0)
  h.equals(result.milestones.apprentice,0); h.equals(result.manualRounds,0)
  h.equals(result.final.slices,1); h.equals(result.final.rate,.1)
  local cafe=Sim.run({strategy='cafe',seconds=1,initial={slices=25}})
  h.equals(cafe.purchases[1].id,'kitchen'); h.equals(cafe.purchases[1].price,25)
  h.equals(cafe.purchases[2].id,'workers_1'); h.near(cafe.purchases[2].seconds,.2)
 end)
 h.test('эвристика симулятора не меняет профиль и использует только доступные покупки',function()
  local data=E.load(nil); local chosen=Sim.choose(data,'invest',8,true)
  h.equals(chosen,'craft'); h.equals(data.slices,0); h.equals(data.levels.craft,0)
  local a=Sim.run({seconds=300,strategy='invest'})
  local b=Sim.run({seconds=300,strategy='invest'})
  h.equals(a.final.slices,b.final.slices); h.equals(#a.purchases,#b.purchases)
  assert(a.milestones.apprentice,'вложения должны дойти до автоматизации')
  for index,buy in a.purchases do
   h.equals(buy.id,b.purchases[index].id); h.near(buy.seconds,b.purchases[index].seconds)
   if index>1 then assert(buy.seconds-a.purchases[index-1].seconds>=.2-1e-8) end
  end
  for _,bad in {{seconds=0},{seconds=math.huge},{roundSeconds=0},{roundSeconds=0/0}} do
   h.equals(pcall(Sim.run,bad),false)
  end
 end)
end
