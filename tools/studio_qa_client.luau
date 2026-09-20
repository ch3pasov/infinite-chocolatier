--!nonstrict
-- Не маппится Rojo: добавляется только в локальный entrypoint перед Play.
assert(game:GetService("RunService"):IsStudio(), "QA requires Studio")
local qa=Instance.new("BindableFunction"); qa.Name="StudioQaControl"; qa.Parent=player.PlayerGui
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
 if args.action=="purchase" then
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
  assert(#kitchen.online.queueStations==6,"Expected six detailed queue stations")
  local loaded=if kitchen.stations[2].actor.rig then 1 else 0
  for _,entry in kitchen.online.queueStations do
   assert(entry.station.actor.visible,"Queue apprentice is hidden")
   if entry.station.actor.rig then loaded+=1 end
  end
  kitchen:setOpen(false)
  return {ok=true,queueStations=6,loadedAvatars=loaded,expectedAvatars=7,frames="explicit"}
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
