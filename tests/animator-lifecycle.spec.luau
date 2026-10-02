--!nonstrict
-- Управляем очередью задач и ответами загрузчика, чтобы поздний результат
-- не мог заменить нового друга или воскресить удалённую станцию.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local function fixture(options)
 options=options or {}
 local deferred,delayed,pending,calls={},{},{},{}
 local function resume(thread)
  local ok,err=coroutine.resume(thread); assert(ok,err)
 end
 local function rig()
  local root={Transparency=1,Size=R.Vector3.new(2,2,1),IsA=function(_,kind) return kind=='BasePart' end}
  local body={Transparency=.25,IsA=function(_,kind) return kind=='BasePart' end}
  local face={Transparency=.3,IsA=function(_,kind) return kind=='Decal' end}
  local humanoid={RigType=options.rigType or R.Enum.HumanoidRigType.R6,HipHeight=2,FindFirstChildOfClass=function() return nil end}
  local parts={HumanoidRootPart=root,['Left Leg']={Size=R.Vector3.new(1,2,1)}}
  for _,side in {'Left','Right'} do
   parts[side..'UpperArm']={}; parts[side..'Hand']={FindFirstChild=function() return nil end}
  end
  local model={attributes={},root=root,body=body,face=face}
  function model:Destroy() self.destroyed=true; self.Parent=nil end
  function model:ScaleTo(scale) self.scale=scale end
  function model:SetAttribute(key,value) self.attributes[key]=value end
  function model:FindFirstChild(name) return parts[name] end
  function model:FindFirstChildOfClass() return humanoid end
  function model:GetDescendants() return {root,body,face} end
  function model:PivotTo(cf) self.pivot=cf end
  function model:GetExtentsSize() return R.Vector3.new(2,6,2) end
  return model
 end
 local function createRig(_,_,id,kind)
  local model=rig(); table.insert(calls,{id=id,rig=model,kind=kind})
  local index=#calls
  if options.block then table.insert(pending,coroutine.running()); coroutine.yield() end
  if options.failed and options.failed[index] then return false,'temporary rig failure',false end
  return true,model,if options.loaded then options.loaded[index] else id>0,'temporary test failure'
 end
 local Appearance={createRig=createRig,createPlayerRig=createRig,getPlayer=function() return options.player end}
 local Actor=luau.load(fs.readFile('src/client/ChocolatierAnimator.luau'),{environment={
  game={GetService=function() return {} end},script={Parent={FriendAppearance='appearance'}},require=function() return Appearance end,
  Instance={new=function() return {Destroy=function(self) self.destroyed=true end} end},
  Color3=R.Color3,Vector3=R.Vector3,CFrame=R.CFrame,Enum=R.Enum,
  Random={new=function() return {NextInteger=function() return 1 end,NextNumber=function() return .5 end} end},
  task={spawn=function(fn) resume(coroutine.create(fn)) end,defer=function(fn) table.insert(deferred,fn) end,
   delay=function(seconds,fn) table.insert(delayed,{seconds=seconds,fn=fn}) end},warn=function() end,
 },injectGlobals=true})()
 local parent={Parent=true,attributes={}}
 function parent:SetAttribute(name,value) self.attributes[name]=value end
 return {calls=calls,delayed=delayed,parent=parent,
  create=function() return Actor.new(parent,if options.isPlayer then 'Player' else 'Apprentice',3.7,options.isPlayer or false,R.Vector3.zero,options.isPlayer and 1001 or nil) end,
  flush=function() while #deferred>0 do resume(coroutine.create(table.remove(deferred,1))) end end,
  finish=function(index) resume(table.remove(pending,index or 1)) end,
  retry=function() table.remove(delayed,1).fn() end,
 }
