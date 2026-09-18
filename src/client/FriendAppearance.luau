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
function Appearance.createRig(players,defaultDescription,userId,rigType)
 local appearance
 if userId and userId>0 then
  local ok,result=pcall(function() return players:GetHumanoidDescriptionFromUserIdAsync(userId) end)
  if ok then appearance=result end
 end
 local ok,rig=pcall(function()
  return players:CreateHumanoidModelFromDescriptionAsync(appearance or defaultDescription,rigType)
 end)
 if appearance then appearance:Destroy() end
 -- Неудачный аксессуар не должен оставлять станцию без персонажа.
 if not ok and appearance then
  ok,rig=pcall(function() return players:CreateHumanoidModelFromDescriptionAsync(defaultDescription,rigType) end)
 end
 return ok,rig
end
return Appearance
