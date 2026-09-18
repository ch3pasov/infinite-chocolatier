--!nonstrict
-- Автор берётся из OnServerEvent; клиент не может выдать пакет за соседа.
-- Частота ограничена до разбора позы, а кеш нужен новым наблюдателям.
local Relay={}
function Relay.start(players,remote,wire,clock)
 local latest,last,lastRequest={}, {}, {}
 local function nearby(observer,author)
  if observer:GetAttribute('KitchenMode')=='cut' then return false end
  local root=observer.Character and observer.Character:FindFirstChild('HumanoidRootPart')
  local origin=author:GetAttribute('KitchenOrigin')
  return root and origin and (root.Position-origin).Magnitude<80
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
  latest[player]=nil; last[player]=nil; lastRequest[player]=nil
 end)
end
return Relay
