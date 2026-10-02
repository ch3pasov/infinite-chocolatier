--!nonstrict
-- Настоящие подписки кухни, но порядок окончания WaitForChild задаём сами:
-- ответ от старого персонажа может прийти после нового или после cleanup.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local stub=setmetatable({},{__index=function(_,key) return key end})
local Kitchen=luau.load(fs.readFile('src/client/Kitchen.luau'),{environment={
 game={GetService=function() return {WaitForChild=function() return stub end} end},
 script={Parent=stub},Color3=R.Color3,Enum=R.Enum,require=function() return {} end,
 task={spawn=function(fn,...) local co=coroutine.create(fn); local ok,err=coroutine.resume(co,...); assert(ok,err) end},
},injectGlobals=true})()
local function signal()
 local callbacks={}
 return {Connect=function(_,fn)
  callbacks[fn]=true; return {Disconnect=function() callbacks[fn]=nil end}
 end,Fire=function(_,arg)
  local threads={}
  for fn in callbacks do
   local thread=coroutine.create(fn); local ok,err=coroutine.resume(thread,arg); assert(ok,err)
   table.insert(threads,thread)
  end
  return threads
 end}
end
local function fixture(existing)
 local player={CharacterAdded=signal(),CharacterRemoving=signal()}
 local stats={walks=0,resets=0,enabled=true,clears=0}
 local k=setmetatable({player=player,opened=true,state={ready=true},view={cutIndex=2,cutProgress=47},walkCamera={},prompts={},
  walkController={resetInput=function() stats.resets+=1 end},
  controls={Enable=function() stats.enabled=true end,Disable=function() stats.enabled=false end},
  avatarVisibility={set=function(_,char,visible) assert(char==nil and visible); stats.clears+=1 end},
  setWalking=function(self) stats.walks+=1; self:refreshControls() end,
 },{__index=Kitchen})
 local function character(pending)
  local char={humanoid={states={},SetStateEnabled=function(self,state,value) self.states[state.Name]=value end}}
  function char:WaitForChild(name,timeout)
   assert(name=='Humanoid'); self.timeout=timeout
   return if pending then coroutine.yield() else self.humanoid
  end
  return char
 end
 if existing then player.Character=character() end
 k:bindCharacter()
 local function appear(char)
  player.Character=char; return player.CharacterAdded:Fire(char)[1]
 end
 return k,stats,character,appear
end
local function finish(thread,value)
 local ok,err=coroutine.resume(thread,value); assert(ok,err)
end
return function(h)
 h.test('карабканье отключено у уже появившегося персонажа и каждого нового спавна',function()
  local k,_,char,appear=fixture(true)
  h.equals(k.player.Character.humanoid.states.Climbing,false)
  local nextChar=char(); appear(nextChar)
  h.equals(nextChar.humanoid.states.Climbing,false)
  h.equals(nextChar.humanoid.states.Jumping,nil)
  h.equals(nextChar.humanoid.states.Running,nil)
  k:unbindCharacter()
 end)
 h.test('возрождение сохраняет открытые окна, текущий разрез и режим прогулки',function()
  for _,mode in {'walk','cut','browsing','shopping','focus','journal','report','loading'} do
   local k,stats,char,appear=fixture()
   if mode=='cut' then k.opened=false
   elseif mode=='journal' then k.view.journalOpen=true
   elseif mode=='report' then k.view.diagnosticsOpen=true
   elseif mode=='loading' then k.state.ready=false
   elseif mode~='walk' then k[mode]=true end
   local new=char(); appear(new)
   h.equals(k.walkCamera.CameraSubject,new.humanoid)
   h.equals(stats.walks,if mode=='walk' then 1 else 0,'самовольный переход в прогулку: '..mode)
   h.equals(stats.enabled,mode=='walk'); assert(stats.resets>=1)
   h.equals(k.view.cutIndex,2); h.equals(k.view.cutProgress,47)
   if mode=='browsing' then h.equals(k.browsing,true) end
   k:unbindCharacter()
  end
 end)
 h.test('запоздалый Humanoid не заменяет камеру и управление нового персонажа',function()
  local k,stats,char,appear=fixture()
  local old=char(true); local pending=appear(old)
  local new=char(); appear(new); local resets=stats.resets
  finish(pending,old.humanoid)
  h.equals(old.humanoid.states.Climbing,nil)
  h.equals(k.walkCamera.CameraSubject,new.humanoid); h.equals(stats.walks,1)
  h.equals(stats.resets,resets,'старый ответ не трогает ввод')
  -- Запоздалое удаление старой модели также не сбрасывает нового игрока.
  k.player.CharacterRemoving:Fire(old)
  h.equals(k.walkCamera.CameraSubject,new.humanoid); h.equals(stats.resets,resets)
  k:unbindCharacter()
 end)
 h.test('удаление персонажа освобождает захват, а cleanup отменяет уже начатое ожидание',function()
  local k,stats,char,appear=fixture()
  local old=char(true); local pending=appear(old)
  local resets=stats.resets
  k.player.CharacterRemoving:Fire(old)
  assert(stats.resets>resets); h.equals(stats.clears,1)
  finish(pending,old.humanoid)
  h.equals(k.walkCamera.CameraSubject,nil); h.equals(stats.walks,0)
  local new=char(true); local second=appear(new)
  k:unbindCharacter(); local before=stats.resets
  finish(second,new.humanoid)
  h.equals(k.walkCamera.CameraSubject,nil); h.equals(stats.walks,0); h.equals(stats.resets,before)
  appear(char()); k.player.CharacterRemoving:Fire(new)
  h.equals(stats.walks,0); h.equals(stats.resets,before,'подписки сняты при cleanup')
  k:unbindCharacter()
 end)
 h.test('отсутствующий Humanoid ограничивает ожидание и не меняет интерфейс после таймаута',function()
  local k,stats,char,appear=fixture()
  local absent=char(true); local pending=appear(absent)
  h.equals(absent.timeout,10); finish(pending,nil)
  h.equals(k.walkCamera.CameraSubject,nil); h.equals(stats.walks,0)
  local good=char(); appear(good); h.equals(k.walkCamera.CameraSubject,good.humanoid)
  h.equals(stats.walks,1); k:unbindCharacter()
 end)
end
