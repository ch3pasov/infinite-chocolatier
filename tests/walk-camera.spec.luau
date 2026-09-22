-- Проверяем направление движения и границы камеры независимо от графики.
local R=require('@lune/roblox'); local luau=require('@lune/luau'); local fs=require('@lune/fs')
local function signal()
 local s={}
 function s:Connect(fn) self.fn=fn; return {Disconnect=function() self.fn=nil end} end
 function s:fire(...) if self.fn then self.fn(...) end end
 return s
end
local function setup()
 local input={MouseBehavior=R.Enum.MouseBehavior.Default,GetFocusedTextBox=function(self) return self.focused end}
 for _,name in {'InputBegan','InputChanged','InputEnded','WindowFocusReleased','TextBoxFocused'} do input[name]=signal() end
 local gui={MenuIsOpen=false,MenuOpened=signal()}
 local run={BindToRenderStep=function(self,_,_,fn) self.tick=fn end,UnbindFromRenderStep=function(self) self.tick=nil end}
 local camera={}; local world={CurrentCamera=camera}
 local services={UserInputService=input,RunService=run,Workspace=world,GuiService=gui}
 local module=luau.load(fs.readFile('src/client/WalkCamera.luau'),{environment={
  game={GetService=function(_,name) return services[name] end},Enum=R.Enum,Vector3=R.Vector3,CFrame=R.CFrame,
 },injectGlobals=true})()
 local root={Position=R.Vector3.new(5,3,10)}
 local player={Character={FindFirstChild=function() return root end}}
 local enabled=true
 local controller=module.new(player,camera,function() return enabled end)
 return controller,camera,input,world,run,root,function(v) enabled=v end,gui
end
return function(h)
 h.test('прогулка: меню Roblox сразу освобождает мышь и не сохраняет движение стика',function()
  local c,_,input,_,run,_,_,gui=setup()
  local right={UserInputType=R.Enum.UserInputType.MouseButton2}
  local stick={UserInputType=R.Enum.UserInputType.Gamepad1,KeyCode=R.Enum.KeyCode.Thumbstick2,Position=R.Vector3.new(0,1,0)}
  input.InputBegan:fire(right,false); input.InputChanged:fire(stick,false)
  h.equals(input.MouseBehavior,R.Enum.MouseBehavior.LockCurrentPosition); h.equals(c.stick,1)
  gui.MenuIsOpen=true; gui.MenuOpened:fire()
  h.equals(input.MouseBehavior,R.Enum.MouseBehavior.Default); h.equals(c.stick,0)
  local pitch,distance=c.pitch,c.distance
  input.InputBegan:fire(right,false)
  input.InputChanged:fire(stick,false)
  input.InputChanged:fire({UserInputType=R.Enum.UserInputType.MouseWheel,Position=R.Vector3.new(0,0,2)},false)
  run.tick(1)
  h.equals(c.pitch,pitch); h.equals(c.distance,distance); h.equals(input.MouseBehavior,R.Enum.MouseBehavior.Default)
  gui.MenuIsOpen=false; run.tick(1); h.equals(c.pitch,pitch)
  input.InputBegan:fire(right,false)
  input.InputChanged:fire({UserInputType=R.Enum.UserInputType.MouseMovement,Delta=R.Vector3.new(0,10,0)},false)
  h.equals(c.pitch,pitch+2)
  c:destroy(); h.equals(gui.MenuOpened.fn,nil); h.equals(input.TextBoxFocused.fn,nil)
 end)
 h.test('прогулка: фокус текста немедленно отменяет мышь и пальцы без ожидания нового кадра',function()
  local c,_,input=setup()
  input.InputBegan:fire({UserInputType=R.Enum.UserInputType.MouseButton2},false)
  local touch={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.zero}
  input.InputBegan:fire(touch,false)
  input.focused={}; input.TextBoxFocused:fire(input.focused)
  h.equals(input.MouseBehavior,R.Enum.MouseBehavior.Default); h.equals(next(c.touches),nil)
  input.focused=nil; touch.Position=R.Vector3.new(0,50,0); input.InputChanged:fire(touch,false)
  h.equals(c.pitch,30,'старый палец не захватывает камеру после закрытия текста')
  input.InputBegan:fire(touch,false); touch.Position=R.Vector3.new(0,60,0); input.InputChanged:fire(touch,false)
  h.equals(c.pitch,32)
 end)
 h.test('прогулка: приближение и наклон сохраняют направление к столам и третье лицо',function()
  local c,camera,_,_,_,root=setup()
  for _,pitch in {-1000,10,1000} do for _,zoom in {-1000,5,1000} do
   c:adjust(pitch,zoom); c:step(0)
   h.near(camera.CFrame.LookVector.X,0); assert(camera.CFrame.LookVector.Z<0)
   assert(c.pitch>=25 and c.pitch<=70)
   assert((camera.CFrame.Position-camera.Focus.Position).Magnitude>=7.999)
   assert((camera.CFrame.Position-camera.Focus.Position).Magnitude<=32.001)
  end end
  root.Position+=R.Vector3.new(10,0,-5); c:step(0)
  h.near(camera.Focus.Position.X,root.Position.X); h.near(camera.Focus.Position.Z,root.Position.Z)
 end)
 h.test('прогулка: мышь не вращает азимут; выход и потеря фокуса освобождают курсор',function()
  local c,camera,input,world,run,_,enabled=setup()
  local right={UserInputType=R.Enum.UserInputType.MouseButton2}
  input.InputBegan:fire(right,false)
  input.InputChanged:fire({UserInputType=R.Enum.UserInputType.MouseMovement,Delta=R.Vector3.new(1000,25,0)},false)
  h.equals(c.pitch,35); c:step(0); h.near(camera.CFrame.LookVector.X,0)
  input.WindowFocusReleased:fire(); h.equals(input.MouseBehavior,R.Enum.MouseBehavior.Default)
  input.InputBegan:fire(right,false); enabled(false); run.tick(0)
  h.equals(input.MouseBehavior,R.Enum.MouseBehavior.Default)
  local before=camera.CFrame; world.CurrentCamera={}; c:step(.1); h.equals(camera.CFrame,before)
  c:destroy(); h.equals(run.tick,nil); h.equals(input.InputChanged.fn,nil)
 end)
 h.test('прогулка: интерфейс не управляет камерой, два пальца меняют масштаб',function()
  local c,_,input=setup()
  local wheel={UserInputType=R.Enum.UserInputType.MouseWheel,Position=R.Vector3.new(0,0,2)}
  input.InputChanged:fire(wheel,true); h.equals(c.distance,24)
  input.InputChanged:fire(wheel,false); h.equals(c.distance,21)
  local a={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(0,0,0)}
  local b={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(100,0,0)}
  input.InputBegan:fire(a,false); input.InputBegan:fire(b,false)
  b.Position=R.Vector3.new(200,0,0); input.InputChanged:fire(b,false)
  h.equals(c.distance,17); h.equals(c.pitch,30)
  input.InputEnded:fire(b); a.Position=R.Vector3.new(0,50,0); input.InputChanged:fire(a,false)
  h.equals(c.pitch,40)
 end)
end
