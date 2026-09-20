--!nonstrict
-- Не маппится Rojo: добавляется только в локальный entrypoint перед Play.
assert(game:GetService("RunService"):IsStudio(), "QA requires Studio")
local qa=Instance.new("BindableFunction"); qa.Name="StudioQaControl"; qa.Parent=player.PlayerGui
local renderedFrames=0
local networkProbe
game:GetService("RunService").RenderStepped:Connect(function() renderedFrames+=1 end)
local function waitUntil(predicate, seconds)
 local deadline=os.clock()+seconds
 repeat if predicate() then return true end; task.wait(.1) until os.clock()>=deadline
 return false
end
local function checkText(container)
 local checked,failures=0,{}
 for _,item in container:GetDescendants() do
  if item:IsA("TextLabel") or item:IsA("TextButton") then
   if item.Visible and item.Text~="" and item.AbsoluteSize.X>0 and item.AbsoluteSize.Y>0 then
    checked+=1
    if not item.TextFits then table.insert(failures,item:GetFullName()..": "..item.Text) end
   end
  end
 end
 assert(#failures==0,table.concat(failures,"\n")); return checked
end
local function dispatch(args)
 local state=atelier.state
 if args.action=="snapshot" then
  return {ready=state and state.ready==true,workers=state and state.levels.workers,manual=state and state.manual}
 end
 assert(state and state.ready,"Client state is not ready")
 if args.action=="captureView" then
  local frames=renderedFrames
  if args.scene=='cutting' then kitchen:setOpen(false)
  elseif args.scene=='kitchen' then kitchen:setOpen(true); kitchen:step(.5)
  elseif args.scene=='rear' then dispatch({action='rearDetail',preview=true})
  elseif args.scene=='catalog' then kitchen:setOpen(true); kitchen:openShop()
  else error('Unknown capture scene') end
  local ready=waitUntil(function()
   local camera=workspace.CurrentCamera
   return renderedFrames>=frames+2 and camera and camera.ViewportSize.X>1 and camera.ViewportSize.Y>1
  end,5)
  local camera=workspace.CurrentCamera
  return {ok=ready,renderReady=ready,scene=args.scene,frames=renderedFrames,
   fieldOfView=camera and camera.FieldOfView,viewport=camera and {x=camera.ViewportSize.X,y=camera.ViewportSize.Y}}
 elseif args.action=="avatarLifecycle" then
  local Animator=require(script.ChocolatierAnimator)
  local Appearance=require(script.FriendAppearance)
  local original=Appearance.createRig
  local parent=Instance.new("Model"); parent.Name="AvatarLifecycleQA"; parent.Parent=kitchen.world
  local actor,cancelled
  local calls=0; local identity=-567890
  -- Отрицательный QA-id использует обычную сборку R6, без запроса чужого
  -- аккаунта. Остальные станции проходят через загрузчик без изменений.
  Appearance.createRig=function(players,description,id,rigType,current)
   if id==identity then calls+=1 end
   return original(players,description,id,rigType,current)
  end
  local ok,result=pcall(function()
   actor=Animator.new(parent,"Current",0,true,kitchen.origin,identity)
   actor:setIdentity(identity,42); actor:setVisible(true)
   cancelled=Animator.new(parent,"Cancelled",0,true,kitchen.origin,identity)
   cancelled:destroy()
   assert(waitUntil(function() return actor.rig~=nil end,15),"Avatar did not load")
   assert(calls==1,"Obsolete assignments started avatar loads: "..calls)
   assert(actor.rig.Parent==parent and actor.rig:GetAttribute("AssignedUserId")==identity,"Wrong avatar attached")
   assert(math.abs(actor.rig:GetScale()-.8)<.001,"Avatar scale changed")
   local root=actor.rig:FindFirstChild("HumanoidRootPart")
   local torso=actor.rig:FindFirstChild("Torso")
   assert(root.Transparency==1 and torso.Transparency==0,"Initial visibility changed")
   actor:setVisible(false); assert(torso.Transparency==1,"Avatar did not hide")
   actor:setVisible(true); assert(torso.Transparency==0 and root.Transparency==1,"Avatar did not restore")
   actor:destroy(); assert(actor.rig==nil and #parent:GetChildren()==0,"Destroyed avatar retained its model")
   return {ok=true,createdRigs=calls,cancelledBeforeLoad=true,visibilityRestored=true}
  end)
  Appearance.createRig=original
  if actor then actor:destroy() end
  if cancelled then cancelled:destroy() end
  parent:Destroy()
  assert(ok,result); return result
 elseif args.action=="loadingRecovery" then
  local saved=state
  kitchen:setOpen(false)
  kitchen.state=nil
  for i=1,3 do
   local loading={ready=false}
   atelier:update(loading); kitchen:update(loading); kitchen:step(.1)
   assert(gameView.inputBlocked and not atelier.journal.chip.Visible,'Loading left input or order active')
   kitchen:openShop(); kitchen:watchPlayer({}); kitchen:setOpen(true)
   assert(not kitchen.shopping and not kitchen.focus and not kitchen.opened,'Incomplete profile entered a kitchen action')
   atelier:update(saved); kitchen:update(saved)
   assert(kitchen.state.ready and atelier.journal.chip.Visible,'Ready state did not recover')
   assert(gameView.inputBlocked==(atelier.overlay.Visible and not atelier.docked),'Ready input stayed blocked')
  end
  kitchen:setOpen(true)
  atelier:update({ready=false}); kitchen:update({ready=false}); kitchen:step(.5)
  for _,prompt in kitchen.prompts do assert(not prompt.Enabled,'Loading left a prompt enabled') end
  atelier:update(saved); kitchen:update(saved); kitchen:setOpen(false)
  return {ok=true,recoveries=4,initialPartialState=true}
 elseif args.action=="apprenticeTempo" then
  local Online=require(script.OnlineKitchen)
  local Action=require(script.WorkstationAction)
  local home=workspace.KitchenIslands:FindFirstChild('KitchenRoom_'..player.UserId)
  assert(home,"Home model is missing")
  local probe=setmetatable({cycles={}},Online)
  local beforeCycle=home:GetAttribute('CycleSeconds')
  local sample=beforeCycle*.23
  local before=probe:cyclePhase(home,sample)
  local oldLevel=state.levels.speed
  -- Предыдущий сценарий только что купил мастерство. Сервер отклоняет
  -- покупки чаще 0.2 с; задержка теста не должна зависеть от скорости MCP.
  task.wait(.25)
  remotes.purchase:FireServer('speed')
  assert(waitUntil(function()
   return atelier.state.levels.speed==oldLevel+1 and home:GetAttribute('CycleSeconds')==atelier.state.cycleSeconds
  end,4),"Speed purchase did not replicate")
  local afterCycle=home:GetAttribute('CycleSeconds')
  local after=probe:cyclePhase(home,sample)
  assert(afterCycle<beforeCycle and before==after,"Speed purchase jumped the cycle")
  local station=kitchen.stations[2]
  local function pose(phase)
   station:pose(Action.cycle((phase+.17)%1,Config,gameView.recipe.slides,gameView.tileWidth,gameView.tileHeight),true,0)
   return station.knife:GetPivot()
  end
  assert(pose(before)==pose(after),"Knife moved at the instant of an upgrade")
  local advanced=probe:cyclePhase(home,sample+.1)
  assert(math.abs(advanced-before-.1/afterCycle)<.000001,"New tempo was not applied")
  return {ok=true,cycleBefore=beforeCycle,cycleAfter=afterCycle,phaseJump=after-before,knifeStable=true}
 elseif args.action=="idleNetwork" then
  local Online=require(script.OnlineKitchen)
  local view=table.clone(gameView); view.active='cut'; view.cutIndex=1; view.cutProgress=0
  local sent=0
  -- Изолированный отправитель считает реальные вызовы той же функции.
  -- Изменяется копия view; в серверную экономику и живой разрез не вмешиваемся.
  local sender=setmetatable({kitchen={view=view},remote={FireServer=function() sent+=1 end}},Online)
  for _=1,21 do sender:publishPlayer(); task.wait(.1) end
  local idle=sent
  assert(idle>=2 and idle<=5,'Idle pose was repeated too often: '..idle)
  for i=1,10 do view.cutProgress=i; sender:publishPlayer(); task.wait(.1) end
  assert(sent-idle==10,'A moving knife lost updates')
  return {ok=true,idlePackets=idle,idleSamples=21,movingPackets=sent-idle,movingSamples=10}
 elseif args.action=="networkPrepare" then
  if networkProbe then networkProbe.connection:Disconnect() end
  networkProbe={}
  networkProbe.connection=remotes.kitchenAction.OnClientEvent:Connect(function(id,action)
   if id==2147483000 then networkProbe.action=action end
  end)
  kitchen:setOpen(true)
  return {ok=true}
 elseif args.action=="networkFinish" then
  local arrived=networkProbe and waitUntil(function() return networkProbe.action~=nil end,4)
  if networkProbe then networkProbe.connection:Disconnect() end
  kitchen:setOpen(false)
  assert(arrived,"Distant player's packet did not arrive through RemoteEvent")
  local action=networkProbe.action; networkProbe=nil
  assert(action.cutting and action.knifePoint==Vector2.new(1.25,2.5),"Network pose changed")
  return {ok=true,transport="RemoteEvent",conditionalAuthor=true}
 elseif args.action=="gesture" then
  -- Только чтение. Резать, сдвигать и завершать раунд будет настоящий ввод
  -- user_mouse_input, не вызов Game:finishCut или RemoteEvent из теста.
  local v=gameView; local camera=workspace.CurrentCamera
  local viewport=if camera then camera.ViewportSize else Vector2.zero
  local result={ready=true,phase=v.active,cut=v.cutIndex,rounds=state.rounds,
   blocked=v.inputBlocked or v.observingKitchen or v.journalOpen or v.diagnosticsOpen or false,
   progress=v.cutProgress,renderReady=renderedFrames>1 and viewport.X>1 and viewport.Y>1,
   frames=renderedFrames,viewport={x=viewport.X,y=viewport.Y}}
  if not result.renderReady then return result end
  local a,b
  if v.active=="cut" then
   local path=v.paths[v.cutIndex].geom
   local geom=require(game.ReplicatedStorage.Shared.Geom)
   a=geom.pointAt(path,v.cutProgress); b=geom.pointAt(path,path.length)
  elseif v.active=="assembleLarge" or v.active=="assembleStrip" then
   local large=v.active=="assembleLarge"; local name=if large then "upperLeft" else "stripDouble"
   local anchor=if large then Vector2.new(v.trick.largeHintAnchor.x*v.tileWidth,v.trick.largeHintAnchor.y*v.tileHeight) else v:pieceCenter(name)
   a=anchor+v.pieces[name].offset
   assert(v:isInsidePiece(name,a),"Gesture start is outside the moving piece")
   local progress=if large then v.largeProgress else v.stripProgress
   b=a+(v:definitionOffset(v.recipe.slides[name])-v:definitionOffset(v.trick.exploded[name]))*(1-progress)
  end
  if a then
   local function screen(point)
    local p=v.scene3D:boardToScreen(point)+v.root.AbsolutePosition
    return {x=p.X,y=p.Y}
   end
   result.start=screen(a); result.finish=screen(b)
  end
  return result
 elseif args.action=="purchase" then
  atelier:setQuantity(10); local before=state.levels.craft
  atelier:purchase(atelier.cards.craft.spec)
  assert(waitUntil(function() return atelier.state.levels.craft==before+10 end,4),"Purchase did not arrive")
  assert(atelier.state.manual==11,"Wrong manual reward after purchase")
  assert(math.abs(atelier.state.rate-27.5)<.0001,"Wrong apprentice rate after purchase")
  return {ok=true,levels=atelier.state.levels.craft,manual=atelier.state.manual,rate=atelier.state.rate}
 elseif args.action=="orders" then
  for i=1,4 do
   local before=atelier.state.rounds; remotes.roundComplete:FireServer()
   assert(waitUntil(function() return atelier.state.rounds==before+1 end,3),"Round did not arrive")
   task.wait(Config.Payout.minInterval+.05)
  end
  assert(atelier.state.ordersCompleted==1 and atelier.state.order.progress==0,"Order did not complete")
  return {ok=true,orders=atelier.state.ordersCompleted,rounds=atelier.state.rounds}
 elseif args.action=="journal" then
  atelier.journal:open()
  assert(gameView.journalOpen and atelier.journal.overlay.Visible,"Journal did not open")
  assert(atelier.journal.offlineCard.Visible,"Offline report is missing")
  atelier.journal:close()
  assert(not gameView.journalOpen and not atelier.journal.overlay.Visible,"Journal did not close")
  return {ok=true,offline=atelier.state.offline,seconds=atelier.state.offlineReport.seconds}
 elseif args.action=="layout" then
  require(script.Localization).__qaLocale(args.locale)
  gameView.root.Size=UDim2.fromOffset(360,780); atelier:fit(); atelier:setOpen(true)
  -- Модальный слой привязан к ScreenGui: сужаем его отдельно от root.
  atelier.panel.Size=UDim2.fromOffset(336,690); atelier.journal.panel.Size=UDim2.fromOffset(336,650)
  atelier.journal:open(); task.wait(.15)
  local checked=checkText(atelier.journal.panel)
  for _,id in {"craft","speed","recipe","cafes"} do
   local card=atelier.cards[id]; checked+=checkText(card.frame)
   assert(card.buy.AbsolutePosition.Y>=card.waitHint.AbsolutePosition.Y+card.waitHint.AbsoluteSize.Y,"Purchase label overlaps button")
  end
  local title=atelier.journal.panel.Title.Text
  if args.locale=="ru-ru" then assert(title=="Дневник шоколатье","Static title was not translated") end
  atelier.journal:close(); atelier:setOpen(false)
  return {ok=true,locale=args.locale,texts=checked,width=atelier.panel.AbsoluteSize.X,title=title}
 elseif args.action=="kitchen" then
  assert(kitchen,"Kitchen is disabled"); kitchen:setOpen(true)
  -- При блокировке macOS RenderStepped может не работать. Вызываем тот же
  -- обработчик явно, не выдавая это за проверку нативного игрового ввода.
  kitchen:step(.5); task.wait(1); kitchen:step(.5)
  assert(kitchen.stations[2].actor.visible,"Home apprentice is hidden")
  assert(#kitchen.online.queueStations==8,"Expected eight detailed queue stations")
  local loaded=if kitchen.stations[2].actor.rig then 1 else 0
  for _,entry in kitchen.online.queueStations do
   assert(entry.station.actor.visible,"Queue apprentice is hidden")
   if entry.station.actor.rig then loaded+=1 end
  end
  kitchen:setOpen(false)
  return {ok=true,queueStations=8,loadedAvatars=loaded,expectedAvatars=9,frames="explicit"}
 elseif args.action=="rearDetail" then
  kitchen:setOpen(true); kitchen:step(.5)
  local rear={}
  for _,entry in kitchen.online.queueStations do if entry.rear then table.insert(rear,entry) end end
  assert(#rear==2,"Nearest rear cafe is missing full stations")
  assert(waitUntil(function() return rear[1].station.actor.rig and rear[2].station.actor.rig end,15),"Rear avatars did not load")
  for _,entry in rear do
   local station=entry.station
   assert(station.actor.visible and station.actor.rig:FindFirstChild('Humanoid'),"Rear apprentice is a placeholder")
   assert(station.world.Parent==kitchen.online.queue,"Rear station has the wrong parent")
   local z=station.actor.rig:GetPivot().Position.Z-kitchen.origin.Z
   assert(z>31 and z<55,"Detailed apprentice is not in the nearest rear cafe")
   assert(station.whole and station.knife and next(station.parts),"Rear workstation is incomplete")
  end
  for _,object in kitchen.online.queue:GetDescendants() do
   if object.Name=='DistantWorkerHead' then
    local z=object.Position.Z-kitchen.origin.Z
    assert(z<0 or z>55,"Block mannequin remains beside the camera")
   end
  end
  local controller=kitchen.walkController; local distance,pitch=controller.distance,controller.pitch
  controller:adjust(0,1000); controller:step(0)
  assert(controller.distance==32,"Maximum walking zoom changed")
  if args.preview then
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root then root.CFrame=CFrame.new(kitchen.origin.X,root.Position.Y,kitchen.origin.Z+17) end
   controller.pitch=30; controller.camera.FieldOfView=90; controller:step(0)
  else controller.distance=distance; controller.pitch=pitch; controller:step(0); kitchen:setOpen(false) end
  return {ok=true,rearAvatars=2,fullWorkstations=2,nearestPlaceholders=0,maxZoom=32,frames="explicit",renderedFrames=renderedFrames}
 elseif args.action=="rosterRefresh" then
  local Appearance=require(script.FriendAppearance)
  local original=Appearance.createRig; local qaId=2147482999; local loads=0
  kitchen:setOpen(true); kitchen:step(.5)
  local online=kitchen.online; local models=workspace.KitchenIslands:GetChildren()
  local home=workspace.KitchenIslands:FindFirstChild('KitchenRoom_'..player.UserId)
  local before=online.queue; local count=#before:GetDescendants(); local geometry=before:GetChildren()
  local entries=table.clone(online.queueStations); local unchanged={}
  for i,entry in entries do unchanged[i]=entry.station.actor.identity end
  assert(entries[1].owner==player.UserId and entries[1].index==1,"Unexpected first cafe")
  local savedRoster=home:GetAttribute('StaffRoster')
  local roster={}; for id in string.gmatch(savedRoster or '', '%d+') do table.insert(roster,tonumber(id)) end
  while #roster<7 do table.insert(roster,0) end; roster[2]=qaId
  local raw=table.concat(roster,',')
  -- Только тестовый id использует локальную сборку R6. Настоящие аккаунты
  -- не запрашиваются от имени выдуманного друга, остальные загрузки обычные.
  Appearance.createRig=function(players,description,id,rigType,current)
   if id==qaId then
    loads+=1
    local ok,rig=original(players,description,0,rigType,current)
    return ok,rig,ok
   end
   return original(players,description,id,rigType,current)
  end
  local ok,result=pcall(function()
   home:SetAttribute('StaffRoster',raw); online:updateIslands(models)
   assert(online.queue==before,"Friend change rebuilt the room queue")
   for i,entry in online.queueStations do
    assert(entry.station==entries[i].station and entry.source==home,"Station or source was not retained")
    if i>1 then assert(entry.station.actor.identity==unchanged[i],"Unchanged apprentice was reassigned") end
   end
   local actor=entries[1].station.actor
   assert(waitUntil(function() return actor.rig and actor.rig:GetAttribute('AssignedUserId')==qaId end,15),"Replacement avatar did not load")
   assert(loads==1 and online.queue==before and before.Parent~=nil,"Replacement rebuilt geometry")
   for _,object in geometry do assert(object.Parent==before,"Existing room geometry was removed") end
   return {ok=true,queueRetained=true,stationsRetained=#entries,replacementLoads=loads,queueObjects=count,controlledRoster=true}
  end)
  Appearance.createRig=original
  home:SetAttribute('StaffRoster',savedRoster); online:updateIslands(models); kitchen:setOpen(false)
  assert(ok,result); return result
 elseif args.action=="peerReplacement" then
  kitchen:setOpen(true)
  local directory=workspace.KitchenIslands; local online=kitchen.online
  local id=-567891; local key=tostring(id)..':0'
  local fake=Instance.new('Model'); fake.Name='PeerReplacementQA'
  for name,value in {OwnerId=id,CafeIndex=0,OwnerOnline=false,DisplayName='QA',Username='QA',
   HasApprentice=false,CafeCount=0,CycleSeconds=10,Origin=kitchen.origin+Vector3.new(30,0,0)} do fake:SetAttribute(name,value) end
  fake.Parent=directory
  local replacement
  local ok,result=pcall(function()
   kitchen:step(.5)
   local first=online.peers[key]
   assert(first and first.station,"Temporary neighboring station did not appear")
   local oldWorld=first.world; local oldStation=first.station.world
   kitchen:watchPlayer(first); assert(kitchen.watchPeer==first and kitchen.focus,"Watch mode did not open")
   replacement=fake:Clone(); fake:Destroy(); replacement.Parent=directory
   kitchen:step(.5)
   local second=online.peers[key]
   assert(second and second~=first and second.model==replacement,"Old room model stayed attached")
   assert(oldWorld.Parent==nil and oldStation.Parent==nil,"Old room retained its geometry")
   assert(kitchen.watchPeer==nil and not kitchen.focus,"Old watch mode did not close")
   local moved=kitchen.origin+Vector3.new(35,0,0)
   replacement:SetAttribute('Origin',moved); kitchen:step(.5)
   local third=online.peers[key]
   assert(third and third~=second and third.origin==moved and third.station,"Room did not move to its new origin")
   assert(second.world.Parent==nil,"Moved room left old geometry")
   return {ok=true,modelReplaced=true,watchClosed=true,originUpdated=true,conditionalNeighbor=true}
  end)
  fake:Destroy(); if replacement then replacement:Destroy() end
  kitchen:step(.5); kitchen:setOpen(false)
  assert(ok,result); assert(online.peers[key]==nil,"Temporary neighbor was not removed"); return result
 elseif args.action=="directoryRefresh" then
  kitchen:setOpen(true)
  local d=kitchen.directory; local models={}; local created=0; local original=d.createRow
  d.createRow=function(self,entry) created+=1; return original(self,entry) end
  for i=1,8 do
   local model=Instance.new('Model'); model.Name='DirectoryQA_'..i
   for name,value in {OwnerId=-88000-i,CafeIndex=0,OwnerOnline=true,DisplayName='QA '..i,Username='qa'..i,
    CafeCount=0,HasApprentice=false,CycleSeconds=10,Origin=kitchen.origin+Vector3.new(9000+i*256,0,0)} do model:SetAttribute(name,value) end
   model.Parent=workspace.KitchenIslands; table.insert(models,model)
  end
  local ok,result=pcall(function()
   d:open(); assert(created==8 and #d.entries==8,'Directory did not create eight visitors')
   task.wait(.3); d.scroll.CanvasPosition=Vector2.new(0,80); task.wait(.1)
   local scroll=d.scroll.CanvasPosition; local first=d.rows[-88001]; local other=d.rows[-88002]
   models[1]:SetAttribute('CafeCount',99); models[1]:SetAttribute('DisplayName','Updated QA')
   d:refresh(); task.wait(.1)
   assert(d.rows[-88001]==first and d.rows[-88002]==other and created==8,'Count update recreated cards')
   assert(first.name.Text=='Updated QA' and first.cafeCount==99,'Card contents were not updated')
   assert(d.scroll.CanvasPosition==scroll,'Count update moved the scroll position')
   d:close(); d:open(); assert(created==8 and d.rows[-88001]==first,'Reopening recreated cards')
   models[1]:SetAttribute('OwnerOnline',false); d:refresh()
   assert(first.frame.Parent==nil and not d.rows[-88001] and d.rows[-88002]==other,'Leaving removed the wrong cards')
   models[1]:SetAttribute('OwnerOnline',true); d:refresh()
   assert(created==9 and d.rows[-88001]~=first,'Returning did not create one new card')
   return {ok=true,retainedCards=8,newCardsOnReturn=1,scrollY=scroll.Y,conditionalVisitors=true}
  end)
  d.createRow=original
  for _,model in models do model:Destroy() end
  d:refresh(); d:close(); kitchen:step(.5); kitchen:setOpen(false)
  assert(ok,result); return result
 elseif args.action=="catalog" then
  local catalog=require(game.ReplicatedStorage.Shared.KitchenCatalog)
  kitchen:setOpen(true); kitchen:openShop()
  local slot=atelier.placeProgress.clock
  assert(slot.count.Text=="0/5","Wrong initial collection count")
  atelier.selectedPlace="clock"; atelier:update(atelier.state)
  remotes.purchase:FireServer("clock_5")
  assert(waitUntil(function() return atelier.state.owned.clock_5==true end,4),"Clock purchase did not arrive")
  assert(slot.count.Text=="1/5" and slot.visualId=="clock_5","Map did not show the purchased clock")
  local original=slot.visual; atelier:update(atelier.state)
  assert(slot.visual==original,"Income refresh recreated the thumbnail")
  assert(atelier.cards.clock_5.installed.Enabled,"Displayed clock not marked")
  local rate=atelier.state.rate; local balance=atelier.state.slices
  task.wait(.25)
  remotes.purchase:FireServer("clock_5")
  assert(waitUntil(function() return atelier.state.equipped.clock==nil end,4),"Clock did not hide")
  assert(slot.count.Text=="1/5" and slot.visualId=="clock_1","Hidden clock lost collection credit")
  assert(not atelier.cards.clock_5.installed.Enabled,"Hidden clock still marked as displayed")
  assert(atelier.state.rate==rate and atelier.state.slices>=balance,"Hiding changed bonus or charged pieces")
  local checked=0
  for _,locale in {"en-us","ru-ru"} do
   require(script.Localization).__qaLocale(locale)
   atelier.panel.Size=UDim2.fromOffset(336,690)
   atelier.selectedPlace=nil; atelier:update(atelier.state); task.wait(.15)
   checked+=checkText(atelier.placeMap)
   for _,group in {"clock","temper","library","workers","art","rug","plant"} do
    atelier.selectedPlace=group; atelier:update(atelier.state); task.wait(.15)
    for _,card in atelier.cards do if card.spec.group==group then checked+=checkText(card.frame) end end
   end
  end
  atelier:setOpen(false); kitchen:setOpen(false)
  return {ok=true,collected=catalog.collection(atelier.state).owned,texts=checked,thumbnailReused=true,bonusKept=true}
 elseif args.action=="visibility" then
  kitchen:setOpen(true); kitchen:step(.5)
  local online=kitchen.online; local origin=kitchen.origin
  local all=kitchen.world:GetDescendants(); local excluded=online.queue:GetDescendants()
  local sentinel=online.queue:FindFirstChildWhichIsA("BasePart",true)
  assert(sentinel,"Queue has no parts"); sentinel.LocalTransparencyModifier=.37
  local late=Instance.new("Part"); late.Anchored=true; late.Transparency=1; late.CanCollide=false
  late.Position=origin+Vector3.new(256,0,0); late.Parent=kitchen.world
  online:updateLocalVisibility(origin); assert(late.LocalTransparencyModifier==1,"New part was not hidden")
  late.Position=origin; online:updateLocalVisibility(origin)
  assert(late.LocalTransparencyModifier==0,"Moved part did not reappear"); late:Destroy()
  online:updateLocalVisibility(origin+Vector3.new(256,0,0))
  assert(math.abs(sentinel.LocalTransparencyModifier-.37)<.001,"Queue visibility was overwritten")
  online:updateLocalVisibility(origin); sentinel.LocalTransparencyModifier=0
  local checked=0
  for _,part in all do
   if part:IsA("BasePart") and not part:IsDescendantOf(online.queue) then
    local expected=if (part.Position-origin).Magnitude<55 then 0 else 1
    assert(part.LocalTransparencyModifier==expected,"Local visibility mismatch: "..part:GetFullName())
    checked+=1
   end
  end
  -- Замер одного участка, не FPS. Старый обход оставлен только в тесте;
  -- количество комнат и деталей в обоих случаях строго одинаковое.
  local function legacy()
   for _,part in kitchen.world:GetDescendants() do
    if part:IsA("BasePart") and not part:IsDescendantOf(online.queue) then
     part.LocalTransparencyModifier=if (part.Position-origin).Magnitude<55 then 0 else 1
    end
   end
  end
  local samples={}
  for _=1,3 do
   local started=os.clock(); for _=1,100 do legacy() end
   local before=(os.clock()-started)*1000
   started=os.clock(); for _=1,100 do online:updateLocalVisibility(origin) end
   table.insert(samples,{beforeMs=before,afterMs=(os.clock()-started)*1000})
  end
  kitchen:setOpen(false)
  return {ok=true,checked=checked,descendants=#all,excluded=#excluded,samples=samples,iterations=100}
 end
 error("Unknown QA action: "..tostring(args.action))
end
qa.OnInvoke=function(args)
 local ok,result=pcall(dispatch,args)
 return if ok then result else {ok=false,error=tostring(result)}
end
