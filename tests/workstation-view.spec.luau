--!nonstrict
-- Считаем реальные вызовы перемещения, сохраняя те же видимые позы во всех
-- фазах. Это проверяет экономию работы, не подменяя её обещанием роста FPS.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local Config=require('../src/shared/Config'); local Recipe=require('../src/shared/Recipe')
local Action=require('../src/client/WorkstationAction')
local Knife=luau.load(fs.readFile('src/client/KnifeMotion.luau'),{environment={Vector3=R.Vector3,CFrame=R.CFrame},injectGlobals=true})()
local Actor=luau.load(fs.readFile('src/client/ChocolatierAnimator.luau'),{environment={
 game={GetService=function() return {} end},script={Parent={}},require=function() return {} end,
},injectGlobals=true})()
local function model()
 local m={moves=0,attributes={},part={IsA=function() return true end}}
 function m:Clone() return model() end
 function m:GetAttribute(k) return self.attributes[k] end
 function m:SetAttribute(k,v) self.attributes[k]=v end
 function m:GetDescendants() return {self.part} end
 function m:PivotTo(cf) self.frame=cf; self.moves+=1 end
 return m
end
local modules={Config=Config,KnifeMotion=Knife,ChocolatierAnimator={new=function() return {step=function() end} end}}
local Station=luau.load(fs.readFile('src/client/WorkstationView.luau'),{environment={
 game={GetService=function() return {WaitForChild=function() return {Config='Config'} end} end},
 script={Parent={ChocolatierAnimator='ChocolatierAnimator',KnifeMotion='KnifeMotion'}},require=function(id) return modules[id] end,
 Instance={new=model},Vector2=R.Vector2,Vector3=R.Vector3,CFrame=R.CFrame,
},injectGlobals=true})()
local slides=Recipe.build(Config.Recipe).slides
local function station()
 local pieces={}; for _,name in Config.Trick.pieceOrder do pieces[name]=model() end
 local view={tileWidth=66,tileHeight=104,scene3D={intact=model(),pieces=pieces,knife=model()}}
 return Station.new(view,{},R.Vector3.zero,0,false)
end
return function(h)
 h.test('станция не двигает скрытые куски при резке и неподвижные модели на паузе',function()
  local s=station(); local a=Action.cycle(.1,Config,slides)
  for _=1,120 do s:pose(a,true,1/60) end
  for _,m in s.parts do h.equals(m.moves,0) end
  h.equals(s.knife.moves,1)
  a=Action.cycle(.5,Config,slides)
  for _=1,120 do s:pose(a,true,1/60) end
  for _,m in s.parts do h.equals(m.moves,1) end
 end)
 h.test('все видимые части сохраняют исходную траекторию и догоняют позу после скрытия',function()
  local s=station(); local unit=Config.Scene3D.unitsPerPixel*Config.Scene3D.renderScale
  for i=0,100 do
   local a=Action.cycle(i/101,Config,slides)
   s:pose(a,true,.01)
   for name,m in s.parts do
    h.equals(m.part.Transparency,if a.whole then 1 else 0)
    if not a.whole then
     local o=a.offsets[name]; local target=s.origin+R.Vector3.new(o.X*66*unit,0,o.Y*104*unit)
     h.near((m.frame.Position-target).Magnitude,0)
    end
   end
  end
  local a=Action.cycle(.7,Config,slides); a.hidden={upperLeft=true}
  local part=s.parts.upperLeft; local before=part.moves
  s:pose(a,true,.01); h.equals(part.moves,before); h.equals(part.part.Transparency,1)
  a.hidden=nil; s:pose(a,true,.01); h.equals(part.part.Transparency,0)
  local o=a.offsets.upperLeft; h.near((part.frame.Position-s.origin-R.Vector3.new(o.X*66*unit,0,o.Y*104*unit)).Magnitude,0)
 end)
 h.test('видимость аватара применяется один раз и заново при загрузке другого rig',function()
  local writes=0; local values={}
  local part=setmetatable({},{__index=values,__newindex=function(_,k,v) values[k]=v; writes+=1 end})
  local attributes=0
  local parent={SetAttribute=function() attributes+=1 end}
  local actor=setmetatable({rig={},rest={[part]=.35},parent=parent},Actor)
  for _=1,120 do actor:setVisible(true) end
  h.equals(writes,1); h.equals(part.Transparency,.35); h.equals(attributes,1)
  actor:setVisible(false); h.equals(writes,2); h.equals(part.Transparency,1)
  actor.rig={}; actor:setVisible(false); h.equals(writes,3)
  actor:setVisible(true); h.equals(writes,4); h.equals(part.Transparency,.35)
 end)
end
