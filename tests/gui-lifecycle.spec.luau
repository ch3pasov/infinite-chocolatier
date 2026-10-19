--!nonstrict
-- Сигналы сервисов переживают GUI. Уничтожаем настоящие контроллеры меню
-- вместе с их деревьями и проверяем, что подписки не остаются в сервисах.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local Config=require('../src/shared/Config')
local function signal()
 local handlers={}
 local s={}
 function s:Connect(callback)
  local c={Connected=true,callback=callback}
  function c:Disconnect() self.Connected=false end
  table.insert(handlers,c); return c
 end
 function s:Fire(...) for _,c in table.clone(handlers) do if c.Connected then c.callback(...) end end end
 function s:count() local n=0; for _,c in handlers do if c.Connected then n+=1 end end; return n end
 function s:clear() for _,c in handlers do c:Disconnect() end end
 return s
end
local function instances()
 local objects={}
 local function instance(class)
  local o={ClassName=class,Name=class,AbsoluteSize=R.Vector2.new(800,600),signals={}}
  for _,name in {'Destroying','Activated','Focused'} do o[name]=signal(); table.insert(o.signals,o[name]) end
  function o:GetPropertyChangedSignal() local s=signal(); table.insert(self.signals,s); return s end
  function o:Destroy()
   if self.destroyed then return end
   self.destroyed=true; self.Destroying:Fire()
   for _,child in objects do if child.Parent==self then child:Destroy() end end
   for _,s in self.signals do s:clear() end
   self.Parent=nil
  end
  function o:FindFirstChild(name) for _,child in objects do if child.Parent==self and child.Name==name then return child end end end
  function o:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
  table.insert(objects,o); return o
 end
 return instance
end
local function fixture()
 local instance=instances()
 local input,errorSignal,topbarSignal=signal(),signal(),signal()
 local shared=setmetatable({},{__index=function(_,name) return name end})
 local playerGui=instance('PlayerGui'); local gui=instance('ScreenGui'); gui.Parent=playerGui
 local view={gui=gui,root=instance('Frame'),counter=instance('TextLabel')}; view.root.Parent=gui; view.counter.Parent=view.root
 local services={ReplicatedStorage={WaitForChild=function() return shared end},UserInputService={InputBegan=input},
  GuiService={GetPropertyChangedSignal=function() return topbarSignal end},
  ScriptContext={Error=errorSignal},Players={LocalPlayer={UserId=Config.BalanceTesterUserId}},RunService={IsStudio=function() return true end}}
 local modules={Config=Config,KitchenCatalog=require('../src/shared/KitchenCatalog'),Theme={},
  Localization={set=function(o,text) o.Text=text end,token=function(text) return text end},
  DecorThumbnails={new=function(parent) local o=instance('ViewportFrame'); o.Parent=parent; return o end}}
 local function load(name)
  return luau.load(fs.readFile('src/client/'..name..'.luau'),{environment={
   game={GetService=function(_,key) return services[key] or {} end},script={Parent=shared},
   require=function(key) return modules[key] or {} end,Instance={new=instance},
   Enum=R.Enum,Color3=R.Color3,Vector2=R.Vector2,UDim=R.UDim,UDim2=R.UDim2,
  },injectGlobals=true})()
 end
 modules.Journal=load('Journal')
 local Atelier,Diagnostics=load('Atelier'),load('Diagnostics')
 -- Размеры проверяются отдельно; здесь исполняются создание и очистка меню.
 Atelier.fit=function() end
 local atelier=Atelier.new(gui,view,{})
 local diagnostics=Diagnostics.new(playerGui,view)
 return {gui=gui,playerGui=playerGui,view=view,atelier=atelier,diagnostics=diagnostics,input=input,errors=errorSignal,topbar=topbarSignal}
end
return function(h)
 h.test('серверные снимки больше не обновляют удалённый клиентский интерфейс',function()
  local instance=instances(); local playerGui=instance('PlayerGui')
  local stateSync=signal(); local requests,updates,rewards=0,0,0; local view
  local names=setmetatable({},{__index=function(_,name) return name end})
  local modules={Config={Scene3D={enabled=false}},Remotes=require('../src/shared/Remotes')}
  modules.Game={new=function(gui)
   view={gui=gui,playRewardEffect=function() rewards+=1 end}
   gui.Destroying:Connect(function() view.destroyed=true end); return view
  end}
  modules.Atelier={new=function() return {update=function() updates+=1 end} end}
  modules.Audio={new=function() return {update=function() end} end}
  modules.Diagnostics={new=function() return {update=function() updates+=1 end} end}
  local remotes={StateSync={OnClientEvent=stateSync},RequestState={FireServer=function() requests+=1 end}}
  local services={Players={LocalPlayer={WaitForChild=function() return playerGui end}},
   ReplicatedStorage={WaitForChild=function(_,name)
    if name=='Shared' then return names end
    return {WaitForChild=function(_,key) return remotes[key] or {} end}
   end}}
  luau.load(fs.readFile('src/client/init.client.luau'),{environment={
   game={GetService=function(_,name) return services[name] or {} end},script=names,
   require=function(name) return assert(modules[name],name) end,Instance={new=instance},Enum=R.Enum,
  },injectGlobals=true})()
  h.equals(requests,1); h.equals(stateSync:count(),1)
  stateSync:Fire({reward=4}); h.equals(updates,2); h.equals(rewards,1)
  view.gui:Destroy(); h.equals(stateSync:count(),0)
  stateSync:Fire({reward=4}); h.equals(updates,2); h.equals(rewards,1)
 end)
 h.test('удаление основного GUI убирает отдельные окна и все глобальные подписки меню',function()
  for _,removeReportFirst in {false,true} do
   local f=fixture(); local journal=f.playerGui:FindFirstChild('ChocolateJournal')
   assert(journal); h.equals(f.input:count(),3); h.equals(f.errors:count(),1); h.equals(f.topbar:count(),1)
   local calls=0
   f.atelier.setOpen=function() calls+=1 end; f.atelier.overlay.Visible=true
   f.atelier.journal.close=function() calls+=1 end; f.atelier.journal.overlay.Visible=true
   f.diagnostics.close=function() calls+=1 end; f.diagnostics.overlay.Visible=true
   f.input:Fire({KeyCode=R.Enum.KeyCode.Escape}); h.equals(calls,3)
   if removeReportFirst then
    f.diagnostics.gui:Destroy(); h.equals(f.input:count(),2); h.equals(f.errors:count(),0)
   end
   f.gui:Destroy(); f.gui:Destroy()
   h.equals(journal.destroyed,true); h.equals(f.diagnostics.gui.destroyed,true)
   h.equals(f.input:count(),0); h.equals(f.errors:count(),0); h.equals(f.topbar:count(),0)
   h.equals(f.playerGui:FindFirstChild('ChocolateJournal'),nil)
   h.equals(f.playerGui:FindFirstChild('DeveloperDiagnostics'),nil)
   f.input:Fire({KeyCode=R.Enum.KeyCode.Escape}); h.equals(calls,3)
  end
 end)
end
