--!nonstrict
-- Исполняем настоящий контроллер со временем и загрузкой под управлением
-- теста: важны отсутствие поздних наград, накопления голосов и подписок.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local R=require("@lune/roblox")
local Config=require("../src/shared/Config")

local function signal()
 local handlers={}; local s={}
 function s:Connect(callback)
  local c={Connected=true,callback=callback}; function c:Disconnect() self.Connected=false end
  table.insert(handlers,c); return c
 end
 function s:Fire(...) for _,c in table.clone(handlers) do if c.Connected then c.callback(...) end end end
 function s:count() local n=0; for _,c in handlers do if c.Connected then n+=1 end end; return n end
 return s
end

local function fixture()
 local objects,spawned,delayed={},{},{}
 local now=0
 local function instance(class)
  local o={ClassName=class,Name=class,Destroying=signal(),Activated=signal(),IsLoaded=false,plays=0,stops=0,attributes={}}
  function o:IsA(name) return self.ClassName==name or name=="GuiButton" and self.ClassName=="TextButton" end
  function o:FindFirstAncestorWhichIsA(name)
   local p=self.Parent; while p do if p:IsA(name) then return p end; p=p.Parent end
  end
  function o:GetDescendants()
   local out={}; for _,child in objects do local p=child.Parent
    while p do if p==self then table.insert(out,child); break end; p=p.Parent end
   end; return out
  end
  function o:SetAttribute(key,value) self.attributes[key]=value end
  function o:Play() self.plays+=1; self.Playing=true end
  function o:Stop() self.stops+=1; self.Playing=false end
  function o:Destroy()
   if self.destroyed then return end; self.destroyed=true; self.Destroying:Fire()
   for _,child in table.clone(objects) do if child.Parent==self then child:Destroy() end end
   self.Parent=nil
  end
  table.insert(objects,o); return o
 end
 local playerGui=instance("PlayerGui"); playerGui.DescendantAdded=signal()
 local gui=instance("ScreenGui"); gui.Name="InfiniteChocolate"; gui.Parent=playerGui
 local button=instance("TextButton"); button.Parent=gui
 local input={WindowFocusReleased=signal()}; local menus={MenuOpened=signal()}
 local soundService=instance("SoundService")
 local services={SoundService=soundService,UserInputService=input,GuiService=menus,
  ContentProvider={PreloadAsync=function(_,list) for _,s in list do s.IsLoaded=true end end},
  ReplicatedStorage={WaitForChild=function() return {Config="Config"} end}}
 local Audio=luau.load(fs.readFile("src/client/Audio.luau"),{environment={
  game={GetService=function(_,key) return assert(services[key],key) end},
  require=function(key) return if key=="Config" then Config else {} end,
  script={Parent={Theme="Theme"}},Instance={new=instance},Enum=R.Enum,
  UDim=R.UDim,UDim2=R.UDim2,Vector2=R.Vector2,os={clock=function() return now end},
  task={spawn=function(callback) table.insert(spawned,callback) end,
   delay=function(_,callback) table.insert(delayed,callback) end},
 },injectGlobals=true})()
 local audio=Audio.new(gui)
 return {audio=audio,gui=gui,playerGui=playerGui,button=button,input=input,menus=menus,objects=objects,
  instance=instance,advance=function(dt) now+=dt end,
  load=function() for _,callback in spawned do callback() end; table.clear(spawned) end,
  flushOne=function() table.remove(delayed,1)() end,
  flush=function() local list=table.clone(delayed); table.clear(delayed); for _,callback in list do callback() end end}
end

return function(h)
 h.test("аудио не задерживает игру и не проигрывает опоздавший жест после загрузки",function()
  local f=fixture(); h.equals(f.audio:play("cut"),false)
  f.load(); h.equals(f.audio.sounds.cut.plays,0)
  h.equals(f.audio:play("cut"),true); h.equals(f.audio.sounds.cut.plays,1)
 end)
 h.test("частые события движения используют постоянный пул и ограниченную частоту",function()
  local f=fixture(); f.load(); local count=#f.objects
  for _=1,1000 do f.audio:play("cutMotion") end
  h.equals(f.audio.sounds.cutMotion.plays,1); h.equals(#f.objects,count)
  f.advance(.25); f.audio:play("cutMotion"); h.equals(f.audio.sounds.cutMotion.plays,2)
  f.audio:stopMotion(); h.equals(f.audio.sounds.cutMotion.Playing,false)
  f.flush(); h.equals(f.audio.sounds.cutMotion.Playing,false)
 end)
 h.test("старый таймер не обрывает новый звук после отключения и включения",function()
  local f=fixture(); f.load(); f.audio:play("slide")
  f.audio:setEnabled(false); h.equals(f.audio.group.Volume,0)
  h.equals(f.audio.sounds.slide.Playing,false); h.equals(f.audio:play("reward"),false)
  f.advance(.3); f.audio:setEnabled(true)
  f.audio:play("slide"); local sound=f.audio.sounds.slide
  local before=sound.stops
  -- Первый таймер устарел; отдельный новый голос продолжает играть.
  f.flushOne(); h.equals(sound.stops,before); h.equals(sound.Playing,true)
  f.flush(); h.equals(sound.Playing,false)
  h.equals(f.audio.toggle.attributes.SoundEnabled,true)
 end)
 h.test("пассивные снимки и загрузка молчат, ответ сервера подтверждает награду и покупку",function()
  local f=fixture(); f.load()
  for i=1,30 do f.audio:update({ready=true,slices=i,lastOrder={bonus=50}}) end
  f.audio:update({ready=false,reward=10})
  for _,s in f.audio.sounds do h.equals(s.plays,0) end
  f.audio:update({ready=true,reward=3}); h.equals(f.audio.sounds.reward.plays,1)
  f.audio:update({ready=true,notice={key="Purchased {count} upgrades",args={count=10}}})
  h.equals(f.audio.sounds.purchase.plays,1)
  f.audio:update({ready=true,notice={key="Cannot purchase: check your balance and upgrade level"}})
  h.equals(f.audio.sounds.denied.plays,1)
  f.audio:update({ready=true,notice={key="New workshop! +{stars} cocoa stars"}})
  h.equals(f.audio.sounds.prestige.plays,1)
 end)
 h.test("новые игровые кнопки озвучены, удалённые кнопки и сцена освобождают подписки",function()
  local f=fixture(); f.load(); f.button.Activated:Fire(); h.equals(f.audio.sounds.ui.plays,1)
  local kitchen=f.instance("ScreenGui"); kitchen.Name="KitchenExperiment"; kitchen.Parent=f.playerGui
  local nextButton=f.instance("TextButton"); nextButton.Parent=kitchen; f.playerGui.DescendantAdded:Fire(nextButton)
  h.equals(nextButton.Activated:count(),1); nextButton:Destroy(); h.equals(nextButton.Activated:count(),0)
  h.equals(f.audio.buttons[nextButton],nil)
  f.gui:Destroy(); h.equals(f.audio.destroyed,true); h.equals(f.audio.folder.destroyed,true)
  h.equals(f.audio.gui.destroyed,true); h.equals(f.playerGui.DescendantAdded:count(),0)
  h.equals(f.input.WindowFocusReleased:count(),0); h.equals(f.menus.MenuOpened:count(),0)
  h.equals(f.button.Activated:count(),0); f.load(); f.flush()
  h.equals(f.audio:play("cut"),false)
 end)
end
