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
local function description(players,userId)
 while pending[userId] do task.wait() end
 if cache[userId] then return cache[userId]:Clone() end
 pending[userId]=true
 local ok,result=pcall(function() return players:GetHumanoidDescriptionFromUserIdAsync(userId) end)
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
 if userId and userId>0 then appearance,loadError=description(players,userId) end
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
return Appearance
