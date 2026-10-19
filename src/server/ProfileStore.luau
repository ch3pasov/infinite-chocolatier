--!strict
-- Аренда записи не даёт двум входам затереть прогресс, даже на одном сервере.
-- Неудачная загрузка не превращается в пустой профиль с последующей записью.
local ProfileStore = {}
ProfileStore.__index = ProfileStore

function ProfileStore.new(store, economy, settings, token, now)
	return setmetatable({ store = store, economy = economy, settings = settings, token = token, now = now, pendingClaims = {}, leases = {} }, ProfileStore)
end

-- Срок берётся из подтверждённой записи. Время ожидания ответа уже
-- потрачено и не должно выдавать сессии новую аренду поверх старой.
function ProfileStore:hasLease(key, reserve)
 return (self.leases[key] or 0) - self.now() > (reserve or 0)
end

-- Версия 5 защищает пожизненные социальные множества от старых серверов.
function ProfileStore:claim(key)
	local offline = 0
	local away = { seconds = 0, capped = false }
	local now = self.now()
	local record = self.store:UpdateAsync(key, function(old)
		if type(old) == "table" and old.version and old.version > 5 then return nil end
		if type(old) == "table" and old.owner and old.owner ~= self.token
			and type(old.expires) == "number" and old.expires > now then return nil end
		local data = self.economy.load(if type(old) == "table" then old.data else nil)
		local savedAt = if type(old) == "table" and type(old.savedAt) == "number" then old.savedAt else now
		local elapsed = math.max(0, now - savedAt)
		away = { seconds = math.min(elapsed, self.settings.offlineLimit), capped = elapsed > self.settings.offlineLimit }
		local balance = data.slices
		self.economy.tick(data, away.seconds)
		-- В отчёте показываем полученные дольки, а не сумму сверх предела кошелька.
		offline = math.max(0, data.slices - balance)
		-- UpdateAsync мог записать аренду, но потерять ответ. Своё владение
		-- подтверждает запись; сохраняем первый отчёт, не начисляя его снова.
		-- Чужая/ещё не записанная аренда требует нового расчёта из её данных.
		local pending = self.pendingClaims[key]
		if type(old) == "table" and old.owner == self.token and pending then
			offline = pending.amount
			away = table.clone(pending.report)
		else
			self.pendingClaims[key] = { amount = offline, report = table.clone(away) }
		end
		return { version = 5, owner = self.token, expires = now + self.settings.leaseSeconds, savedAt = now, data = data }
	end)
	-- Только неопределённый сетевой исход оставляет отчёт следующей попытке.
	-- После обычного ответа повторный claim не показывает старую выплату.
	self.pendingClaims[key] = nil
	if not record or record.owner ~= self.token then self.leases[key] = nil; return nil end
	self.leases[key] = record.expires
	return self.economy.load(record.data), offline, away
end

function ProfileStore:save(key, data, release)
	local now = self.now()
	-- Снимок делается до сетевого запроса: callback UpdateAsync может повториться.
	local snapshot = self.economy.load(data)
	local written = false
	local record = self.store:UpdateAsync(key, function(old)
		written = false
		if type(old) ~= "table" or old.owner ~= self.token then return nil end
		written = true
		return { version = 5, owner = if release then nil else self.token,
			expires = if release then 0 else now + self.settings.leaseSeconds,
			savedAt = now, data = snapshot }
	end)
	self.leases[key] = if written and not release and record and record.owner == self.token then record.expires else nil
	return written
end

return ProfileStore
