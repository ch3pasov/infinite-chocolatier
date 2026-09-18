--!nonstrict
-- Исполняем жизненный цикл комнаты: коллизии существуют до появления аватара,
-- чужие запросы не меняют режим соседа, повторное появление сохраняет режим.
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local R=require('@lune/roblox')
local function signal()
 local callbacks={}
 return {Connect=function(_,fn) table.insert(callbacks,fn) end,Fire=function(_,...) for _,fn in callbacks do fn(...) end end}
end
return function(h)
 h.test('соседние кухни, возрождение и переиспользование места после выхода',function()
  local world=R.Instance.new('Folder'); local delayed={}
  local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
  local remote={OnServerEvent=signal()}
  local Rooms=luau.load(fs.readFile('src/server/KitchenRooms.luau'),{environment={
   game={GetService=function(_,name) return if name=='Players' then players else world end},
   Instance=R.Instance,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,
   task={spawn=function(fn) fn() end,delay=function(_,fn) table.insert(delayed,fn) end},
  },injectGlobals=true})()
  Rooms.start(remote)
  local function player(id)
   local p={UserId=id,Parent=true,CharacterAdded=signal()}
   function p:SetAttribute(k,v) self[k]=v end
   function p:LoadCharacterAsync()
    assert(#world:GetChildren()>0,'спавн без пола')
    local root={}; local hum={Died=signal()}
    local body={Transparency=.2,CanCollide=true,Parent=true,IsA=function(_,kind) return kind=='BasePart' end}; self.body=body
    self.Character={WaitForChild=function() return root end,FindFirstChild=function() return root end,
     GetDescendants=function() return {body} end,FindFirstChildOfClass=function() return hum end,PivotTo=function(_,cf) self.position=cf.Position end}
    self.CharacterAdded:Fire(self.Character); self.root=root; self.hum=hum
    -- Движок завершает размещение после CharacterAdded.
    self.position=R.Vector3.zero; root.Anchored=false
   end
   players.PlayerAdded:Fire(p); return p
  end
  local a,b=player(1),player(2)
  h.equals(a.root.Anchored,true); h.equals(b.root.Anchored,true)
  h.equals(a.body.Transparency,1); h.equals(a.body.CanCollide,false)
  assert((a.KitchenOrigin-b.KitchenOrigin).Magnitude==24)
  remote.OnServerEvent:Fire(a,'walk'); h.equals(a.root.Anchored,false); h.equals(b.root.Anchored,true)
  h.near(a.body.Transparency,.2); h.equals(a.body.CanCollide,true)
  remote.OnServerEvent:Fire(a,'bogus'); h.equals(a.root.Anchored,false)
  a.hum.Died:Fire(); delayed[1](); h.equals(a.root.Anchored,false)
  h.near((a.position-(a.KitchenOrigin+R.Vector3.new(0,3,8))).Magnitude,0)
  remote.OnServerEvent:Fire(a,'watch'); h.equals(a.root.Anchored,true)
  players.PlayerRemoving:Fire(a); h.equals(#world:GetChildren(),2)
  local c=player(3); h.equals(c.KitchenOrigin,a.KitchenOrigin)
  players.PlayerRemoving:Fire(c)
  players.PlayerRemoving:Fire(b); h.equals(#world:GetChildren(),1)
  assert(world.SharedKitchenHall:FindFirstChild('Foundation'),'пол гостей должен пережить уход владельца')
 end)
end
