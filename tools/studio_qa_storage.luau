-- Проверяем настоящий серверный модуль на локальном хранилище в памяти.
-- Потеря ответа моделируется после записи, реальные DataStore не вызываются.
assert(game:GetService('RunService'):IsStudio() and game.PlaceId==0,'Local Studio only')
local Store=require(game.ServerScriptService.InfiniteChocolateServer.ProfileStore)
local Economy=require(game.ReplicatedStorage.Shared.Economy)
local Config=require(game.ReplicatedStorage.Shared.Config)
local record={savedAt=900,data={collectionVersion=2,owned={workers_1=true},levels={kitchen=1}}}
local calls=0; local now=1000
local memory={UpdateAsync=function(_,_,transform)
 calls+=1
 record=transform(record)
 if calls==1 then error('Simulated lost response after committed claim') end
 return record
end}
local store=Store.new(memory,Economy,Config.Economy,'local-claim-qa',function() return now end)
assert(not pcall(function() store:claim('qa') end),'First response was not interrupted')
now+=20
local data,amount,report=store:claim('qa')
assert(data.slices==12 and amount==10 and report.seconds==100,'Offline receipt was lost or paid twice')
local repeated,extra,nextReport=store:claim('qa')
assert(repeated.slices==12 and extra==0 and nextReport.seconds==0,'Successful claim retained a stale receipt')
assert(next(store.pendingClaims)==nil,'Settled receipt was retained')
return {ok=true,balance=data.slices,offline=amount,offlineSeconds=report.seconds,repeatedOffline=extra,storage='in-memory'}
