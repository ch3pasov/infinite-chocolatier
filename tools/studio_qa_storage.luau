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
local leaseNow=2000; local leaseRecord; local delay=Config.Economy.leaseSeconds+1; local fail=false
local leaseMemory={UpdateAsync=function(_,_,transform)
 local updated=transform(leaseRecord); if updated then leaseRecord=updated end
 leaseNow+=delay
 if fail then error('Simulated lost renewal reply') end
 return updated
end}
local lease=Store.new(leaseMemory,Economy,Config.Economy,'lease-deadline-qa',function() return leaseNow end)
local profile=lease:claim('lease')
assert(not lease:hasLease('lease',30),'Slow claim reply extended the stored expiry')
delay=0; assert(lease:save('lease',profile,false) and lease:hasLease('lease',30),'Normal save did not renew the lease')
leaseNow+=50; fail=true
assert(not pcall(function() lease:save('lease',profile,false) end),'Renewal reply was not interrupted')
assert(lease:hasLease('lease',30),'Network error erased the previous valid confirmation')
leaseNow+=Config.Economy.leaseSeconds-50
assert(not lease:hasLease('lease',0),'Unconfirmed renewal extended the lease')
fail=false; assert(lease:save('lease',profile,false)); assert(lease:hasLease('lease',30))
assert(lease:save('lease',profile,true)); assert(not lease:hasLease('lease',0),'Released profile remained writable')
return {ok=true,balance=data.slices,offline=amount,offlineSeconds=report.seconds,repeatedOffline=extra,leaseDeadline=true,unconfirmedRenewalRejected=true,storage='in-memory'}