end
return function(h)
 h.test('R15 за столом сохраняет масштаб и высоту, обе руки следуют действию',function()
  local f=fixture({isPlayer=true,rigType=R.Enum.HumanoidRigType.R15})
  local actor=f.create(); actor:setVisible(true); f.flush()
  h.equals(f.calls[1].kind,R.Enum.HumanoidRigType.R15); h.equals(actor.rig.scale,1)
  h.near(actor.rig.pivot.Position.Y,3)
  local grip=R.Vector3.new(1,2,3)
  local action={cutting=true,whole=true,leftHand=R.Vector2.new(2,1),rightHand=R.Vector2.zero}
  for _=1,60 do actor:step(action,R.Vector3.zero,R.Vector2.one,.016,grip) end
  assert(actor.ik.Right.control.Weight>.99 and actor.ik.Right.control.Weight<=1)
  h.equals(actor.ik.Right.control.Enabled,true); h.equals(actor.ik.Right.target.WorldPosition,grip)
  h.equals(actor.ik.Left.target.WorldPosition,R.Vector3.new(2,.2,1))
  action.cutting=false
  for _=1,60 do actor:step(action,R.Vector3.zero,R.Vector2.one,.016) end
  h.equals(actor.ik.Right.control.Enabled,false)
  actor:setVisible(false); h.equals(actor.ik.Left.control.Enabled,false)
  actor:destroy(); h.equals(actor.ik,nil)
 end)
 h.test('возрождение и загрузка одежды обновляют копию, поздние события и cleanup безопасны',function()
  local function signal()
   local connections={}
   return {Connect=function(_,fn)
    local c={active=true,callback=fn,Disconnect=function(self) self.active=false end}; table.insert(connections,c); return c
   end,Fire=function(_,char) for _,c in table.clone(connections) do if c.active then c.callback(char) end end end,
   count=function() local n=0; for _,c in connections do if c.active then n+=1 end end; return n end}
  end
  local original={}; local revision=signal(); local player={Character=original,CharacterAdded=signal(),GetAttributeChangedSignal=function(_,name) h.equals(name,'AvatarRevision'); return revision end}
  local f=fixture({isPlayer=true,player=player}); local actor=f.create(); f.flush()
  local first=actor.rig; h.equals(player.CharacterAdded:count(),1)
  player.Character={}; player.CharacterAdded:Fire(player.Character); f.flush()
  assert(first.destroyed and actor.rig~=first); local second=actor.rig
  player.CharacterAdded:Fire(original); f.flush(); h.equals(actor.rig,second)
  revision:Fire(); f.flush(); assert(second.destroyed)
  h.equals(#f.calls,3); h.equals(revision:count(),1)
  actor:destroy(); h.equals(player.CharacterAdded:count(),0); h.equals(revision:count(),0)
  player.CharacterAdded:Fire(player.Character); f.flush(); h.equals(#f.calls,3)
 end)
 h.test('назначение друга в том же кадре не создаёт лишнего запасного персонажа',function()
  local f=fixture(); local actor=f.create()
  actor:setIdentity(1001,7); actor:setIdentity(1002,8); actor:setVisible(true)
  h.equals(f.parent.attributes.ActorLoadState,'loading')
  f.flush()
  h.equals(#f.calls,1); h.equals(f.calls[1].id,1002)
  h.equals(actor.rig.attributes.AssignedUserId,1002)
  h.equals(actor.rig.body.Transparency,.25); h.equals(actor.rig.face.Transparency,.3)
  h.equals(actor.rig.root.Transparency,1); h.equals(actor.rig.scale,.8)
  h.equals(f.parent.attributes.ActorLoadState,'ready')
  h.equals(f.parent.attributes.ActorAssignedUserId,1002)
  h.equals(f.parent.attributes.ActorAppearanceUserId,1002)
  h.equals(f.parent.attributes.ActorVisible,true)
 end)
 h.test('удаление станции до запуска загрузки не обращается к внешности',function()
  local f=fixture(); local actor=f.create(); actor:setIdentity(1001,7)
  actor:destroy(); f.flush(); h.equals(#f.calls,0)
  h.equals(f.parent.attributes.ActorLoadState,nil); h.equals(f.parent.attributes.ActorVisible,false)
  actor:setIdentity(1002,8); f.flush(); h.equals(#f.calls,0)
 end)
 h.test('поздние загрузки старого друга и удалённой станции уничтожаются',function()
  local f=fixture({block=true}); local actor=f.create(); actor:setIdentity(1001,7); f.flush()
  actor:setIdentity(1002,8); f.flush()
  f.finish(2); h.equals(actor.rig.attributes.AssignedUserId,1002)
  local current=actor.rig
  f.finish(1); h.equals(actor.rig,current); h.equals(f.calls[1].rig.destroyed,true)
  h.equals(f.parent.attributes.ActorAssignedUserId,1002); h.equals(f.parent.attributes.ActorLoadState,'ready')
  actor:setIdentity(1003,9); f.flush(); actor:destroy(); f.finish()
  h.equals(f.calls[3].rig.destroyed,true); h.equals(actor.rig,nil)
 end)
 h.test('повтор загрузки держит запасной rig до готовности друга и отменяется при смене',function()
  local f=fixture({loaded={false,true,false,true}})
  local actor=f.create(); actor:setIdentity(1001,7); actor:setVisible(true); f.flush()
  local fallback=actor.rig
  h.equals(fallback.attributes.AppearanceUserId,0); h.equals(f.delayed[1].seconds,5)
  f.retry(); h.equals(actor.rig,fallback,'не прятать повара на время повторной загрузки')
  f.flush(); assert(actor.rig~=fallback); h.equals(fallback.destroyed,true)
  h.equals(actor.rig.attributes.AppearanceUserId,1001)
  actor:setIdentity(1002,8); f.flush(); h.equals(#f.delayed,1)
  actor:setIdentity(1003,9); f.flush(); local count=#f.calls
  f.retry(); f.flush(); h.equals(#f.calls,count)
  h.equals(actor.rig.attributes.AssignedUserId,1003)
 end)
 h.test('случайный стажёр восстанавливается после ошибки создания модели',function()
  local f=fixture({failed={true}}); local actor=f.create(); actor:setVisible(true); f.flush()
  h.equals(actor.rig,nil); h.equals(#f.delayed,1)
  h.equals(f.parent.attributes.ActorAssignedUserId,0)
  h.equals(f.parent.attributes.ActorLoadState,'retrying'); h.equals(f.parent.attributes.ActorVisible,true)
  h.equals(f.delayed[1].seconds,5)
  f.retry(); f.flush()
  h.equals(#f.calls,2); h.equals(actor.rig.attributes.AssignedUserId,0)
  h.equals(actor.rig.attributes.AppearanceUserId,0); h.equals(actor.rig.body.Transparency,.25)
  h.equals(#f.delayed,0,'успешный случайный персонаж не требует поиска друга')
  h.equals(f.parent.attributes.ActorLoadState,'ready')
 end)
 h.test('недоступный загрузчик случайных стажёров повторяется с паузами и конечным числом попыток',function()
  local f=fixture({failed={true,true,true,true}}); local actor=f.create(); f.flush()
  for _,seconds in {5,20,60} do
   h.equals(#f.delayed,1); h.equals(f.delayed[1].seconds,seconds)
   f.retry(); f.flush()
  end
  h.equals(#f.calls,4); h.equals(#f.delayed,0); h.equals(actor.rig,nil)
  h.equals(f.parent.attributes.ActorLoadState,'failed')
  actor:setIdentity(1001,7); f.flush()
  h.equals(actor.rig.attributes.AssignedUserId,1001,'новое назначение начинает собственную загрузку')
 end)
 h.test('повтор отсутствующего случайного персонажа отменяется при назначении друга или удалении станции',function()
  local f=fixture({failed={true}}); local actor=f.create(); f.flush()
  h.equals(#f.delayed,1)
  actor:setIdentity(1001,7); f.flush(); local current=actor.rig
  f.retry(); f.flush()
  h.equals(#f.calls,2); h.equals(actor.rig,current)
  local removed=fixture({failed={true}}); local gone=removed.create(); removed.flush()
  h.equals(#removed.delayed,1); gone:destroy(); removed.retry(); removed.flush()
  h.equals(#removed.calls,1); h.equals(gone.rig,nil)
  h.equals(removed.parent.attributes.ActorLoadState,nil)
 end)
 h.test('исчерпанная загрузка друга отличается в отчёте от обычного случайного стажёра',function()
  local f=fixture({loaded={false,false,false,false}}); local actor=f.create()
  actor:setIdentity(1001,7); actor:setVisible(true); f.flush()
  for _=1,3 do f.retry(); f.flush() end
  h.equals(f.parent.attributes.ActorLoadState,'fallback')
  h.equals(f.parent.attributes.ActorAssignedUserId,1001)
  h.equals(f.parent.attributes.ActorAppearanceUserId,0)
  h.equals(actor.rig.attributes.AssignedUserId,1001); h.equals(#f.delayed,0)
  actor:setVisible(false); h.equals(f.parent.attributes.ActorVisible,false)
 end)
end
