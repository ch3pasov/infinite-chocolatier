--!nonstrict
-- Задержка портрета управляется отдельно от обновления списка: уход игрока
-- может произойти между запросом картинки и ответом Roblox.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local Queue=require('../src/shared/CafeQueue')
local function signal()
 local listeners={}
 return {Connect=function(_,fn) listeners[fn]=true; return {Disconnect=function() listeners[fn]=nil end} end,
  Fire=function(_,...) for fn in listeners do fn(...) end end}
end
local function fixture()
 local objects,jobs,requests,records,visits={},{},{},{},{}; local now=0
 local function new(class)
  local x={ClassName=class,Activated=signal(),IsLoaded=false}
  function x:GetChildren() local out={}; for _,o in objects do if o.Parent==self then table.insert(out,o) end end; return out end
  function x:IsA(name) return name=='GuiObject' or name==self.ClassName end
  function x:GetPropertyChangedSignal() return signal() end
  function x:Destroy() for _,o in self:GetChildren() do o:Destroy() end; self.Parent=nil; self.destroyed=true end
  table.insert(objects,x); return x
 end
 local stub=setmetatable({},{__index=function(_,key) return key end})
 local models={GetChildren=function() return records end}
 local services={Workspace={FindFirstChild=function() return models end},
  Players={GetUserThumbnailAsync=function(_,id)
   table.insert(requests,id); local image,ready=coroutine.yield()
   if image=='ERROR' then error('temporary thumbnail failure') end
   return image,ready
  end},
  RunService={Heartbeat=signal()},UserInputService={InputBegan=signal()},
  ReplicatedStorage={WaitForChild=function() return stub end}}
 local theme=setmetatable({},{__index=function() return R.Color3.new() end})
 local modules={CafeQueue=Queue,Theme=theme,Localization={set=function(object,text,args) object.Text=text; object.args=args end,number=tostring}}
 local Directory=luau.load(fs.readFile('src/client/CafeDirectory.luau'),{environment={
  game={GetService=function(_,name) return services[name] end},script={Parent=stub},require=function(name) return modules[name] end,
  Instance={new=new},Enum=R.Enum,UDim=R.UDim,UDim2=R.UDim2,Vector2=R.Vector2,
  task={spawn=function(fn) local co=coroutine.create(fn); table.insert(jobs,co); assert(coroutine.resume(co)) end},
  os={clock=function() return now end},
 },injectGlobals=true})()
 local player={UserId=1,GetAttribute=function(self) return self.visiting end}
 local remote={OnClientEvent=signal(),FireServer=function(_,id) table.insert(visits,id) end}
 local kitchen={player=player,opened=true,gui={Parent={}},atelier={remotes={cafeVisit=remote}},
  controls={Disable=function() end,Enable=function() end}}
 local directory=Directory.new(kitchen)
 local function add(id,name,count)
  local model={OwnerId=id,DisplayName=name,Username='user'..id,CafeCount=count or 0,CafeIndex=0,OwnerOnline=true}
  function model:GetAttribute(key) return self[key] end
  table.insert(records,model); return model
 end
 local function finish(index,image,ready) assert(coroutine.resume(jobs[index],image or 'image',ready~=false)) end
 return directory,add,requests,finish,visits,remote,player,function(dt) now+=dt end
end
return function(h)
 h.test('неготовый портрет повторяется с паузой без пересоздания карточки',function()
  local d,add,requests,finish,_,_,_,advance=fixture()
  add(2,'Alice'); d:open(); local row=d.rows[2]
  d:refresh(); h.equals(#requests,1,'запрос уже выполняется')
  finish(1,'placeholder',false); advance(14); d:refresh(); h.equals(#requests,1)
  advance(1); d:refresh(); h.equals(#requests,2); h.equals(d.rows[2],row)
  finish(2,'ERROR'); d:refresh(); h.equals(#requests,2)
  advance(15); d:refresh(); h.equals(#requests,3); h.equals(d.rows[2],row)
  finish(3,'ready'); advance(100); d:refresh(); h.equals(#requests,3)
  h.equals(row.portrait.Image,'ready'); d:destroy()
 end)
 h.test('список кафе сохраняет карточки, прокрутку и портреты при покупках и повторном открытии',function()
  local d,add,requests,finish=fixture()
  add(1,'Me'); local a=add(2,'Alice',3); add(3,'Bob',4)
  d:open()
  -- Находим по имени, не полагаясь на внутренний порядок GUI-детей.
  local function row(id) for _,r in d.scroll:GetChildren() do if r.Name=='Cafe_'..id then return r end end end
  local alice=row(2); local bob=row(3); assert(alice and bob); h.equals(#requests,2)
  finish(1,'alice'); finish(2,'bob'); d.scroll.CanvasPosition=R.Vector2.new(0,48)
  a.CafeCount=20; a.DisplayName='Алиса'; d:refresh()
  h.equals(row(2),alice); h.equals(row(3),bob); h.equals(#requests,2)
  h.equals(d.scroll.CanvasPosition,R.Vector2.new(0,48))
  local function child(parent,name) for _,c in parent:GetChildren() do if c.Name==name then return c end end end
  h.equals(child(alice,'Name').Text,'Алиса'); h.equals(child(alice,'Factory').args.count,'21')
  h.equals(child(child(alice,'Avatar'),'Initial').Text,'А')
  d:close(); d:open(); h.equals(row(2),alice); h.equals(#requests,2)
  d:destroy()
 end)
 h.test('поздний портрет ушедшего игрока не оживляет старую карточку и визит проверяет свежий список',function()
  local d,add,requests,finish,visits,remote=fixture()
  local a=add(2,'Alice'); add(3,'Bob'); d:open()
  local old=d.rows[2]; a.OwnerOnline=false; d:refresh()
  assert(old.frame.destroyed); h.equals(d.rows[2],nil)
  d:visit(2); h.equals(#visits,0)
  a.OwnerOnline=true; d:refresh(); local current=d.rows[2]; assert(current~=old)
  h.equals(#requests,3); finish(1,'obsolete'); h.equals(current.portrait.Image,nil)
  finish(3,'current'); h.equals(current.portrait.Image,'current')
  d:visit(2); h.equals(visits[1],2); d:visit(3); h.equals(#visits,1,'двойной клик не отправляет второй визит')
  a.OwnerOnline=false; remote.OnClientEvent:Fire('unavailable'); d:visit(2); h.equals(#visits,1)
  local bob=d.rows[3]; d:destroy(); finish(2,'late-bob'); h.equals(bob.portrait.Image,nil)
 end)
end
