--!nostrict
local R = require('@lune/roblox')
-- Lune хранит настоящие Instance, но не исполняет перемещение моделей движком.
R.implementMethod('Model','PivotTo',function(m,frame)
	local transform=frame*m.WorldPivot:Inverse()
	for _,p in m:GetDescendants() do
		if p:IsA('BasePart') then p.CFrame=transform*p.CFrame end
	end
	m.WorldPivot=frame
end)
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local Config = require('../src/shared/Config')
local Geom = require('../src/shared/Geom')
local Layout = require('../src/client/Layout')
local Recipe = require('../src/shared/Recipe')
local env = {Vector2=R.Vector2,Vector3=R.Vector3,CFrame=R.CFrame}
local function module(path)
	return luau.load(fs.readFile(path),{environment=env,injectGlobals=true})()
end
local Projection=module('src/client/Projection3D.luau')
local Solid=module('src/client/SolidGeometry.luau')
local Motion=module('src/client/Motion3D.luau')
local deps={Config=Config,Geom=Geom,Layout=Layout,Projection3D=Projection,SolidGeometry=Solid,Motion3D=Motion}
local modules=setmetatable({},{__index=function(_,k)return k end})
local sceneEnv=table.clone(env)
sceneEnv.game={GetService=function(_,name) return if name=='ReplicatedStorage' then {WaitForChild=function()return modules end} else {} end}
sceneEnv.Instance=R.Instance
sceneEnv.Color3=R.Color3
sceneEnv.Enum=R.Enum
sceneEnv.script={Parent=modules}
sceneEnv.require=function(name)return assert(deps[name],name) end
local Scene=luau.load(fs.readFile('src/client/Scene3D.luau'),{environment=sceneEnv,injectGlobals=true})()

