--!nonstrict
-- Ни дружба, ни посещение, ни получатель бонуса не приходят с клиента.
-- Сигналы этапов доказывают порядок игрового протокола, не физический ввод
-- человека. Положение, непрерывность наблюдения и выплаты проверяет сервер.
local Social = {}; Social.__index=Social
function Social.new(economy,rooms,sessions,active,accrue,clock,minInterval)
 return setmetatable({economy=economy,rooms=rooms,sessions=sessions,active=active,
  accrue=accrue,clock=clock,minInterval=minInterval,attempts={}},Social)
end
function Social:session(player)
 local s=self.sessions[player]
 return if s and self.active(player,s) then s else nil
end
function Social:prune(owner,attempt)
 if not self.rooms then return end
 if self.rooms:manualContext(owner)~=attempt.ownerEpoch then attempt.witnesses={}; return end
 for watcher,epoch in attempt.witnesses do
  if self.rooms:watching(owner,watcher)~=epoch or not self.rooms:isFriend(owner,watcher) then
   attempt.witnesses[watcher]=nil
  end
 end
end
function Social:refresh()
 if not self.rooms then return end
 local changed={}
 for player in self.sessions do
  local session=self:session(player)
  if session then
   -- Профиль может загрузиться раньше персонажа. Клиент должен дождаться
   -- того же контекста, который принимает begin, иначе первый фокус пропадёт.
   local manualReady=self.rooms:manualContext(player)~=nil
   if session.manualReady~=manualReady then session.manualReady=manualReady; changed[player]=true end
   local status=if self.rooms.friendStatus then self.rooms:friendStatus(player) else 'ready'
   if session.data.friendStatus~=status then session.data.friendStatus=status; changed[player]=true end
   local online=self.rooms:hasOnlineFriend(player)
   if (session.data.onlineFriend==true)~=online then
    self.accrue(session); session.data.onlineFriend=online; changed[player]=true
   end
  end
 end
 for _,visit in self.rooms:visits() do
  local session=self:session(visit.owner)
  if session and visit.guest.UserId~=visit.owner.UserId then
   local key=string.format('%.0f',visit.guest.UserId)
   if not session.data.social.guests[key] then
    self.accrue(session)
    if self.economy.addSocial(session.data,'guests',visit.guest.UserId,visit.owner.UserId) then changed[visit.owner]=true end
   end
  end
 end
 for owner,attempt in self.attempts do self:prune(owner,attempt) end
 return changed
end
function Social:step(player,step)
 local session=self:session(player); if not session then return end
 if step=='cancel' then self.attempts[player]=nil; return end
 local epoch=if self.rooms then self.rooms:manualContext(player) else true
 if not epoch then return end
 local attempt=self.attempts[player]
 if step=='begin' then
  -- Повтор первого нажатия не позволяет присоединить опоздавших зрителей.
  if attempt then return end
  local witnesses={}
  if self.rooms then
   for _,visit in self.rooms:visits() do
    if visit.owner==player and self.rooms:isFriend(player,visit.guest) then
     local watchEpoch=self.rooms:watching(player,visit.guest)
     if watchEpoch then witnesses[visit.guest]=watchEpoch end
    end
   end
  end
  self.attempts[player]={step=0,started=self.clock(),ownerEpoch=epoch,witnesses=witnesses}
 elseif type(step)=='number' and step%1==0 and step>=1 and step<=5 and attempt then
  self:prune(player,attempt)
  if step~=attempt.step+1 then self.attempts[player]=nil; return end
  attempt.step=step
 end
end
function Social:complete(player)
 local attempt=self.attempts[player]
 if not attempt then return nil end
 self.attempts[player]=nil
 if not self:session(player) or attempt.step~=5 or self.clock()-attempt.started<self.minInterval then return nil end
 if self.rooms and not self.rooms:manualContext(player) then return nil end
 self:prune(player,attempt)
 return attempt.witnesses
end
function Social:award(player,witnesses)
 local session=self:session(player); if not session then return end
 for watcher in witnesses do
  self.economy.addSocial(session.data,'spectators',watcher.UserId,player.UserId)
 end
end
function Social:remove(player)
 self.attempts[player]=nil
 for _,attempt in self.attempts do attempt.witnesses[player]=nil end
end
return Social
