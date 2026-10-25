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
  function o:ReleaseFocus() self.focusReleased=true end
  table.insert(objects,o); return o
 end
 return instance
end
local function fixture(withStaff)
 local instance=instances()
 local input,errorSignal,topbarSignal=signal(),signal(),signal()
 local added,removing,staffSignal=signal(),signal(),signal();local requests,timers={},{}
 local staffRemote={OnClientEvent=staffSignal,FireServer=function(_,request) table.insert(requests,request) end}
 local shared=setmetatable({},{__index=function(_,name) return name end})
 local playerGui=instance('PlayerGui'); local gui=instance('ScreenGui'); gui.Parent=playerGui
 local view={gui=gui,root=instance('Frame'),counter=instance('TextLabel')}; view.root.Parent=gui; view.counter.Parent=view.root
 local services={ReplicatedStorage={WaitForChild=function() return shared end},UserInputService={InputBegan=input},
  GuiService={GetPropertyChangedSignal=function() return topbarSignal end},
  ScriptContext={Error=errorSignal},Players={LocalPlayer={UserId=Config.BalanceTesterUserId},PlayerAdded=added,PlayerRemoving=removing},RunService={IsStudio=function() return true end}}
 local modules={Config=Config,KitchenCatalog=require('../src/shared/KitchenCatalog'),Theme={},
  Localization={set=function(o,text) o.Text=text end,token=function(text) return text end,text=function(text) return text end},
  DecorThumbnails={new=function(parent) local o=instance('ViewportFrame'); o.Parent=parent; return o end}}
 local function load(name)
  return luau.load(fs.readFile('src/client/'..name..'.luau'),{environment={
   game={GetService=function(_,key) return services[key] or {} end},script={Parent=shared},
   require=function(key) return modules[key] or {} end,Instance={new=instance},
   Enum=R.Enum,Color3=R.Color3,Vector2=R.Vector2,UDim=R.UDim,UDim2=R.UDim2,
   task={delay=function(seconds,fn) table.insert(timers,{seconds=seconds,fn=fn}) end},
  },injectGlobals=true})()
 end
 modules.Journal=load('Journal')
 modules.StaffPicker=load('StaffPicker')
 local Atelier,Diagnostics=load('Atelier'),load('Diagnostics')
 -- Размеры проверяются отдельно; здесь исполняются создание и очистка меню.
 Atelier.fit=function() end
 local atelier=Atelier.new(gui,view,if withStaff then {staffChoice=staffRemote} else {})
 local diagnostics=Diagnostics.new(playerGui,view)
 return {gui=gui,playerGui=playerGui,view=view,atelier=atelier,diagnostics=diagnostics,input=input,errors=errorSignal,topbar=topbarSignal,
  added=added,removing=removing,staffSignal=staffSignal,requests=requests,
  flush=function() local queue=table.clone(timers);table.clear(timers);for _,timer in queue do if timer.seconds==.3 then timer.fn() end end end}
end
return function(h)
 h.test('меню стажёра отбрасывает старые ответы и объединяет поиск, отправляя только последний выбор',function()
  local f=fixture(true);local picker=f.atelier.staffPicker
  picker:setOpen(true);local stale=picker.request
  picker.query='alice';picker:send('list');f.flush();h.equals(#f.requests,1);h.equals(f.requests[1].query,'alice')
  picker:receive({request=stale,items={{id=1}}});h.equals(#picker.rows,0)
  picker:receive({request=picker.request,page=1,pages=2,total=13,status='ready',selected=7,current=7,
   selectedName={displayName='Alice',name='alice'},items={{id=7,name='alice',displayName='Alice'}}})
  h.equals(#picker.rows,1);picker.rows[1].Activated:Fire();f.flush()
  h.equals(f.requests[2].id,7);h.equals(f.requests[2].action,'select')
  picker:send('select',8);picker:send('select',9);f.flush();h.equals(#f.requests,3);h.equals(f.requests[3].id,9)
  picker.next.Activated:Fire();f.flush();h.equals(f.requests[4].action,'list');h.equals(f.requests[4].page,2)
  picker:setOpen(false);picker:receive({request=picker.request,items={}});h.equals(#picker.rows,1)
 end)
 h.test('закрытие и удаление меню стажёра отменяют отправку и освобождают глобальные подписки',function()
  local f=fixture(true);local picker=f.atelier.staffPicker
  h.equals(f.added:count(),1);h.equals(f.staffSignal:count(),1)
  picker:setOpen(true);picker:setOpen(false);f.flush();h.equals(#f.requests,0)
  picker:setOpen(true);f.gui:Destroy();f.flush();h.equals(#f.requests,0)
  h.equals(f.added:count(),0);h.equals(f.removing:count(),0);h.equals(f.staffSignal:count(),0)
 end)
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
