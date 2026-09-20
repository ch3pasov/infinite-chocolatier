--!nonstrict
local R=require('@lune/roblox')
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local Knife=luau.load(fs.readFile('src/client/KnifeMotion.luau'),{environment={CFrame=R.CFrame,Vector3=R.Vector3},injectGlobals=true})()
return function(h)
 h.test('кончик большого ножа остаётся на разрезе при любом наклоне',function()
  for _,size in {1,2.2} do
   local settings={knifeScale=size,renderScale=.25,unitsPerPixel=.02}
   for _,direction in {R.Vector3.new(1,0,-1),R.Vector3.new(0,0,1),R.Vector3.new(1,0,0)} do
    for _,roll in {-65,-12} do
     local point=R.Vector3.new(5,.18,8)
     local frame=Knife.frame(point,direction,settings,math.rad(roll))
     local tip=frame:PointToWorldSpace(R.Vector3.new(0,0,-.86*size*.25))
     assert((tip-point).Magnitude<.00001)
     local grip=Knife.grip(frame,settings)
     assert((grip-tip).Magnitude>.4*size)
    end
   end
  end
 end)
end
