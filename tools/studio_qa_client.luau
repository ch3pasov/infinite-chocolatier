--!nonstrict
-- Не маппится Rojo: добавляется только в локальный entrypoint перед Play.
assert(game:GetService("RunService"):IsStudio(), "QA requires Studio")
-- PlayerGui удаляет прямых детей при возрождении. Постоянный игровой
-- ScreenGui сохраняет и проверочный канал до завершения собственного Play.
local qa=Instance.new("BindableFunction"); qa.Name="StudioQaControl"; qa.Parent=gui
local renderedFrames=0
local networkProbe
local respawnProbe
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
  return {ready=state and state.ready==true,manualReady=state and state.manualReady,
   workers=state and state.levels and state.levels.workers,manual=state and state.manual}
 end
 assert(state and state.ready,"Client state is not ready")
 if args.action=='staffChoiceOpen' then
  if args.locale then require(script.Localization).__qaLocale(args.locale) end
  kitchen:setOpen(true);kitchen:step(.5);kitchen:openShop()
  atelier.selectedPlace='workers';atelier:update(state)
  if args.picker then
   atelier.staffPicker:setOpen(true)
   assert(waitUntil(function() return atelier.staffPicker.received==atelier.staffPicker.request end,15),'Staff list did not arrive')
  end
  local picker=atelier.staffPicker
  return {ok=true,opened=picker.opened,candidates=#picker.rows,selected=atelier.state.apprenticeUserId,
   texts=if picker.opened then checkText(picker.frame) else checkText(atelier.cards.workers_1.frame)}
 elseif args.action=='staffChoiceSelect' then
  local picker=atelier.staffPicker;local id=args.id
  assert(picker.opened,'Staff picker is closed');picker:send('select',id)
  assert(waitUntil(function() return atelier.state.apprenticeUserId==id and picker.received==picker.request end,10),'Staff selection was not accepted')
  local home=workspace.KitchenIslands:FindFirstChild('KitchenRoom_'..player.UserId)
  if id>0 then assert(home:GetAttribute('Staff1')==id,'Selected friend did not reach main table') end
  kitchen:step(.5)
  return {ok=true,selected=id,mainStaff=home:GetAttribute('Staff1'),texts=checkText(picker.frame)}
 elseif args.action=='staffChoiceClose' then
  atelier:setOpen(false);kitchen:setOpen(false)
  assert(not atelier.staffPicker.opened,'Picker remained open')
  return {ok=true}
 end
 if args.action=='promptLocalization' then
  local L=require(script.Localization)
  local Catalog=require(game.ReplicatedStorage.Shared.LocalizationCatalog)
  local observations={}
  local function verify(prompt,action,object,params,literal)
   assert(prompt,'Missing proximity prompt: '..action)
   assert(prompt.AutoLocalize==false,'Engine may translate a finished prompt again')
   assert(prompt.ActionText==Catalog.format(action,nil,args.locale),'Wrong action: '..prompt.ActionText)
   local expected=if object then Catalog.format(object,params,args.locale) else literal
   if expected then assert(prompt.ObjectText==expected,'Wrong object: '..prompt.ObjectText) end
   table.insert(observations,{action=prompt.ActionText,object=prompt.ObjectText})
  end
  local function verifyAll(locale,neighbor)
   args.locale=locale;L.__qaLocale(locale)
   for _,spec in {{'My worktable','Cut chocolate'},{'Apprentice worktable','Watch apprentice'},{'Kitchen upgrades','My Kitchen'}} do
    verify(kitchen.prompts[spec[1]],spec[2],spec[1])
   end
   local staff=kitchen.online.peers[tostring(player.UserId)..':1']
   assert(staff,'Test staff cafe missing')
   verify(staff.prompt,'Watch apprentices',nil,nil,staff.player.DisplayName..' · 1')
   local arrow=workspace.KitchenIslands:FindFirstChild('NextCafePrompt',true)
   verify(arrow,'Choose a cafe',nil,nil,'Infinite Chocolatier')
   local board;for _,entry in rankings.world do if rankings:current(entry) then board=entry;break end end
   verify(board and board.prompt,'View rankings','Global top 10')
   if neighbor then
    verify(neighbor.prompt,'Watch player',nil,nil,'Cocoa_Друг (@Watch_player)')
    verify(neighbor.apprenticePrompt,'Watch apprentice','Apprentice of {name}',{name='Cocoa_Друг'})
   end
  end
  kitchen:setOpen(true);kitchen.online:step(.5)
  verifyAll('en-us');verifyAll('ru-ru')
  -- Сосед появляется уже после смены языка. Все атрибуты задаём до Parent,
  -- чтобы проверка перевода не создавала неполную сетевую комнату.
  local room=Instance.new('Model');room.Name='PromptLocalizationQA'
  for key,value in {OwnerId=-12345,CafeIndex=0,Origin=kitchen.origin+Vector3.new(4096,0,0),DisplayName='Cocoa_Друг',Username='Watch_player',OwnerOnline=false,HasApprentice=true} do room:SetAttribute(key,value) end
  room.Parent=workspace.KitchenIslands;kitchen.online:step(.5)
  local neighbor=kitchen.online.peers['-12345:0'];assert(neighbor,'Late neighbor missing')
  verifyAll('ru-ru',neighbor);verifyAll('en-us',neighbor);verifyAll('ru-ru',neighbor)
  room:Destroy();kitchen.online:step(.5)
  assert(not kitchen.online.peers['-12345:0'],'Deleted neighbor retained')
  kitchen:setWalking();kitchen:step(0)
  return {ok=true,checks=observations,lateNeighbor=true,namesPreserved=true,removed=true}
 elseif args.action=="captureView" then
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
 elseif args.action=="hintTiming" then
  kitchen:setOpen(false); gameView:resetRound(); gameView.scene3D:syncHints()
  local samples={}
  for _=1,3 do
   local elapsed=0
   for _=1,10 do
    local start=os.clock()
    for _=1,100 do gameView.scene3D:syncHints() end
    elapsed+=os.clock()-start; task.wait()
   end
   table.insert(samples,elapsed*1000)
  end
  return {ok=true,samplesMs=samples,iterations=1000,hints=#gameView.hintLayer:GetChildren()}
 elseif args.action=="avatarLifecycle" then
  local Animator=require(script.ChocolatierAnimator)
  local Appearance=require(script.FriendAppearance)
  local original=Appearance.createRig
  local parent=Instance.new("Model"); parent.Name="AvatarLifecycleQA"; parent.Parent=kitchen.world
  local actor,cancelled
  local calls=0; local identity=-567890
  -- Отрицательный QA-id использует обычную сборку R15, без запроса чужого
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
   assert(math.abs(actor.rig:GetScale()-1)<.001,"Avatar scale changed")
   local root=actor.rig:FindFirstChild("HumanoidRootPart")
   local torso=actor.rig:FindFirstChild("UpperTorso")
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
 elseif args.action=="playerAvatar" then
  local Animator=require(script.ChocolatierAnimator)
  assert(waitUntil(function() return player.Character and player.Character:GetAttribute('AvatarReady') and player.Character:FindFirstChildOfClass('Humanoid') end,30),'Walking avatar did not load')
  local character=args.character or player.Character; local humanoid=character:FindFirstChildOfClass('Humanoid')
  local parent=Instance.new('Model'); parent.Name='PlayerAppearanceQA'; parent.Parent=kitchen.world
  local actor=Animator.new(parent,'LiveAvatar',-3.7,true,kitchen.origin,args.userId or player.UserId)
  local ok,result=pcall(function()
   actor:setVisible(true)
   assert(waitUntil(function() return actor.rig~=nil end,20),'Live avatar did not load')
   local copy=actor.rig:FindFirstChildOfClass('Humanoid')
   assert(copy.RigType==humanoid.RigType,'Walking avatar changed rig type at table')
   assert(math.abs(actor.rig:GetScale()-character:GetScale())<.001,'Walking avatar changed model scale')
   local sourceDescription=humanoid:GetAppliedDescription(); local tableDescription=copy:GetAppliedDescription()
   for _,property in {'Head','Torso','LeftArm','RightArm','LeftLeg','RightLeg','HeadColor','TorsoColor','LeftArmColor','RightArmColor','LeftLegColor','RightLegColor','Shirt','Pants','GraphicTShirt','Face','HeightScale','WidthScale','DepthScale','HeadScale','BodyTypeScale','ProportionScale'} do
    assert(sourceDescription[property]==tableDescription[property],'Avatar changed '..property)
   end
   local function accessories(description)
    local ids={}; for _,accessory in description:GetAccessories(true) do table.insert(ids,accessory.AssetId) end
    table.sort(ids); return table.concat(ids,',')
   end
   assert(accessories(sourceDescription)==accessories(tableDescription),'Avatar lost accessories or layered clothing')
   sourceDescription:Destroy(); tableDescription:Destroy()
   -- Два пустых описания раньше тоже проходили сравнение. Проверяем
   -- фактическую геометрию/одежду и снятие масок, которыми видит игрок.
   local visualParts=0
   local function compare(source,target)
    for _,item in source:GetChildren() do
     if item:IsA('BaseScript') or item:IsA('Tool') or item:IsA('ForceField') then continue end
     local properties=if item:IsA('MeshPart') then {'Color','Size','MeshId','TextureID'}
      elseif item:IsA('BasePart') then {'Color','Size'} elseif item:IsA('Decal') then {'Texture'}
      elseif item:IsA('Shirt') then {'ShirtTemplate'} elseif item:IsA('Pants') then {'PantsTemplate'}
      elseif item:IsA('ShirtGraphic') then {'Graphic'} else {}
     local copyItem=target:FindFirstChild(item.Name)
     if not copyItem then
      assert(#properties==0 and not item:IsA('Accessory') and not item:IsA('SurfaceAppearance') and not item:IsA('DataModelMesh') and not item:IsA('CharacterMesh') and not item:IsA('BodyColors'),'Missing avatar item '..item:GetFullName())
      continue
     end
     for _,property in properties do assert(copyItem[property]==item[property],'Changed visual '..item.Name..'.'..property) end
     if item:IsA('BasePart') or item:IsA('Decal') then
      local transparency=item:GetAttribute('KitchenOriginalTransparency') or item.Transparency
      assert(copyItem.Transparency==transparency and copyItem.LocalTransparencyModifier==0,'Copied avatar mask '..item.Name)
      visualParts+=1
     end
     compare(item,copyItem)
    end
   end
   compare(character,actor.rig)
   local ikCount=0
   for _,entry in actor.ik do
    assert(entry.control.ChainRoot and entry.control.EndEffector and entry.control.Target,'Incomplete arm IK')
    ikCount+=1
   end
   assert(ikCount==(if humanoid.RigType==Enum.HumanoidRigType.R15 then 2 else 0),'Wrong arm rig')
   return {ok=true,rigType=copy.RigType.Name,scale=actor.rig:GetScale(),accessoriesKept=true,descriptionKept=true,visualParts=visualParts,ikArms=ikCount}
  end)
  actor:destroy(); parent:Destroy()
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
 elseif args.action=="respawnPrepare" then
  kitchen:setOpen(false); gameView:resetRound()
  assert(waitUntil(function() return atelier.state.manualReady==true end,4),'Worktable was not ready')
  local oldBegin=player:GetAttribute('StudioQaManualBegin')
  gameView.manualStarted=true; gameView:reportStep('begin')
  assert(waitUntil(function() return player:GetAttribute('StudioQaManualBegin')~=oldBegin end,4),'Begin was not accepted')
  local progress=gameView.paths[1].geom.length*.4
  gameView.cutProgress=progress; gameView:drawProgress(gameView.paths[1],progress)
  gameView.drag={kind='cut',progress=progress,ready=false}
  respawnProbe={character=player.Character,progress=progress,rounds=state.rounds}
  respawnProbe.connection=remotes.stateSync.OnClientEvent:Connect(function(nextState)
   if nextState.manualReady==false then
    respawnProbe.sawUnready=true
    task.defer(function()
     if respawnProbe then respawnProbe.blocked=gameView.inputBlocked and gameView.drag==nil end
    end)
   end
  end)
  return {ok=true,progress=progress}
 elseif args.action=="respawnFinish" then
  local probe=assert(respawnProbe,'Respawn was not prepared')
  local arrived=waitUntil(function()
   return player.Character and player.Character~=probe.character and atelier.state.manualReady==true
  end,12)
  probe.connection:Disconnect(); respawnProbe=nil
  assert(arrived,'New character did not restore the worktable')
  assert(probe.sawUnready and probe.blocked,'Death did not block and release the cut')
  assert(gameView.active=='cut' and gameView.cutIndex==1 and gameView.cutProgress==probe.progress,'Respawn reset cut progress')
  assert(not gameView.inputBlocked and gameView.drag==nil,'Respawn left stale input')
  gameView:finishCut()
  assert(waitUntil(function() return player:GetAttribute('StudioQaManualStep')==1 end,4),'Resumed step was not accepted')
  assert(atelier.state.rounds==probe.rounds,'Respawn produced a round reward')
  gameView:resetRound()
  return {ok=true,newCharacter=true,cutPreserved=true,inputRecovered=true,serverAcceptedAfterResume=true}
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
   -- Здесь проверяется начисление заказа синтетическим протоколом.
   -- Настоящие жесты и геометрия проверяются отдельным сценарием native input.
   local before=atelier.state.rounds
   local previousBegin=player:GetAttribute('StudioQaManualBegin')
   remotes.manualStep:FireServer('cancel'); remotes.manualStep:FireServer('begin')
   assert(waitUntil(function() return player:GetAttribute('StudioQaManualBegin')~=previousBegin end,4),'Server did not accept manual begin')
   for step=1,#Config.Recipe.cuts+1 do remotes.manualStep:FireServer(step) end
   task.wait(Config.Payout.minInterval+.05)
   remotes.roundComplete:FireServer()
   assert(waitUntil(function() return atelier.state.rounds==before+1 end,3),"Round did not arrive")
   task.wait(Config.Payout.minInterval+.05)
  end
  assert(atelier.state.ordersCompleted==1 and atelier.state.order.progress==0,"Order did not complete")
  local receipt=atelier.state.lastOrder
  assert(receipt and receipt.name==Config.Orders[1].name and receipt.number==1,'Order receipt missing')
  assert(receipt.bonus==atelier.state.manual*Config.Orders[1].bonusRounds,'Receipt has the wrong bonus')
  return {ok=true,orders=atelier.state.ordersCompleted,rounds=atelier.state.rounds,receipt=receipt}
 elseif args.action=="cutInterruption" then
  kitchen:setOpen(false); gameView:resetRound()
  assert(waitUntil(function() return atelier.state.manualReady end,4),'Manual table is not ready')
  local previousBegin=player:GetAttribute('StudioQaManualBegin')
  gameView.manualStarted=true; gameView:reportStep('begin')
  assert(waitUntil(function() return player:GetAttribute('StudioQaManualBegin')~=previousBegin end,4),'Server did not accept manual begin')
  local path=gameView.paths[1]
  local radius=math.min(Config.Cutting.finishSnapRadius/gameView.boardScale.Scale,path.geom.length*(1-Config.Cutting.finishSnapMinProgress))
  gameView.cutProgress=path.geom.length-radius/2
  local progress=gameView.cutProgress; local rounds=atelier.state.rounds
  gameView:finishCutSmoothly(path); kitchen:setOpen(true)
  assert(waitUntil(function() return player:GetAttribute('KitchenMode')=='walk' and atelier.state.manualReady==false end,4),'Server did not confirm walking')
  task.wait(Config.Cutting.finishSnapDuration+.05)
  assert(gameView.active=='cut' and gameView.cutIndex==1 and gameView.cutProgress==progress,'Walking completed or erased the pending cut')
  assert(player:GetAttribute('StudioQaManualStep')==0,'Interrupted cut advanced the server')
  kitchen:setOpen(false)
  assert(waitUntil(function() return player:GetAttribute('KitchenMode')=='cut' and atelier.state.manualReady end,4),'Manual table did not recover')
  gameView:finishCutSmoothly(path)
  assert(waitUntil(function() return gameView.cutIndex==2 and player:GetAttribute('StudioQaManualStep')==1 end,4),'Resumed cut was not accepted by server')
  assert(atelier.state.rounds==rounds,'Partial cut awarded a whole trick')
  gameView:resetRound()
  return {ok=true,cutPreserved=true,serverAcceptedAfterResume=true,noPrematureReward=true}
 elseif args.action=="journal" then
  atelier.journal:open()
  assert(gameView.journalOpen and atelier.journal.overlay.Visible,"Journal did not open")
  assert(atelier.journal.offlineCard.Visible,"Offline report is missing")
  local journal=atelier.journal; local saved=atelier.state
  journal:selectPage('bonuses')
  assert(journal.calculations.Visible and not journal.pages.Visible,'Bonus page did not open')
  assert(saved.bonuses and saved.bonuses.manual==saved.manual,'Bonus snapshot differs from income')
  assert(journal.bonusRows.online and journal.bonusRows.spectators and journal.bonusRows.cycle,'Bonus rows are missing')
  journal:selectPage('journal')
  assert(journal.productionCard.Visible and journal.productionCycle.Visible,'Factory report is missing')
  local L=require(script.Localization)
  assert(journal.receiptCard.Visible and journal.receiptName.Text==L.text(saved.lastOrder.name),'Last order is missing from the journal')
  assert(journal.receiptBonus.Text==L.text('Bonus received: +{bonus}',{bonus=L.number(saved.lastOrder.bonus)}),'Journal receipt changed the paid bonus')
  assert(journal.productionCount.Text==L.text('{cafes} cafes · {workers} apprentices',{cafes=L.number(13),workers=L.number(25)}),'Wrong cafe or apprentice count')
  assert(journal.productionCycle.Text==L.text('Each apprentice: +{reward} every {seconds}s',{reward=L.number(saved.cycleReward),seconds=L.number(saved.cycleSeconds)}),'Wrong production cycle')
  local economy=require(game.ReplicatedStorage.Shared.Economy)
  local empty=economy.snapshot(economy.load(nil)); empty.ready=true
  journal:update(empty)
  assert(not journal.receiptCard.Visible,'New session shows a previous receipt')
  assert(not journal.productionCycle.Visible and journal.productionRate.Text==L.text('No apprentices yet'),'Empty factory shows active production')
  journal:update({ready=false}); assert(not journal.productionCard.Visible and not journal.receiptCard.Visible,'Loading shows old factory or receipt')
  journal:update(saved)
  atelier.journal:close()
  assert(not gameView.journalOpen and not atelier.journal.overlay.Visible,"Journal did not close")
  local cut,progress=gameView.cutIndex,gameView.cutProgress
  kitchen:setOpen(true); kitchen:step(0)
  assert(kitchen.journalButton.Visible,'Walking has no journal entry')
  journal:open(); kitchen:step(0)
  assert(journal.overlay.Visible and not kitchen.journalButton.Visible,'Walking journal did not open')
  assert(journal.receiptCard.Visible,'Walking lost the completed order')
  assert(kitchen.controls.controlsEnabled==false,'Walking remained active while reading')
  for _,prompt in kitchen.prompts do assert(not prompt.Enabled,'Journal left a worktable prompt active') end
  for _,entry in workspace.KitchenIslands:GetDescendants() do
   if entry:IsA('ProximityPrompt') then assert(not entry.Enabled,'Journal left a visit arrow active') end
  end
  kitchen.directory:open(); kitchen:openShop(); kitchen:watchPlayer({})
  assert(not kitchen.browsing and not kitchen.shopping and not kitchen.focus,'Another menu overlapped the journal')
  journal:close(); kitchen:step(0)
  assert(kitchen.controls.controlsEnabled and kitchen.journalButton.Visible,'Walking did not resume')
  kitchen:openShop(); journal:open()
  assert(not journal.overlay.Visible,'Journal overlapped the catalog')
  atelier:setOpen(false)
  journal:open(); kitchen:setOpen(false)
  assert(not journal.overlay.Visible and not gameView.journalOpen and not kitchen.controls.controlsEnabled,'Return to cutting left journal or movement active')
  assert(gameView.cutIndex==cut and gameView.cutProgress==progress,'Reading changed the manual cut')
  return {ok=true,offline=atelier.state.offline,seconds=atelier.state.offlineReport.seconds,factoryCafes=13,apprentices=25,emptyFactory=true,walkingJournal=true,movementRestored=true,cutPreserved=true}
 elseif args.action=="rankingsView" then
  assert(rankings,'Rankings missing')
  if args.locale then require(script.Localization).__qaLocale(args.locale) end
  if args.fixture then
   kitchen:setOpen(true)
   local rows={};for i=1,10 do rows[i]={id=-i,name=string.format('QA_Player_%02d',i),score=1000-i*10} end
   rankings.snapshot={studio=true,boards={pieces={ready=true,rows=rows},guests={ready=true,rows=rows},tricks={ready=true,rows=rows}}};rankings:render()
  end
  if args.close then rankings:close() end
  local entry
  for _,item in rankings.world do if rankings:current(item) then entry=item;break end end
  assert(entry,'Current board missing')
  if args.open then rankings:open(entry) end
  local camera=workspace.CurrentCamera
  local root=game.Players.LocalPlayer.Character.HumanoidRootPart
  local function vec(v) return {x=v.X,y=v.Y,z=if typeof(v)=='Vector3' then v.Z else nil} end
  local function project(x,y)
   local canvas=entry.surface.CanvasSize
   local point=entry.part.CFrame:PointToWorldSpace(Vector3.new((x/canvas.X-.5)*entry.part.Size.X,(.5-y/canvas.Y)*entry.part.Size.Y,entry.part.Size.Z/2+.02))
   local p,visible=camera:WorldToViewportPoint(point);return {x=p.X,y=p.Y,visible=visible}
  end
  local columns={}
  for key,column in entry.columns do
   local x=column.frame.Position.X.Offset+column.scroll.Position.X.Offset+column.scroll.AbsoluteSize.X*.5
   local y=column.frame.Position.Y.Offset+column.scroll.Position.Y.Offset+column.scroll.AbsoluteSize.Y*.5
   columns[key]={scroll=column.scroll.CanvasPosition.Y,enabled=column.scroll.ScrollingEnabled,visible=column.frame.Visible,input=project(x,y),rowsHeight=column.scroll.AbsoluteSize.Y,canvas=column.scroll.AbsoluteCanvasSize.Y}
  end
  return {ok=true,opened=rankings.entry==entry,ready=rankings.camera:ready(),portrait=entry.portrait,canWalk=kitchen:canWalk(),columns=columns,
   position=vec(root.Position),camera={position=vec(camera.CFrame.Position),look=vec(camera.CFrame.LookVector),name=camera.Name,fov=camera.FieldOfView},
   viewport=vec(camera.ViewportSize),boardTopLeft=project(0,0),boardBottomRight=project(entry.surface.CanvasSize.X,entry.surface.CanvasSize.Y),
   promptDistance=(root.Position-entry.prompt.Parent.WorldPosition).Magnitude,range=entry.prompt.MaxActivationDistance,texts=checkText(entry.surface)}
 elseif args.action=="rankings" then
  assert(rankings,'Rankings not initialized')
  rankings:close()
  local L=require(script.Localization);L.__qaLocale(args.locale)
  local original=rankings.snapshot
  local sample={studio=true,boards={}}
  for _,key in {'pieces','guests','tricks'} do
   local rows={};for i=1,10 do table.insert(rows,{id=i,name=string.rep('W',20),score=1e15-i}) end
   sample.boards[key]={rows=rows,ready=true}
  end
  local root=game.Players.LocalPlayer.Character.HumanoidRootPart
  local previousPosition=root.CFrame
  local ok,result=pcall(function()
   kitchen:setOpen(true);rankings.snapshot=sample;rankings:render();kitchen.online:step(.5)
   local board
   for _,entry in rankings.world do
    assert(entry.prompt.ActionText==L.text('View rankings'),'Island refresh replaced ranking action text')
    if rankings:current(entry) then board=entry end
   end
   assert(board,'No current rankings board')
   assert(board.surface.Parent==game.Players.LocalPlayer.PlayerGui and board.surface.Adornee==board.part and board.part.CanQuery,'Surface cannot receive native input')
   local origin=board.room:GetAttribute('Origin');local center=board.part.Position-origin
   assert(center.Z-board.part.Size.X/2>9.25 and center.Z+board.part.Size.X/2<17,'Board is not in front of the painting')
   local previousCamera=workspace.CurrentCamera
   -- Только исходная точка теста: нативный подход проверяется отдельно через CUA.
   local anchor=board.prompt.Parent.WorldPosition
   root.CFrame=CFrame.new(anchor.X,root.Position.Y,anchor.Z)
   rankings:open(board)
   assert(rankings.entry==board and not kitchen:canWalk(),'Rankings did not block walking')
   assert(workspace.CurrentCamera==rankings.camera.camera and not rankings.camera:ready(),'Camera did not start turning')
   for _,column in board.columns do assert(not column.scroll.ScrollingEnabled,'Scrolling started before camera turn') end
   assert(not atelier.journal.canOpen(),'Journal opened over rankings')
   task.wait(.65)
   assert(rankings.camera:ready(),'Camera transition did not finish')
   local cases={}
   for key,column in board.columns do
    assert(column.scroll.ScrollingEnabled and column.scroll.Active,'Native scrolling stayed disabled')
    local last=column.rows[10]
    assert(last.Position.Y.Offset+last.AbsoluteSize.Y<=column.scroll.AbsoluteCanvasSize.Y,'Last rank cannot be scrolled into view')
    local before=column.scroll.CanvasPosition
    rankings:render();assert(column.scroll.CanvasPosition==before,'Refreshing data resets scrolling')
    table.insert(cases,{key=key,rows=#column.rows,rowsHeight=column.scroll.AbsoluteSize.Y})
   end
   local texts=checkText(board.surface)
   rankings:close();assert(workspace.CurrentCamera==previousCamera and kitchen:canWalk(),'Closing did not restore camera and movement')
   rankings:open(board);task.wait(.05);rankings:close()
   assert(workspace.CurrentCamera==previousCamera,'Early cancellation lost walking camera')
   local delayed=Instance.new('Model');delayed.Name='RankingsReplicationQA'
   -- Полные подписи нужны соседнему контроллеру кафе; здесь задерживаем
   -- только атрибуты, от которых зависит создание самой доски рейтинга.
   delayed:SetAttribute('DisplayName','QA visitor');delayed:SetAttribute('Username','QA_Visitor');delayed:SetAttribute('OwnerOnline',false)
   delayed.Parent=workspace.KitchenIslands
   delayed:SetAttribute('CafeIndex',0);delayed:SetAttribute('Origin',Vector3.new(4096,0,1000));task.wait(.05)
   assert(rankings.world[delayed]==nil,'Board created without owner')
   delayed:SetAttribute('OwnerId',-123);task.wait(.05)
   assert(rankings.world[delayed],'Late attributes lost board')
   local surface=rankings.world[delayed].surface
   delayed:Destroy();task.wait(.05);assert(rankings.world[delayed]==nil and rankings.pendingRooms[delayed]==nil and not surface.Parent,'Departed room retained surface or board')
   return {ok=true,locale=args.locale,cases=cases,texts=texts,portrait=board.portrait,cloud=false,cameraRestored=true,earlyCancel=true,partZ=center.Z}
  end)
  rankings:close();rankings.snapshot=original;rankings:render()
  root.CFrame=previousPosition;kitchen:setOpen(false)
  assert(ok,result);return result
 elseif args.action=="hudLayout" then
  local L=require(script.Localization); L.__qaLocale(args.locale)
  local original=gameView.root.Size
  local probes={}; local cases={}
  local ok,result=pcall(function()
   for _,size in {Vector2.new(749,381),Vector2.new(568,320),Vector2.new(400,777),Vector2.new(296,600),Vector2.new(336,720),Vector2.new(1440,900)} do
    gameView.root.Size=UDim2.fromOffset(size.X,size.Y); atelier:fit(); task.wait(.05)
    assert(atelier.metrics.TextFits,'Production summary clipped: '..atelier.metrics.Text)
    local hint=gameView.status:Clone(); hint.Name='HudHintQA'; hint.TextTransparency=1; hint.Parent=gameView.status.Parent
    table.insert(probes,hint)
    local hints=0
    for index,instruction in Config.Trick.cutLabels do
     L.set(hint,'Cut {step} of {total}: {instruction}',{step=index,total=4,instruction=L.token(instruction)})
     task.wait(.05); assert(hint.TextFits,'Cut hint clipped: '..hint.Text); hints+=1
    end
    for _,source in {'Slide the large piece along the arrow — the other piece will follow','Slide the two-piece strip into the gap at the top',
      'All four cuts are done — the bar separates into five pieces','Done! The bar is whole again, with one original piece left over'} do
     L.set(hint,source); task.wait(.05); assert(hint.TextFits,'Phase hint clipped: '..hint.Text); hints+=1
    end
    local counter=gameView.counter:Clone(); counter.Name='HudCounterQA'; counter.TextTransparency=1; counter.Parent=gameView.counter.Parent
    table.insert(probes,counter)
    for _,amount in {0,Config.Economy.maxValue} do
     L.set(counter,if atelier.compactCounter then '{amount}' else 'PIECES  {amount}',{amount=L.number(amount)})
     task.wait(.05); assert(counter.TextFits,'Counter clipped: '..counter.Text)
    end
    if not atelier.landscape then
     assert(counter.Position.X.Offset>=game:GetService('GuiService').TopbarInset.Min.X+8,'Counter overlaps Roblox controls')
    end
    table.insert(cases,{width=size.X,height=size.Y,hints=hints,hintHeight=hint.AbsoluteSize.Y,counterWidth=counter.AbsoluteSize.X,compact=atelier.compactCounter})
    hint:Destroy(); counter:Destroy()
   end
   return {ok=true,locale=args.locale,cases=cases}
  end)
  for _,probe in probes do probe:Destroy() end
  gameView.root.Size=original; atelier:fit()
  assert(ok,result); return result
 elseif args.action=="layout" then
  require(script.Localization).__qaLocale(args.locale)
  gameView.root.Size=UDim2.fromOffset(360,780); atelier:fit(); atelier:setOpen(true)
  -- Модальный слой привязан к ScreenGui: сужаем его отдельно от root.
  atelier.panel.Size=UDim2.fromOffset(336,690); atelier.journal.panel.Size=UDim2.fromOffset(336,650)
  atelier.journal:open(); task.wait(.15)
  local checked=checkText(atelier.journal.panel)
  local receiptChecks=0
  for _,spec in Config.Orders do
   local snapshot=table.clone(state); snapshot.lastOrder={name=spec.name,bonus=Config.Economy.maxValue,number=123}
   atelier.journal:update(snapshot)
   receiptChecks+=checkText(atelier.journal.receiptCard)
  end
  atelier.journal:update(state)
  for _,id in {"craft","speed","recipe","cafes"} do
   local card=atelier.cards[id]; checked+=checkText(card.frame)
   assert(card.buy.AbsolutePosition.Y>=card.waitHint.AbsolutePosition.Y+card.waitHint.AbsoluteSize.Y,"Purchase label overlaps button")
  end
  local saveChecks=0
  for _,status in {'Progress saved','Saving delayed · retrying','Test session · progress is not saved'} do
   local snapshot=table.clone(state); snapshot.saveStatus=status; snapshot.saveAge=29
   atelier:update(snapshot)
   local L=require(script.Localization)
   local expected=if status=='Progress saved' then L.text('Saved {seconds}s ago',{seconds=L.number(29)}) else L.text(status)
   assert(atelier.saved.Text==expected,'Save status did not prioritize error or Studio')
   local size=game:GetService('TextService'):GetTextSize(expected,atelier.saved.TextSize,atelier.saved.Font,Vector2.new(atelier.saved.AbsoluteSize.X,1000))
   assert(size.Y<=atelier.saved.AbsoluteSize.Y,'Save status overflows footer')
   saveChecks+=1
  end
  local prestigeChecks=0
  local Economy=require(game.ReplicatedStorage.Shared.Economy)
  for _,sample in {{earned=2500,stars=0},{earned=10000,stars=0},{earned=20000,stars=Config.Economy.maxStars-1},{earned=5000,stars=Config.Economy.maxStars}} do
   local snapshot=table.clone(state); snapshot.earned=sample.earned; snapshot.stars=sample.stars
   snapshot.prestigeGain=Economy.prestigeGain(snapshot)
   for _,confirmed in {false,true} do
    atelier.confirmed=confirmed; atelier:update(snapshot)
    local preview=Economy.prestigeProgress(snapshot)
    assert(math.abs(atelier.fill.Size.X.Scale-preview.progress)<.001,'Prestige bar targets the wrong star')
    assert(atelier.cancel.Visible==(confirmed and preview.gain>0),'Invalid prestige confirmation remains visible')
    prestigeChecks+=checkText(atelier.prestigeCard)
    assert(atelier.ascend.AbsolutePosition.Y>=atelier.fill.Parent.AbsolutePosition.Y+atelier.fill.Parent.AbsoluteSize.Y,'Prestige button overlaps the progress bar')
   end
  end
  atelier.confirmed=false; atelier:update(state)
  local title=atelier.journal.panel.Title.Text
  if args.locale=="ru-ru" then assert(title=="Дневник шоколатье","Static title was not translated") end
  atelier.journal:close(); atelier:setOpen(false)
  local rewardChecks=0
  local L=require(script.Localization)
  local active,token,blocked=gameView.active,gameView.animationToken,gameView.inputBlocked
  local effects={}
  for _,amount in {.25,357800,15000000,Config.Economy.maxValue} do
   local before={}; for _,child in gameView.root:GetChildren() do before[child]=true end
   gameView:playRewardEffect(amount)
   local effect
   for _,child in gameView.root:GetChildren() do
    if child.Name=='RewardEffect' and not before[child] then effect=child end
   end
   assert(effect,'Reward effect did not appear')
   table.insert(effects,effect)
   local label=effect.EarnedSlices
   assert(label.Text==L.text('+{amount}',{amount=L.number(amount)}),'Reward does not use wallet number formatting')
   local limit=label:FindFirstChildOfClass('UITextSizeConstraint')
   local bounds=game:GetService('TextService'):GetTextSize(label.Text,limit.MinTextSize,label.Font,Vector2.new(1000,1000))
   assert(bounds.X<=160 and bounds.Y<=44,'Reward text cannot fit at its minimum size')
   rewardChecks+=1
  end
  assert(gameView.active==active and gameView.animationToken==token and gameView.inputBlocked==blocked,'Reward interrupted the next cut')
  task.wait(Config.Feedback.duration+.1)
  for _,effect in effects do assert(effect.Parent==nil,'Reward effect leaked after fading') end
  kitchen:setOpen(true); kitchen:step(0); task.wait(.1)
  assert(kitchen.journalButton.Position.Y.Offset>=64,'Narrow journal button overlaps Roblox controls')
  assert(kitchen.journalButton.TextFits,'Journal button text overflows')
  kitchen:setOpen(false)
  return {ok=true,locale=args.locale,receiptChecks=receiptChecks,rewardChecks=rewardChecks,saveChecks=saveChecks,prestigeChecks=prestigeChecks,texts=checked,width=atelier.panel.AbsoluteSize.X,title=title}
 elseif args.action=="bonusLayout" then
  local L=require(script.Localization); L.__qaLocale(args.locale)
  local Economy=require(game.ReplicatedStorage.Shared.Economy)
  -- Отдельный экземпляр настоящего журнала исключает гонку с ежесекундным
  -- StateSync. Тестовый профиль не подменяет состояние игрока или сохранение.
  local owner=Instance.new('ScreenGui'); owner.Name='BonusLayoutQA'; owner.IgnoreGuiInset=true; owner.Parent=player.PlayerGui
  local root=Instance.new('Frame'); root.BackgroundTransparency=1; root.Size=UDim2.fromScale(1,1); root.Parent=owner
  local view={root=root,endDrag=function() end}
  local journal=require(script.Journal).new(owner,view)
  local data=Economy.load({stars=4,collectionVersion=2,owned={workers_1=true,temper_1=true,library_1=true,clock_1=true},levels={kitchen=1,craft=2,recipe=2,speed=3,cafes=2}})
  data.onlineFriend=true; Economy.addSocial(data,'guests',202,101); Economy.addSocial(data,'spectators',202,101)
  local normal=Economy.snapshot(data); normal.ready=true
  local extreme=Economy.load({stars=1000000,collectionVersion=2,owned={workers_1=true},levels={kitchen=1,craft=1e9,recipe=1e9,speed=1e9,cafes=10000}})
  extreme.socialCounts={guests=1000000,spectators=1000000}; extreme.onlineFriend=true
  local large=Economy.snapshot(extreme); large.ready=true
  local cases={}
  local ok,result=pcall(function()
   journal:update(normal); journal:open(); journal:selectPage('bonuses')
   for _,width in {296,336,496} do
    journal.panel.Size=UDim2.fromOffset(width,650)
    for index,snapshot in {normal,large} do
     journal:update(snapshot); task.wait(.15)
     local texts=checkText(journal.calculations); local count=0
     for key,row in journal.bonusRows do
      count+=1
      local card=row.value.Parent
      assert(card.AbsoluteSize.Y>0,'Collapsed bonus card: '..key)
      assert(row.help.AbsolutePosition.Y>=row.value.AbsolutePosition.Y+row.value.AbsoluteSize.Y-1,'Overlapping bonus text: '..key)
      assert(row.help.AbsolutePosition.Y+row.help.AbsoluteSize.Y<=card.AbsolutePosition.Y+card.AbsoluteSize.Y+1,'Clipped bonus explanation: '..key)
      assert(not row.value.Text:find('{',1,true) and not row.help.Text:find('{',1,true),'Unformatted bonus: '..key)
     end
     assert(count==15 and texts==30,'Missing bonus rows')
     local layout=journal.calculations:FindFirstChildOfClass('UIListLayout')
     assert(journal.calculations.AbsoluteCanvasSize.Y>=layout.AbsoluteContentSize.Y-1,'Bonus cards cannot be scrolled to the end')
     table.insert(cases,{width=journal.panel.AbsoluteSize.X,rows=count,texts=texts,large=index==2,
      height=layout.AbsoluteContentSize.Y,cycle=journal.bonusRows.cycle.value.Text})
    end
   end
   return {ok=true,locale=args.locale,cases=cases}
  end)
  if ok then
   -- Фиксированная тестовая высота 650 px не должна попадать в живой
   -- preview низкого телефона. Проверяем штатную адаптивную панель.
   journal.panel.Size=UDim2.new(1,-24,1,-32); journal:update(normal); task.wait(.15)
   ok=journal.panel.AbsolutePosition.Y>=0
   if not ok then result='Journal overlaps Roblox top controls' end
  end
  if not (ok and args.preview) then owner:Destroy() end
  assert(ok,result); return result
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
 elseif args.action=="queueGrowth" then
  local Online=require(script.OnlineKitchen)
  local Kitchen=require(script.Kitchen)
  local source=workspace.KitchenIslands:FindFirstChild('KitchenRoom_'..player.UserId):Clone()
  source:SetAttribute('StaffRoster','')
  local world=Instance.new('Model'); world.Name='QueueGrowthQA'; world.Parent=workspace
  -- Очередь строится только в открытой кухне; подсказки используют настоящий
  -- canWalk. Отдельная копия состояния не меняет режим живого игрока.
  local probeKitchen=setmetatable({view=gameView,world=world,player=player,
   origin=kitchen.origin,opened=true,state=state},{__index=Kitchen})
  local probe=setmetatable({kitchen=probeKitchen,queueStations={},cycles={}},Online)
  local function geometryCount(root)
   local count=if root:IsA('BasePart') then 1 else 0
   for _,child in root:GetChildren() do
    if not child:IsA('Model') or not child:FindFirstChildOfClass('Humanoid') then count+=geometryCount(child) end
   end
   return count
  end
  local function grow(count)
   source:SetAttribute('CafeCount',count); probe:updateIslands({source})
   local rooms=0; for _ in probe.queueRooms do rooms+=1 end
   assert(rooms<=Config.Kitchen.queueLimit,'Queue allocated unbounded rooms')
   assert(#probe.queueStations<=8,'Queue allocated unbounded full stations')
   return geometryCount(world)
  end
  local ok,result=pcall(function()
   grow(12)
   local before={}; for _,entry in probe.queueStations do before[entry.station]=true end
   local first=probe.queueStations[1].station
   local Action=require(script.WorkstationAction)
   first:pose(Action.cycle(.55,Config,gameView.recipe.slides,gameView.tileWidth,gameView.tileHeight),true,0)
   local frames={}
   for _,piece in first.parts do for _,part in piece:GetDescendants() do
    if part:IsA('BasePart') then frames[part]={part.CFrame,part.Transparency} end
   end end
   local replaced=probe.queueRooms[-1].world
   grow(13)
   local retained=0
   for _,entry in probe.queueStations do if before[entry.station] then retained+=1 end end
   assert(retained==6,'Buying one cafe rebuilt unchanged front stations: '..retained)
   for part,old in frames do assert(part.Parent and part.CFrame==old[1] and part.Transparency==old[2],'Retained chocolate moved during purchase') end
   assert(replaced.Parent==nil and #replaced:GetDescendants()==0,'Replaced room retained geometry')
   local full= grow(100); local maximum=probe.queue; local rooms=table.clone(probe.queueRooms)
   local million=grow(1000000)
   assert(full==million and maximum==probe.queue,'Huge factory allocated more visible geometry')
   for slot,room in rooms do assert(probe.queueRooms[slot]==room,'Offscreen purchase rebuilt a visible room') end
   local moved=source:GetAttribute('Origin')+Vector3.new(256,0,0)
   source:SetAttribute('Origin',moved); grow(1000000)
   assert(maximum.Parent==nil and probe.queue~=maximum,'Changing the current room retained the old queue origin')
   for slot,room in probe.queueRooms do
    for _,entry in room.stations do
     local x=if entry.side==1 then -3.7 else 3.7
     local expected=moved+Vector3.new(x-.75,2.37,-38*slot-.3)
     assert((entry.station.origin-expected).Magnitude<.001,'Station moved to the wrong queue slot')
    end
   end
   rooms=table.clone(probe.queueRooms)
   local reduced=grow(1)
   assert(#probe.queueStations==2 and reduced<full,'Shrinking factory retained distant stations')
   for _,room in rooms do
    if probe.queueRooms[1]~=room then assert(room.world.Parent==nil,'Removed room stayed alive') end
   end
   grow(0); assert(#world:GetDescendants()==1,'Empty factory retained queue rooms')
   probe:clearQueue(); assert(#world:GetDescendants()==0,'Queue cleanup leaked descendants')
   task.wait(.2); assert(#world:GetDescendants()==0,'Late avatar returned after cleanup')
   return {ok=true,retainedStations=retained,changedStations=2,fullGeometry=full,millionGeometry=million,oneCafeGeometry=reduced,originChanged=true,cleaned=true}
  end)
  probe:clearQueue(); world:Destroy(); source:Destroy()
  assert(ok,result); return result
 elseif args.action=="rearDetail" then
  kitchen:setOpen(true); kitchen:step(.5)
  local rear={}
  for _,entry in kitchen.online.queueStations do if entry.rear then table.insert(rear,entry) end end
  assert(#rear==2,"Nearest rear cafe is missing full stations")
  assert(waitUntil(function() return rear[1].station.actor.rig and rear[2].station.actor.rig end,15),"Rear avatars did not load")
  for _,entry in rear do
   local station=entry.station
   assert(station.actor.visible and station.actor.rig:FindFirstChild('Humanoid'),"Rear apprentice is a placeholder")
   assert(station.world:IsDescendantOf(kitchen.online.queue),"Rear station has the wrong parent")
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
   d:open(); assert(created==9 and #d.entries==9,'Directory did not create home and eight visitors')
   assert(d.entries[1].owner==player.UserId,'Home is not first in directory')
   task.wait(.3); d.scroll.CanvasPosition=Vector2.new(0,80); task.wait(.1)
   local scroll=d.scroll.CanvasPosition; local first=d.rows[-88001]; local other=d.rows[-88002]
   models[1]:SetAttribute('CafeCount',99); models[1]:SetAttribute('DisplayName','Updated QA')
   d:refresh(); task.wait(.1)
   assert(d.rows[-88001]==first and d.rows[-88002]==other and created==9,'Count update recreated cards')
   assert(first.name.Text=='Updated QA' and first.cafeCount==99,'Card contents were not updated')
   assert(d.scroll.CanvasPosition==scroll,'Count update moved the scroll position')
   d:close(); d:open(); assert(created==9 and d.rows[-88001]==first,'Reopening recreated cards')
   models[1]:SetAttribute('OwnerOnline',false); d:refresh()
   assert(first.frame.Parent==nil and not d.rows[-88001] and d.rows[-88002]==other,'Leaving removed the wrong cards')
   models[1]:SetAttribute('OwnerOnline',true); d:refresh()
   assert(created==10 and d.rows[-88001]~=first,'Returning did not create one new card')
   return {ok=true,retainedCards=9,newCardsOnReturn=1,scrollY=scroll.Y,conditionalVisitors=true,homeFirst=true}
  end)
  d.createRow=original
  for _,model in models do model:Destroy() end
  d:refresh(); d:close(); kitchen:step(.5); kitchen:setOpen(false)
  assert(ok,result); return result
 elseif args.action=="catalog" then
  local catalog=require(game.ReplicatedStorage.Shared.KitchenCatalog)
  local home=workspace.KitchenIslands:FindFirstChild('KitchenRoom_'..player.UserId)
  kitchen:setOpen(true); kitchen:openShop()
  local slot=atelier.placeProgress.clock
  assert(slot.count.Text=="0/5","Wrong initial collection count")
  atelier.selectedPlace="clock"; atelier:update(atelier.state)
  remotes.purchase:FireServer("clock_5")
  assert(waitUntil(function() return atelier.state.owned.clock_5==true end,4),"Clock purchase did not arrive")
  assert(waitUntil(function() return catalog.fromAppearance(home:GetAttribute('CafeAppearance')).equipped.clock=='clock_5' end,4),'Selected clock did not replicate')
  assert(slot.count.Text=="1/5" and slot.visualId=="clock_5","Map did not show the purchased clock")
  local original=slot.visual; atelier:update(atelier.state)
  assert(slot.visual==original,"Income refresh recreated the thumbnail")
  assert(atelier.cards.clock_5.installed.Enabled,"Displayed clock not marked")
  local rate=atelier.state.rate; local balance=atelier.state.slices
  task.wait(.25)
  remotes.purchase:FireServer("clock_5")
  assert(waitUntil(function() return atelier.state.equipped.clock==nil end,4),"Clock did not hide")
  assert(waitUntil(function() return catalog.fromAppearance(home:GetAttribute('CafeAppearance')).equipped.clock==nil end,4),'Hidden clock remains public')
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
 elseif args.action=="publicDecor" then
  kitchen:setOpen(true)
  local id=-779911; local fake=Instance.new('Model'); fake.Name='PublicDecorQA'
  for name,value in {OwnerId=id,CafeIndex=0,OwnerOnline=true,DisplayName='Decor QA',Username='decorqa',
   HasApprentice=false,CafeCount=0,CycleSeconds=10,Origin=kitchen.origin+Vector3.new(30,0,0),CafeAppearance=',,clock_5,plant,,'} do fake:SetAttribute(name,value) end
  fake.Parent=workspace.KitchenIslands
  local ok,result=pcall(function()
   kitchen:step(.5); local online=kitchen.online; local peer=online.peers[tostring(id)..':0']
   local copy
   for _,room in online.queueDecor do if room.owner==id then copy=room end end
   assert(peer and copy,'Guest or queue home is missing')
   for _,room in {peer,copy} do
    assert(room.decorModel:FindFirstChild('PendulumBob') and room.decorModel:FindFirstChild('CocoaPot'),'Public furniture is missing')
   end
   local world=peer.world; local station=peer.station; local queue=online.queue
   local oldPeer,oldCopy=peer.decorModel,copy.decorModel
   fake:SetAttribute('CafeAppearance',',,clock_2,,,'); kitchen:step(.5)
   for _,room in {peer,copy} do
    assert(room.decorModel:FindFirstChild('ClockFrame') and not room.decorModel:FindFirstChild('PendulumBob') and not room.decorModel:FindFirstChild('CocoaPot'),'Changed furniture was not applied')
   end
   assert(oldPeer.Parent==nil and oldCopy.Parent==nil,'Old furniture was retained')
   assert(peer.world==world and peer.station==station and online.queue==queue,'Furniture change rebuilt workstations')
   fake:SetAttribute('OwnerOnline',false); kitchen:step(.5)
   assert(peer.decorModel:FindFirstChild('ClockFrame'),'Leaving owner removed furniture')
   fake:SetAttribute('CafeAppearance',',,,,,'); kitchen:step(.5)
   assert(not peer.decorModel:FindFirstChild('ClockFrame') and not copy.decorModel:FindFirstChild('ClockFrame'),'Removed furniture remains visible')
   return {ok=true,physicalHome=true,queueHome=true,stationsRetained=true,departedOwnerRetained=true,conditionalOwner=true}
  end)
  fake:Destroy(); kitchen:step(.5); kitchen:setOpen(false)
  assert(ok,result); return result
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
  local function measure(run)
   local elapsed=0
   for _=1,10 do
    local started=os.clock(); for _=1,10 do run() end
    elapsed+=os.clock()-started
    -- Большая очередь на слабом компьютере не должна исчерпывать лимит
    -- одного Lua-потока. Ожидание кадра не входит в замер самого обхода.
    task.wait()
   end
   return elapsed*1000
  end
  local samples={}
  for _=1,3 do
   local before=measure(legacy)
   table.insert(samples,{beforeMs=before,afterMs=measure(function() online:updateLocalVisibility(origin) end)})
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