return function(h)
	local settings=Config.Scene3D
	local recipe=Recipe.build(Config.Recipe)
	local bounds=Layout.bounds(recipe,Config.Trick,66,104,Geom)
	h.test('3D: перспектива и обратный луч совпадают на телефоне и компьютере',function()
		for _,size in {R.Vector2.new(304,340),R.Vector2.new(604,366),R.Vector2.new(740,776),R.Vector2.new(1356,1056)} do
			local camera=Projection.fit(size,bounds,settings)
			for x=-128,330,23 do
				for y=-187,520,31 do
					local original=R.Vector3.new(x*settings.unitsPerPixel,settings.surfaceHeight,y*settings.unitsPerPixel)
					local screen=Projection.project(camera,size,settings.fieldOfView,original)
					assert(screen.X>=0 and screen.X<=size.X and screen.Y>=0 and screen.Y<=size.Y)
					local hit=Projection.unproject(camera,size,settings.fieldOfView,screen,settings.surfaceHeight)
					assert((hit-original).Magnitude<0.0001)
				end
			end
		end
	end)
	h.test('3D: клинья заполняют профиль и сохраняют объём, включая косой срез',function()
		for _,polygon in {Solid.outline(0,0,58,92,6),Geom.clipPolygon(Solid.outline(0,0,58,92,6),{a=R.Vector2.new(0,70),b=R.Vector2.new(58,20)},true)} do
			local volume=0
			for _,w in Solid.prism(polygon,0.2,0.48,0.02) do
				volume += w.size.X*w.size.Y*w.size.Z/2
				-- Три вершины лицевой стороны WedgePart должны оставаться
				-- внутри исходного выпуклого контура, а не зеркалиться наружу.
				for _,yz in {{-1,-1},{-1,1},{1,1}} do
					local world=w.frame:PointToWorldSpace(R.Vector3.new(0,yz[1]*w.size.Y/2,yz[2]*w.size.Z/2))
					local point=R.Vector2.new(world.X/0.02,world.Z/0.02)
					for i,a in polygon do
						local b=polygon[i%#polygon+1]
						assert(Geom.cross(b-a,point-a)>-0.002)
					end
				end
			end
			assert(math.abs(volume-Geom.polygonArea(polygon)*0.02^2*0.28)<0.000001)
		end
	end)
	h.test('3D: физические части не выходят за свои прямые границы',function()
		local self=setmetatable({view={tileWidth=66,tileHeight=104,diagonal={a=R.Vector2.new(0,364),b=R.Vector2.new(330,156)}}},Scene)
		local total=0
		for _,name in Config.Trick.pieceOrder do
			local spec=Config.Trick.pieces[name]
			local polygon=self:clip(Solid.outline(0,0,330,520,0),spec)
			assert(#polygon>=3,name)
			for _,p in polygon do
				assert(p.X>=spec.bounds[1]*66-0.001 and p.X<=spec.bounds[3]*66+0.001,name)
				assert(p.Y>=spec.bounds[2]*104-0.001 and p.Y<=spec.bounds[4]*104+0.001,name)
			end
			total += Geom.polygonArea(polygon)
		end
		-- Единственное превышение площади — прежнее оптическое продолжение.
		assert(math.abs(total-330*520-330*104*Config.Trick.opticalStretchRows)<0.1)
	end)
	h.test('3D: реальные модели проходят сборку и сбор награды без накопления объектов',function()
		local v={tileWidth=66,tileHeight=104,boardWidth=330,boardHeight=520,recipe=recipe,
			diagonal={a=R.Vector2.new(0,364),b=R.Vector2.new(330,156)},pieces={},active='done'}
		for _,key in {'intactLayer','hintLayer','progressLayer','seamLayer'} do v[key]=R.Instance.new('Frame') end
		v.intactLayer.Visible=false
		local self=setmetatable({view=v,world=R.Instance.new('WorldModel'),pieces={},lastOffsets={},hints={},effects={},time=0},Scene)
		self.intact=self:chocolate('WholeBar')
		self.knife=R.Instance.new('Model')
		local count=#self.intact:GetDescendants()
		for _,name in Config.Trick.pieceOrder do
			local spec=Config.Trick.pieces[name]
			local origin=R.Vector2.new(spec.bounds[1]*66,spec.bounds[2]*104)
			local motion=R.Instance.new('Frame')
			motion.Position=R.UDim2.fromOffset(origin.X,origin.Y)
			v.pieces[name]={motion=motion,origin=origin}
			self.pieces[name]=self:chocolate(name,spec)
			count+=#self.pieces[name]:GetDescendants()
		end
		assert(count<5000,`слишком много граней: {count}`)
		self:step(0.016)
		assert(self.pieces.stripSingle.Parent==self.world)
		v.active='collecting'; v.intactLayer.Visible=true
		self:step(0.016); self:step(0.15)
		assert(self.pieces.stripSingle:GetChildren()[2].Transparency>0)
		v.active='exploding'; self:step(0.016)
		for _,p in self.pieces.stripSingle:GetChildren() do h.near(p.Transparency,1) end
		for _=1,60 do
			self:step(0.016)
			assert(self.intact.Parent==self.world)
			for _,m in self.pieces do
				assert(m.Parent==self.world,'модель удалена из сцены')
				for _,p in m:GetChildren() do h.near(p.Transparency,1) end
			end
		end
		v.intactLayer.Visible=false; self:step(0.016)
		for _,m in self.pieces do
			for _,p in m:GetChildren() do h.near(p.Transparency,p:GetAttribute('RestTransparency')) end
		end
		h.equals(#self.effects,0)
		self.world:Destroy(); self.intact:Destroy(); self.knife:Destroy()
		for _,m in self.pieces do m:Destroy() end
	end)

	h.test('3D: обе раскладки обходятся без подъёма и пересечений при переносе',function()
		local self=setmetatable({view={tileWidth=66,tileHeight=104,diagonal={a=R.Vector2.new(0,364),b=R.Vector2.new(330,156)}}},Scene)
		local polygons={}
		for _,name in Config.Trick.pieceOrder do
			polygons[name]=self:clip(Solid.outline(0,0,330,520,0),Config.Trick.pieces[name])
		end
		local function intersects(a,b)
			local result=a
			for i,p in b do result=Geom.clipPolygon(result,{a=p,b=b[i%#b+1]},false) end
			return Geom.polygonArea(result)>0.01
		end
		for mode,layout in settings.layouts do
		for _,phase in {'explode','large','join','strip'} do
			for tick=0,200 do
				local posed={}
				for _,name in Config.Trick.pieceOrder do
					local p=Motion.pose(name,phase,tick/200,layout,recipe.slides,settings.passageY)
					local raw=R.Vector2.new(p.X*66,p.Y*104)
					local offset=Motion.offset(name,raw,phase,settings,recipe.slides,66,104)
					h.near(offset.Y,0)
					local poly={}
					for _,v in polygons[name] do table.insert(poly,v+raw) end
					posed[name]=poly
				end
				for i,a in Config.Trick.pieceOrder do
					for j=i+1,#Config.Trick.pieceOrder do
						local b=Config.Trick.pieceOrder[j]
						-- В исходной нарезке постоянная оптическая кромка скрыта под основанием.
						local sourceSeam=phase=='explode' and tick<60 and a=='base' and (b=='upperLeft' or b=='upperRight')
						if not sourceSeam then
							assert(not intersects(posed[a],posed[b]),`{mode} {phase} {tick}: {a} пересекает {b}`)
						end
					end
				end
			end
		end
		end
	end)

	h.test('3D: переходы маршрута непрерывны, размеры и обратный путь неизменны',function()
		for _,layout in settings.layouts do
			for _,name in Config.Trick.pieceOrder do
				local function pose(phase,t) return Motion.pose(name,phase,t,layout,recipe.slides,settings.passageY) end
				for _,pair in {{'explode','large'},{'large','join'},{'join','strip'}} do
					assert((pose(pair[1],1)-pose(pair[2],0)).Magnitude<0.00001)
				end
				local target=recipe.slides[name] or {dx=0,dy=0}
				assert((pose('strip',1)-R.Vector2.new(target.dx,target.dy)).Magnitude<0.00001)
				for _,phase in {'explode','large','join','strip'} do
					local previous=pose(phase,1)
					for tick=999,0,-1 do
						local current=pose(phase,tick/1000)
						assert((current-previous).Magnitude<0.025,'скачок при отмене')
						previous=current
					end
				end
			end
		end
	end)
	h.test('3D: камера вмещает весь обход в обеих ориентациях',function()
		for mode,layout in settings.layouts do
			local trick=table.clone(Config.Trick)
			trick.exploded=layout
			trick.waypoints={upperRight={{dx=layout.upperRight.dx,dy=settings.passageY},{dx=-3,dy=settings.passageY}}}
			local b=Layout.bounds(recipe,trick,66,104,Geom)
			local size=if mode=='portrait' then R.Vector2.new(304,340) else R.Vector2.new(604,366)
			local camera=Projection.fit(size,b,settings)
			for _,phase in {'explode','large','join','strip'} do
				for tick=0,50 do
					for _,name in Config.Trick.pieceOrder do
						local offset=Motion.pose(name,phase,tick/50,layout,recipe.slides,settings.passageY)
						local spec=Config.Trick.pieces[name]
						local fake=setmetatable({view={tileWidth=66,tileHeight=104,diagonal={a=R.Vector2.new(0,364),b=R.Vector2.new(330,156)}}},Scene)
						for _,p in fake:clip(Solid.outline(0,0,330,520,0),spec) do
							local world=R.Vector3.new((p.X+offset.X*66)*settings.unitsPerPixel,settings.surfaceHeight,(p.Y+offset.Y*104)*settings.unitsPerPixel)
							local screen=Projection.project(camera,size,settings.fieldOfView,world)
							assert(screen.X>=0 and screen.X<=size.X and screen.Y>=0 and screen.Y<=size.Y)
						end
					end
				end
			end
		end
	end)

end
