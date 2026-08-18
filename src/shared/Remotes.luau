--!strict
-- Единая схема связи: клиент сообщает только о завершённом раунде.

local Remotes = {}

Remotes.Names = {
	Folder = "InfiniteChocolateRemotes",
	StateSync = "StateSync",
	RoundComplete = "RoundComplete",
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
	}
end

return Remotes
