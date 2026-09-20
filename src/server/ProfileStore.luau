--!strict
-- Аренда записи не даёт двум серверам затереть прогресс при быстром входе.
-- Неудачная загрузка не превращается в пустой профиль с последующей записью.
local ProfileStore = {}
ProfileStore.__index = ProfileStore

function ProfileStore.new(store, economy, settings, token, now)
	return setmetatable({ store = store, economy = economy, settings = settings, token = token, now = now }, ProfileStore)
end

-- Версия 2 не даёт старому серверу записать профиль без полей коллекции.
function ProfileStore:claim(key)
	local offline = 0
	local now = self.now()
	local record = self.store:UpdateAsync(key, function(old)
		if type(old) == "table" and old.version and old.version > 2 then return nil end
		if type(old) == "table" and old.owner and old.owner ~= self.token
			and type(old.expires) == "number" and old.expires > now then return nil end
		local data = self.economy.load(if type(old) == "table" then old.data else nil)
		local savedAt = if type(old) == "table" and type(old.savedAt) == "number" then old.savedAt else now
		offline = self.economy.tick(data, math.clamp(now - savedAt, 0, self.settings.offlineLimit))
		return { version = 2, owner = self.token, expires = now + self.settings.leaseSeconds, savedAt = now, data = data }
	end)
	if not record or record.owner ~= self.token then return nil end
	return self.economy.load(record.data), offline
end

function ProfileStore:save(key, data, release)
	local now = self.now()
	-- Снимок делается до сетевого запроса: callback UpdateAsync может повториться.
	local snapshot = self.economy.load(data)
	local written = false
	self.store:UpdateAsync(key, function(old)
		written = false
		if type(old) ~= "table" or old.owner ~= self.token then return nil end
		written = true
		return { version = 2, owner = if release then nil else self.token,
			expires = if release then 0 else now + self.settings.leaseSeconds,
			savedAt = now, data = snapshot }
	end)
	return written
end

return ProfileStore
