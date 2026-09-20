-- Только локальный QA: настоящий Relay и RemoteEvent, условный автор
-- на удалённом острове. Это не заменяет сеанс двух настоящих игроков.
assert(game:GetService('RunService'):IsStudio() and game.PlaceId==0)
local players=game:GetService('Players')
local observer=assert(players:GetPlayers()[1])
local deadline=os.clock()+4
while observer:GetAttribute('KitchenMode')~='walk' and os.clock()<deadline do task.wait(.1) end
assert(observer:GetAttribute('KitchenMode')=='walk','Observer did not enter the kitchen')
local Shared=game.ReplicatedStorage.Shared
local Queue=require(Shared.CafeQueue)
local Wire=require(Shared.WorkstationWire)
local Config=require(Shared.Config)
local Relay=require(game.ServerScriptService.InfiniteChocolateServer.KitchenRelay)
local remote=game.ReplicatedStorage.InfiniteChocolateRemotes.KitchenAction
local author={UserId=2147483000,Parent=true}
local origin=observer:GetAttribute('KitchenOrigin')+Vector3.new(256,0,0)
function author:GetAttribute(name) return if name=='KitchenOrigin' then origin else 'cut' end
local root=assert(observer.Character and observer.Character:FindFirstChild('HumanoidRootPart'))
assert((root.Position-origin).Magnitude>80,'Probe author must be physically distant')
local receive
local emitted=0
local transport={OnServerEvent={Connect=function(_,fn) receive=fn end},FireClient=function(_,p,id,action)
 assert(p==observer and id==author.UserId,'Unexpected packet recipient')
 emitted+=1; remote:FireClient(p,id,action)
end}
local audience={PlayerRemoving={Connect=function() end},GetPlayers=function() return {observer,author} end}
local segments=Queue.build({{owner=observer.UserId,index=0,online=true,count=12},{owner=author.UserId,index=0,online=true,count=0}})
Relay.start(audience,transport,Wire,os.clock,function(p)
 return Queue.animatedPlayers(segments,p.UserId,0,p.UserId)
end)
local action={whole=true,cutting=true,knifePoint=Vector2.new(1.25,2.5),knifeDirection=Vector2.new(1,-.4),offsets={},hidden={}}
for _,name in Config.Trick.pieceOrder do action.offsets[name]=Vector2.zero end
receive(author,action)
assert(emitted==1,'Visible distant author was not relayed')
return {ok=true,packets=emitted,author=author.UserId,physicalDistance=(root.Position-origin).Magnitude}
