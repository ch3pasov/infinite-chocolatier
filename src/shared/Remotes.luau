--!strict
-- Клиент передаёт завершение фокуса и намерение купить, но не цену или доход.

local Remotes = {}

Remotes.Names = {
	Folder = "InfiniteChocolateRemotes",
	StateSync = "StateSync",
	RoundComplete = "RoundComplete",
	RequestState = "RequestState",
	Purchase = "Purchase",
	Prestige = "Prestige",
}

function Remotes.ensure(parent: Instance)
	local folder = parent:FindFirstChild(Remotes.Names.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Remotes.Names.Folder
		folder.Parent = parent
	end

	local function getEvent(name: string): RemoteEvent
		local event = folder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
		return event :: RemoteEvent
	end

	return {
		stateSync = getEvent(Remotes.Names.StateSync),
		roundComplete = getEvent(Remotes.Names.RoundComplete),
		requestState = getEvent(Remotes.Names.RequestState),
		purchase = getEvent(Remotes.Names.Purchase),
		prestige = getEvent(Remotes.Names.Prestige),
	}
end

return Remotes
