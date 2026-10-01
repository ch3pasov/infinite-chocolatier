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
 local now=0; local failedIds={}; local hooks={}
 local function instance(class)
  local o={ClassName=class,Name=class,Destroying=signal(),Activated=signal(),InputBegan=signal(),Ended=signal(),IsLoaded=false,IsPlaying=false,IsPaused=false,
   AbsolutePosition=R.Vector2.zero,AbsoluteSize=R.Vector2.new(200,36),plays=0,stops=0,attributes={}}
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
  function o:Play() self.plays+=1; self.IsPlaying=true; self.IsPaused=false end
  function o:Pause() self.IsPlaying=false; self.IsPaused=true end
  function o:Resume() self.IsPlaying=true; self.IsPaused=false end
  function o:Stop() self.stops+=1; self.IsPlaying=false; self.IsPaused=false end
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
 local input={WindowFocusReleased=signal(),InputBegan=signal(),InputChanged=signal(),InputEnded=signal()}; local menus={MenuOpened=signal()}
 local soundService=instance("SoundService")
 local starter={enabled=true,GetCoreGuiEnabled=function(self) return self.enabled end,
  SetCoreGuiEnabled=function(self,_,value) self.enabled=value end}
 local services={SoundService=soundService,UserInputService=input,GuiService=menus,StarterGui=starter,
  ContentProvider={PreloadAsync=function(_,list)
   if #list==1 and hooks.preload then local hook=hooks.preload; hooks.preload=nil; hook() end
   for _,s in list do s.IsLoaded=not failedIds[s.SoundId] end
  end},
  ReplicatedStorage={WaitForChild=function() return {Config="Config"} end}}
 local Audio=luau.load(fs.readFile("src/client/Audio.luau"),{environment={
  game={GetService=function(_,key) return assert(services[key],key) end},
  require=function(key)
   if key=="Config" then return Config end
   if key=="Localization" then return {set=function(label,text) label.Text=text end} end
   return {}
  end,
  script={Parent={Theme="Theme",Localization="Localization"}},Instance={new=instance},Enum=R.Enum,
  UDim=R.UDim,UDim2=R.UDim2,Vector2=R.Vector2,os={clock=function() return now end},
  task={spawn=function(callback) table.insert(spawned,callback) end,
   delay=function(_,callback) table.insert(delayed,callback) end},
 },injectGlobals=true})()
 local view={cancelled=0,endDrag=function(self,cancelled) assert(cancelled); self.cancelled+=1; self.drag=nil end}
 view.onOverlayChanged=function() view.overlayRefreshes=(view.overlayRefreshes or 0)+1 end
 local audio=Audio.new(gui,view)
 return {audio=audio,view=view,starter=starter,gui=gui,playerGui=playerGui,button=button,input=input,menus=menus,objects=objects,
  instance=instance,failedIds=failedIds,hooks=hooks,advance=function(dt) now+=dt end,
  loadOne=function() table.remove(spawned,1)() end,
  load=function() local n=0; while #spawned>0 do n+=1; assert(n<100,"загрузка зациклилась"); table.remove(spawned,1)() end end,
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
  h.equals(f.audio.sounds.cutMotion,nil)
  for _=1,1000 do f.audio:play("slide") end
  h.equals(f.audio.sounds.slide.plays,1); h.equals(#f.objects,count)
  f.advance(.25); f.audio:play("slide"); h.equals(f.audio.sounds.slide.plays,2)
  f.audio:stopMotion(); h.equals(f.audio.sounds.slide.IsPlaying,false)
  f.flush(); h.equals(f.audio.sounds.slide.IsPlaying,false)
 end)
 h.test("старый таймер не обрывает новый звук после отключения и включения",function()
  local f=fixture(); f.load(); f.audio:play("slide")
  f.audio:setVolume("effects",0); h.equals(f.audio.groups.effects.Volume,0)
  h.equals(f.audio.sounds.slide.IsPlaying,false); h.equals(f.audio:play("reward"),false)
  f.advance(.3); f.audio:setVolume("effects",.7)
  f.audio:play("slide"); local sound=f.audio.sounds.slide
  local before=sound.stops
  -- Первый таймер устарел; отдельный новый голос продолжает играть.
  f.flushOne(); h.equals(sound.stops,before); h.equals(sound.IsPlaying,true)
  f.flush(); h.equals(sound.IsPlaying,false)
  h.equals(f.audio.gui.attributes.effectsVolume,.7)
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
  h.equals(f.input.InputChanged:count(),0); h.equals(f.input.InputEnded:count(),0); h.equals(f.input.InputBegan:count(),0)
  h.equals(f.button.Activated:count(),0); f.load(); f.flush()
  h.equals(f.audio:play("cut"),false)
 end)
 h.test("музыка и эффекты независимы, выключение музыки не перематывает запись",function()
  local f=fixture(); f.load(); local a=f.audio
  h.equals(a.music.Looped,false); h.equals(a.music.plays,1)
  a.music.TimePosition=45
  a:setVolume("effects",0); h.equals(a.groups.music.Volume,Config.Audio.defaults.music)
  h.equals(a.music.IsPlaying,true); h.equals(a:play("cut"),false)
  a:setVolume("effects",.42); a:setVolume("music",0)
  h.equals(a.groups.effects.Volume,.42); h.equals(a:play("cut"),true)
  a:setVolume("music",.65); h.equals(a.music.plays,1); h.equals(a.music.TimePosition,45)
  h.equals(a.groups.effects.Volume,.42); h.equals(a.rows.music.value.Text,"65%")
  a:setVolume("music",100); h.equals(a.groups.music.Volume,1)
  a:setVolume("effects",-10); h.equals(a.groups.effects.Volume,0)
  a:setVolume("music",0/0); h.equals(a.groups.music.Volume,1)
 end)
 h.test("загрузка музыки после установки нуля не включает её до поднятия громкости",function()
  local f=fixture(); f.audio:setVolume("music",0); f.load()
  h.equals(f.audio.music.plays,0)
  f.audio:setVolume("music",.25); h.equals(f.audio.music.plays,1)
 end)
 h.test("окно звука временно убирает список игроков и возвращает исходное состояние",function()
  for _,enabled in {true,false} do
   local f=fixture(); f.starter.enabled=enabled
   f.audio:setOpen(true); h.equals(f.starter.enabled,false)
   f.audio:setOpen(true); f.audio:setOpen(false); h.equals(f.starter.enabled,enabled)
   f.audio:setOpen(true); f.audio:destroy(); h.equals(f.starter.enabled,enabled)
  end
 end)
 h.test("ползунок владеет только своим пальцем, меню и потеря фокуса снимают захват",function()
  local f=fixture(); f.load(); local a=f.audio
  f.view.drag={}; a.toggle.Activated:Fire(); h.equals(a.panel.Visible,true)
  h.equals(f.view.audioSettingsOpen,true); h.equals(f.view.cancelled,1)
  h.equals(f.view.overlayRefreshes,1)
  local track=a.rows.music.track; track.AbsolutePosition=R.Vector2.new(10,10); track.AbsoluteSize=R.Vector2.new(100,36)
  local finger={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(35,0,0)}
  track.InputBegan:Fire(finger); h.equals(a.volumes.music,.25)
  local other={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(100,0,0)}
  f.input.InputChanged:Fire(other); f.input.InputEnded:Fire(other); h.equals(a.volumes.music,.25); assert(a.drag)
  finger.Position=R.Vector3.new(85,0,0); f.input.InputChanged:Fire(finger); h.equals(a.volumes.music,.75)
  f.input.InputEnded:Fire(finger); h.equals(a.drag,nil)
  track.InputBegan:Fire(finger); f.input.WindowFocusReleased:Fire()
  h.equals(a.drag,nil); h.equals(a.panel.Visible,false); h.equals(f.view.audioSettingsOpen,false)
  h.equals(f.view.overlayRefreshes,2)
  a:setOpen(true); track.InputBegan:Fire(finger); f.menus.MenuOpened:Fire(); h.equals(a.drag,nil)
  a:setOpen(true); f.input.InputBegan:Fire({KeyCode=R.Enum.KeyCode.Escape}); h.equals(a.panel.Visible,false)
 end)
 h.test("окончание записи запускает следующую, очередь замыкается без новых голосов",function()
  local f=fixture(); f.load(); local a=f.audio; local count=#f.objects
  for index=2,#Config.Audio.music.playlist+1 do
   a.music.IsPlaying=false; a.music.Ended:Fire(); f.load()
   local expected=(index-1)%#Config.Audio.music.playlist+1
   h.equals(a.trackIndex,expected); h.equals(a.music.SoundId,Config.Audio.music.playlist[expected].id)
   h.equals(a.music.IsPlaying,true); h.equals(a.music.Ended:count(),1); h.equals(#f.objects,count)
  end
 end)
 h.test("пауза сохраняет позицию, громкость и переключение не снимают её",function()
  local f=fixture(); f.load(); local a=f.audio
  a.music.TimePosition=42; a.pause.Activated:Fire()
  h.equals(a.music.IsPlaying,false); h.equals(a.paused,true)
  a:setVolume("music",.8); h.equals(a.music.IsPlaying,false)
  a.pause.Activated:Fire(); h.equals(a.music.IsPlaying,true); h.equals(a.music.TimePosition,42); h.equals(a.music.plays,1)
  a:setMusicPaused(true); a.next.Activated:Fire(); f.load()
  h.equals(a.trackIndex,2); h.equals(a.music.IsPlaying,false); h.equals(a.music.TimePosition,0)
  a.previous.Activated:Fire(); f.load(); h.equals(a.trackIndex,1); h.equals(a.paused,true)
  a:setMusicPaused(false); h.equals(a.music.IsPlaying,true)
 end)
 h.test("пауза до загрузки и быстрая смена трека не дают позднего автозапуска",function()
  local f=fixture(); local a=f.audio
  a:setMusicPaused(true); a:selectTrack(3); a:selectTrack(2); f.load()
  h.equals(a.trackIndex,2); h.equals(a.music.plays,0); h.equals(a.musicLoading,false)
  a:setMusicPaused(false); h.equals(a.music.plays,1)
  local oldEnded=a.musicEnded.callback
  a:selectTrack(4); oldEnded(); f.load(); h.equals(a.trackIndex,4); h.equals(a.music.plays,2)
 end)
 h.test("переключение во время сетевой загрузки оставляет только новый трек",function()
  local f=fixture(); local a=f.audio; f.loadOne()
  f.hooks.preload=function() a:selectTrack(3) end
  f.loadOne(); h.equals(a.music.plays,0); h.equals(a.trackIndex,3); h.equals(a.musicLoading,true)
  f.load(); h.equals(a.music.plays,1); h.equals(a.musicLoading,false)
 end)
 h.test("недоступные записи пропускаются, полный отказ останавливает попытки",function()
  local f=fixture(); local a=f.audio
  f.failedIds[Config.Audio.music.playlist[1].id]=true; f.load()
  h.equals(a.trackIndex,2); h.equals(a.music.IsPlaying,true)
  for _,track in Config.Audio.music.playlist do f.failedIds[track.id]=true end
  a:selectTrack(1); f.load(); h.equals(a.trackIndex,#Config.Audio.music.playlist)
  h.equals(a.musicReady,false); h.equals(a.musicLoading,false); h.equals(a.music.IsPlaying,false)
  h.equals(a.trackState.Text,"Music unavailable")
  table.clear(f.failedIds); a.next.Activated:Fire(); f.load()
  h.equals(a.trackIndex,1); h.equals(a.music.IsPlaying,true)
 end)
 h.test("удаление сцены отключает очередь и отменяет незавершённую загрузку",function()
  local f=fixture(); local a=f.audio; local oldEnded=a.musicEnded.callback
  a:destroy(); f.load(); oldEnded()
  h.equals(a.music.Ended:count(),0); h.equals(a.music.plays,0); h.equals(a.trackIndex,1)
 end)

end
