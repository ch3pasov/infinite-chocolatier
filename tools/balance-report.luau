--!nonstrict
-- Запуск до коммита, без Studio, аккаунта Roblox и сетевых запросов.
local process=require('@lune/process'); local fs=require('@lune/fs'); local serde=require('@lune/serde')
local Simulator=require('./balance/Simulator')
local minutes,roundSeconds,output=60,8,nil
local args=process.args; local i=1
while i<=#args do
 local key,value=args[i],args[i+1]
 if key=='--help' then
  print('lune run tools/balance-report [--minutes 60] [--round-seconds 8] [--output /tmp/balance.json]'); process.exit(0)
 end
 assert(value,'нет значения после '..key)
 if key=='--minutes' then minutes=assert(tonumber(value),'неверное число минут')
 elseif key=='--round-seconds' then roundSeconds=assert(tonumber(value),'неверный интервал фокусов')
 elseif key=='--output' then output=value
 else error('неизвестный аргумент: '..key) end
 i+=2
end
local descriptions={
 none='Без покупок',cafe='Копить на кафе',invest='Вкладывать в доход',idle='После найма — простой',
}
local report={formatVersion=1,assumptions={roundSeconds=roundSeconds,seconds=minutes*60,stars=0,
 automaticPrestige=false,travelAndReadingSeconds=0,purchaseCooldownSeconds=.2},scenarios={}}
local function stamp(seconds)
 return if seconds~=nil then string.format('%d:%02d',math.floor(seconds/60),math.floor(seconds%60)) else 'не достигнуто'
end
print(string.format('Первый заход без звёзд · %.2f с/ручной фокус · %.0f мин',roundSeconds,minutes))
print('Меню и прогулка мгновенные; престиж только отмечается, не выполняется. Стратегии не оптимальны.')
for _,strategy in {'none','cafe','invest','idle'} do
 local result=Simulator.run({strategy=strategy,seconds=minutes*60,roundSeconds=roundSeconds})
 table.insert(report.scenarios,result)
 local m=result.milestones
 print(string.format('%s: стажёр %s · кафе %s · престиж %s · %d покупок',descriptions[strategy],stamp(m.apprentice),stamp(m.cafe),stamp(m.prestige),#result.purchases))
end
if output then fs.writeFile(output,serde.encode('json',report,true)); print('Отчёт: '..output) end
