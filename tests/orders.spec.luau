--!nonstrict
local Economy=require("../src/shared/Economy")
local Orders=require("../src/shared/Orders")
local Config=require("../src/shared/Config")
return function(h)
	h.test("заказы начисляют бонус один раз и переходят к следующей коробке",function()
		local d=Economy.load(nil)
		for index,spec in Config.Orders do
			for i=1,spec.rounds do
				local amount,complete=Economy.round(d)
				h.equals(amount,1+(if i==spec.rounds then spec.bonusRounds else 0))
				h.equals(complete~=nil,i==spec.rounds)
			end
			h.equals(d.ordersCompleted,index); h.equals(d.orderProgress,0)
		end
		h.equals(Economy.snapshot(d).order.name,Config.Orders[1].name)
		h.equals(d.slices,22); h.equals(d.rounds,18)
	end)
	h.test("вход и офлайн не выдают награду за заказ и сохраняют неполную коробку",function()
		local d=Economy.load({levels={workers=1}})
		Economy.round(d); Economy.round(d); Economy.round(d)
		d=Economy.load(d); Economy.tick(d,3600)
		h.equals(d.ordersCompleted,0); h.equals(d.orderProgress,3)
		local amount=Economy.round(d); h.equals(amount,2)
		d=Economy.load(d); h.equals(d.ordersCompleted,1); h.equals(d.orderProgress,0)
		local before=d.slices; Economy.load(d); h.equals(d.slices,before)
	end)
	h.test("престиж обнуляет коробку, но сохраняет выполненные заказы и звание",function()
		local d=Economy.load({earned=5000,rounds=150,ordersCompleted=20,orderProgress=3})
		assert(Economy.prestige(d)); h.equals(d.orderProgress,0); h.equals(d.ordersCompleted,20)
		local rank,nextRank=Orders.rank(d.rounds)
		h.equals(rank.name,"Chocolate artisan"); h.equals(nextRank.rounds,500)
		h.equals(Orders.rank(5000).name,"Infinite chocolatier")
	end)
	h.test("повреждённый прогресс заказа не выдаёт готовую награду при загрузке",function()
		for _,raw in {{ordersCompleted=math.huge,orderProgress=0/0},{ordersCompleted=-4,orderProgress=-5},{ordersCompleted=1,orderProgress=999}} do
			local d=Economy.load(raw); local spec=Orders.spec(d.ordersCompleted)
			assert(d.orderProgress>=0 and d.orderProgress<spec.rounds)
			h.equals(d.slices,0)
		end
		local d=Economy.load({orderProgress=3,stars=20}); d.ignorePrestige=true
		h.equals(Economy.snapshot(d).order.bonus,1)
		h.equals(Economy.round(d),2)
	end)
end
