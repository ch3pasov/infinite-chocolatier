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
  local root={Transparency=1,IsA=function(_,kind) return kind=='BasePart' end}
  local body={Transparency=.25,IsA=function(_,kind) return kind=='BasePart' end}
  local face={Transparency=.3,IsA=function(_,kind) return kind=='Decal' end}
  local humanoid={}
  local model={attributes={},root=root,body=body,face=face}
  function model:Destroy() self.destroyed=true; self.Parent=nil end
  function model:ScaleTo(scale) self.scale=scale end
  function model:SetAttribute(key,value) self.attributes[key]=value end
  function model:FindFirstChild() return root end
  function model:FindFirstChildOfClass() return humanoid end
  function model:GetDescendants() return {root,body,face} end
  function model:PivotTo(cf) self.pivot=cf end
  return model
 end
 local Appearance={createRig=function(_,_,id)
  local model=rig(); table.insert(calls,{id=id,rig=model})
  if options.block then table.insert(pending,coroutine.running()); coroutine.yield() end
  return true,model,if options.loaded then options.loaded[#calls] else id>0,'temporary test failure'
 end}
 local Actor=luau.load(fs.readFile('src/client/ChocolatierAnimator.luau'),{environment={
  game={GetService=function() return {} end},script={Parent={FriendAppearance='appearance'}},require=function() return Appearance end,
  Instance={new=function() return {Destroy=function(self) self.destroyed=true end} end},
  Color3=R.Color3,Vector3=R.Vector3,CFrame=R.CFrame,Enum=R.Enum,
  Random={new=function() return {NextInteger=function() return 1 end,NextNumber=function() return .5 end} end},
  task={spawn=function(fn) resume(coroutine.create(fn)) end,defer=function(fn) table.insert(deferred,fn) end,
   delay=function(seconds,fn) table.insert(delayed,{seconds=seconds,fn=fn}) end},warn=function() end,
 },injectGlobals=true})()
 local parent={Parent=true}
 return {calls=calls,delayed=delayed,parent=parent,
  create=function() return Actor.new(parent,'Apprentice',3.7,false,R.Vector3.zero) end,
  flush=function() while #deferred>0 do resume(coroutine.create(table.remove(deferred,1))) end end,
  finish=function(index) resume(table.remove(pending,index or 1)) end,
  retry=function() table.remove(delayed,1).fn() end,
 }
end
return function(h)
 h.test('назначение друга в том же кадре не создаёт лишнего запасного персонажа',function()
  local f=fixture(); local actor=f.create()
  actor:setIdentity(1001,7); actor:setIdentity(1002,8); actor:setVisible(true)
  f.flush()
  h.equals(#f.calls,1); h.equals(f.calls[1].id,1002)
  h.equals(actor.rig.attributes.AssignedUserId,1002)
  h.equals(actor.rig.body.Transparency,.25); h.equals(actor.rig.face.Transparency,.3)
  h.equals(actor.rig.root.Transparency,1); h.equals(actor.rig.scale,.8)
 end)
 h.test('удаление станции до запуска загрузки не обращается к внешности',function()
  local f=fixture(); local actor=f.create(); actor:setIdentity(1001,7)
  actor:destroy(); f.flush(); h.equals(#f.calls,0)
  actor:setIdentity(1002,8); f.flush(); h.equals(#f.calls,0)
 end)
 h.test('поздние загрузки старого друга и удалённой станции уничтожаются',function()
  local f=fixture({block=true}); local actor=f.create(); actor:setIdentity(1001,7); f.flush()
  actor:setIdentity(1002,8); f.flush()
  f.finish(2); h.equals(actor.rig.attributes.AssignedUserId,1002)
  local current=actor.rig
  f.finish(1); h.equals(actor.rig,current); h.equals(f.calls[1].rig.destroyed,true)
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
end
