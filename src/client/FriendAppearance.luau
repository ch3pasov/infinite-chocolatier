--!nonstrict
-- Выбор выполняется один раз при создании стажёра, вне кадрового цикла.
-- Резервуарная выборка учитывает все страницы без хранения списка друзей.
local Appearance={}
function Appearance.pickFriend(players,userId,random)
 if not userId or userId<=0 then return nil end
 local selected,count=nil,0
 local ok=pcall(function()
  local pages=players:GetFriendsAsync(userId)
  while true do
   for _,friend in pages:GetCurrentPage() do
    if type(friend.Id)=='number' and friend.Id>0 and friend.Id~=userId then
     count+=1
     if random(1,count)==1 then selected=friend.Id end
    end
   end
   if pages.IsFinished then break end
   pages:AdvanceToNextPageAsync()
  end
 end)
 return if ok then selected else nil
end
-- Повторные видимые копии используют один запрос описания на пользователя.
-- Кэш ограничен; модели и их суставы остаются отдельными у каждой станции.
local cache={}
local pending={}
local order={}
local function description(players,userId,isCurrent)
 local request=pending[userId]
 if request then
  -- Копия может исчезнуть, пока другая станция ждёт Roblox. Отменяем
  -- собственное ожидание, не трогая запрос, нужный оставшимся станциям.
  while not request.done do
   if isCurrent and not isCurrent() then return nil end
   task.wait()
  end
  if isCurrent and not isCurrent() then return nil end
  -- Уже ожидающие копии получают тот же сбой, а не создают по запросу
  -- каждая. Новая попытка после ответа по-прежнему может загрузить друга.
  if not request.ok then return nil,request.error end
 end
 if isCurrent and not isCurrent() then return nil end
 if cache[userId] then return cache[userId]:Clone() end
 request={done=false}; pending[userId]=request
 local ok,result=pcall(function() return players:GetHumanoidDescriptionFromUserIdAsync(userId) end)
 request.ok=ok
 request.error=if ok then nil else result
 request.done=true
 pending[userId]=nil
 if not ok then return nil,result end
 -- Тестовые описания без Clone не попадают в кэш Roblox-объектов.
 if type(result.Clone)=='function' then
  cache[userId]=result:Clone(); table.insert(order,userId)
  if #order>64 then local id=table.remove(order,1); cache[id]:Destroy(); cache[id]=nil end
 end
 return result
end
function Appearance.createRig(players,defaultDescription,userId,rigType,isCurrent)
 if isCurrent and not isCurrent() then return false,nil,false end
 local appearance,loadError
 if userId and userId>0 then appearance,loadError=description(players,userId,isCurrent) end
 -- Запрос описания может ждать сеть. Устаревшее назначение не должно после
 -- ответа запускать ещё и тяжёлое создание персонажа.
 if isCurrent and not isCurrent() then
  if appearance then appearance:Destroy() end
  return false,nil,false
 end
 local ok,rig=pcall(function()
  return players:CreateHumanoidModelFromDescriptionAsync(appearance or defaultDescription,rigType)
 end)
 local friendLoaded=appearance~=nil and ok
 if appearance then appearance:Destroy() end
 if not ok and appearance and (not isCurrent or isCurrent()) then
  loadError=rig
  ok,rig=pcall(function() return players:CreateHumanoidModelFromDescriptionAsync(defaultDescription,rigType) end)
 end
 return ok,rig,friendLoaded,loadError
end
function Appearance.getPlayer(players,userId)
 if type(players.GetPlayerByUserId)~='function' then return nil end
 return players:GetPlayerByUserId(userId)
end
-- Копируем готового персонажа: ранний GetAppliedDescription может успешно
-- вернуть пустое описание с чёрными цветами и без одежды. Копия сохраняет
-- фактические меши, текстуры, R6/R15 и многослойную одежду без нового API-запроса.
function Appearance.createPlayerRig(players,defaultDescription,userId,fallbackRigType,isCurrent)
 if isCurrent and not isCurrent() then return false,nil,false end
 local player=Appearance.getPlayer(players,userId)
 if not player then return Appearance.createRig(players,defaultDescription,userId,fallbackRigType,isCurrent) end
 local character=player.Character
 if not character then return false,nil,false,'Player character is loading' end
 local function current()
  return player.Character==character and (not isCurrent or isCurrent())
 end
 -- Готовность принадлежит конкретному спавну, а не ревизии Player от прошлой
 -- жизни. Ожидание ограничено и отменяется при удалении станции/персонажа.
 for _=1,100 do
  if not current() then return false,nil,false end
  if character:GetAttribute('AvatarReady') then break end
  task.wait(.1)
 end
 if not current() then return false,nil,false end
 if not character:GetAttribute('AvatarReady') then return false,nil,false,'Player appearance is loading' end
 if not character:FindFirstChildOfClass('Humanoid') or not character:FindFirstChild('HumanoidRootPart') then
  return false,nil,false,'Player rig is loading'
 end
 local archivable=character.Archivable
 local ok,rig=pcall(function()
  character.Archivable=true
  return character:Clone()
 end)
 character.Archivable=archivable
 if not ok or not rig then return false,nil,false,if ok then 'Player clone is unavailable' else rig end
 for _,item in rig:GetDescendants() do
  if item:IsA('BaseScript') or item:IsA('Tool') or item:IsA('ForceField') then item:Destroy()
  elseif item:IsA('BasePart') or item:IsA('Decal') then
   -- Серверная и локальная маски скрывают оригинал при нарезке/наблюдении;
   -- они не должны сделать невидимой его рабочую копию.
   local transparency=item:GetAttribute('KitchenOriginalTransparency')
   if transparency~=nil then item.Transparency=transparency end
   item.LocalTransparencyModifier=0
   item:SetAttribute('KitchenOriginalTransparency',nil)
  end
 end
 return true,rig,true,nil,character
end
return Appearance
