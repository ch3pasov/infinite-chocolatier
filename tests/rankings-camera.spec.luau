-- Камера стены должна закончить поворот до включения прокрутки, вместить
-- табло на телефоне и не перезаписать камеру при смене режима или персонажа.
local fs=require('@lune/fs');local luau=require('@lune/luau');local R=require('@lune/roblox')
local function fixture()
 local previous={Parent={},CFrame=R.CFrame.new(0,8,20),Focus=R.CFrame.new(0,3,10),FieldOfView=70}
 local world={CurrentCamera=previous}
 local module=luau.load(fs.readFile('src/client/RankingsCamera.luau'),{environment={
  game={GetService=function() return world end},CFrame=R.CFrame,
 },injectGlobals=true})()
 local camera={Parent={},ViewportSize=R.Vector2.new(1280,720)}
 local part={Parent={},Size=R.Vector3.new(7,4.25,.25),Position=R.Vector3.new(-10.25,4.1,13.2)}
 part.CFrame=R.CFrame.new(part.Position)*R.CFrame.Angles(0,math.pi/2,0)
 return module,module.new(camera),world,previous,camera,part
end
return function(h)
 h.test('рейтинг: плавный поворот завершается до разрешения прокрутки',function()
  local _,c,w,previous,camera,part=fixture()
  local original=previous.CFrame
  h.equals(c:open(part),true);h.equals(w.CurrentCamera,camera);h.equals(c:ready(),false)
  h.equals(camera.CFrame,original);h.equals(c:open(part),false)
  c:step(.2);h.equals(c:ready(),false)
  assert((camera.CFrame.Position-original.Position).Magnitude>.1)
  c:step(.3);h.equals(c:ready(),true)
  h.near(camera.CFrame.LookVector:Dot(part.CFrame.ZVector),-1)
  h.equals(previous.CFrame,original,'прогулка сохраняет прежнее состояние')
  c:close();h.equals(w.CurrentCamera,previous);h.equals(c:ready(),false)
 end)
 h.test('рейтинг: все углы табло в кадре, камера остаётся внутри кухни',function()
  local module,_,_,_,_,part=fixture()
  for _,size in {R.Vector2.new(1280,720),R.Vector2.new(873,400),R.Vector2.new(400,873),R.Vector2.new(296,900)} do
   local cf,target,fov=module.pose(part,size)
   assert(cf.Position.X<10.1,'камера вышла за правую стену')
   for _,x in {-part.Size.X/2,part.Size.X/2} do for _,y in {-part.Size.Y/2,part.Size.Y/2} do
    local point=part.CFrame:PointToWorldSpace(R.Vector3.new(x,y,part.Size.Z/2))
    local p=cf:PointToObjectSpace(point);local half=-p.Z*math.tan(math.rad(fov)/2)
    assert(math.abs(p.X)<half*size.X/size.Y*.9 and math.abs(p.Y)<half*.72,'угол вне безопасного кадра')
   end end
   h.near((target-part.Position):Dot(part.CFrame.ZVector),part.Size.Z/2+.02)
  end
 end)
 h.test('рейтинг: смена камеры и исчезновение стены не перехватываются при закрытии',function()
  local _,c,w,_,camera,part=fixture()
  c:open(part);local other={};w.CurrentCamera=other
  h.equals(c:step(.1),false);c:close();h.equals(w.CurrentCamera,other)
  w.CurrentCamera=camera;c:open(part);part.Parent=nil
  h.equals(c:step(.1),false);c:close();c:close()
 end)
 h.test('рейтинг: отмена во время поворота возвращает прежнюю камеру',function()
  local _,c,w,previous,_,part=fixture()
  c:open(part);c:step(.01);c:close();h.equals(w.CurrentCamera,previous)
  c:open(part);previous.Parent=nil;c:close()
  assert(w.CurrentCamera~=previous,'удалённая камера не восстанавливается')
 end)
end
