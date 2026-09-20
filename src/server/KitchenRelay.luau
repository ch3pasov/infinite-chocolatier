--!nonstrict
-- Автор берётся из OnServerEvent; клиент не может выдать пакет за соседа.
-- Частота ограничена до разбора позы, а кеш нужен новым наблюдателям.
local Relay={}
function Relay.start(players,remote,wire,clock,visiblePlayers)
 local latest,last,lastRequest,views={}, {}, {}, {}
 local function nearby(observer,author)
  if observer:GetAttribute('KitchenMode')=='cut' then return false end
  local root=observer.Character and observer.Character:FindFirstChild('HumanoidRootPart')
  local origin=author:GetAttribute('KitchenOrigin')
  if root and origin and (root.Position-origin).Magnitude<80 then return true end
  if not visiblePlayers then return false end
  local now=clock(); local owner=observer:GetAttribute('VisitingKitchen'); local index=observer:GetAttribute('VisitingCafeIndex')
  local view=views[observer]
  -- Ограниченная очередь считается раз в полсекунды на наблюдателя,
  -- а не для каждого автора на каждом сетевом кадре. Визит сбрасывает кеш сразу.
  if not view or view.owner~=owner or view.index~=index or now>=view.expires then
   view={owner=owner,index=index,expires=now+.5,players=visiblePlayers(observer)}; views[observer]=view
  end
  return view.players[author.UserId]==true
 end
 remote.OnServerEvent:Connect(function(player,raw)
  local now=clock()
  if raw==nil then
   if now-(lastRequest[player] or -math.huge)<1 then return end
   lastRequest[player]=now
   for author,action in latest do
    if author.Parent and author~=player and nearby(player,author) then remote:FireClient(player,author.UserId,action) end
   end
   return
  end
  if now-(last[player] or -math.huge)<1/20 then return end
  last[player]=now
  local action=wire.clean(raw)
  if not action then return end
  latest[player]=action
  for _,observer in players:GetPlayers() do
   if observer~=player and nearby(observer,player) then remote:FireClient(observer,player.UserId,action) end
  end
 end)
 players.PlayerRemoving:Connect(function(player)
  latest[player]=nil; last[player]=nil; lastRequest[player]=nil; views[player]=nil
 end)
end
return Relay
