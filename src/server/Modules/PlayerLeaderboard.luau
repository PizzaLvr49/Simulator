local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local PlayerLeaderboard = {}
local LeaderboardCache = {}

local coinsDataStore = DataStoreService:GetOrderedDataStore("CoinsLeaderboard", "allTime")
local dailyCoinsDataStore = DataStoreService:GetOrderedDataStore("CoinsLeaderboard", "daily")
local weeklyCoinsDataStore = DataStoreService:GetOrderedDataStore("CoinsLeaderboard", "weekly")
local monthlyCoinsDataStore = DataStoreService:GetOrderedDataStore("CoinsLeaderboard", "monthly")
local playerDataStore = DataStoreService:GetDataStore("PlayerData")

local function getDayStart()
	local now = DateTime.now():ToLocalTime()
	return DateTime.fromLocalTime(now.Year, now.Month, now.Day, 0, 0, 0).UnixTimestamp
end

local function getWeekStart()
	local now = DateTime.now()
	local localTime = now:ToLocalTime()

	local currentWeekday = tonumber(os.date("%w", now.UnixTimestamp))
	local daysSinceMonday = (currentWeekday == 0) and 6 or (currentWeekday - 1)

	local weekStart = now.UnixTimestamp - (daysSinceMonday * 24 * 60 * 60)
	local weekStartDate = DateTime.fromUnixTimestamp(weekStart):ToLocalTime()

	return DateTime.fromLocalTime(weekStartDate.Year, weekStartDate.Month, weekStartDate.Day, 0, 0, 0).UnixTimestamp
end

local function getMonthStart()
	local now = DateTime.now():ToLocalTime()
	return DateTime.fromLocalTime(now.Year, now.Month, 1, 0, 0, 0).UnixTimestamp
end

local currentDayStart = getDayStart()
local currentWeekStart = getWeekStart()
local currentMonthStart = getMonthStart()
local lastDayCheck = DateTime.now().UnixTimestamp
local lastWeekCheck = DateTime.now().UnixTimestamp
local lastMonthCheck = DateTime.now().UnixTimestamp

local function checkAndResetPeriods()
	local now = DateTime.now().UnixTimestamp

	if now - lastDayCheck > 600 then
		local newDayStart = getDayStart()
		if newDayStart ~= currentDayStart then
			currentDayStart = newDayStart
		end
		lastDayCheck = now
	end

	if now - lastWeekCheck > 600 then
		local newWeekStart = getWeekStart()
		if newWeekStart ~= currentWeekStart then
			currentWeekStart = newWeekStart
		end
		lastWeekCheck = now
	end

	if now - lastMonthCheck > 600 then
		local newMonthStart = getMonthStart()
		if newMonthStart ~= currentMonthStart then
			currentMonthStart = newMonthStart
		end
		lastMonthCheck = now
	end
end

local function getPlayerData(userId)
	local success, data = pcall(function()
		return playerDataStore:GetAsync(tostring(userId))
	end)

	if success and data then
		return data
	else
		return {
			coins = 0,
			dailyTare = 0,
			weeklyTare = 0,
			monthlyTare = 0,
			dailyPeriod = 0,
			weeklyPeriod = 0,
			monthlyPeriod = 0,
			lastUpdate = 0
		}
	end
end

local function savePlayerData(userId, data)
	local success = pcall(function()
		return playerDataStore:SetAsync(tostring(userId), data)
	end)

	if not success then
		warn("Failed to save player data for user", userId)
	end
end

local function calculateEarnings(data, currentAmount, periodStart, periodType)
	if data[periodType .. "Period"] ~= periodStart then
		data[periodType .. "Tare"] = currentAmount
		data[periodType .. "Period"] = periodStart
		return 0
	else
		return math.max(0, currentAmount - data[periodType .. "Tare"])
	end
end

function PlayerLeaderboard.UpdateCoins(player: Player, amount: number)
	if not player or typeof(amount) ~= "number" then
		warn("Invalid parameters for UpdateCoins")
		return
	end

	checkAndResetPeriods()

	local playerData = getPlayerData(player.UserId)
	playerData.coins = amount
	playerData.lastUpdate = DateTime.now().UnixTimestamp

	local dayStart = getDayStart()
	local weekStart = getWeekStart()
	local monthStart = getMonthStart()

	local dailyEarnings = calculateEarnings(playerData, amount, dayStart, "daily")
	local weeklyEarnings = calculateEarnings(playerData, amount, weekStart, "weekly")
	local monthlyEarnings = calculateEarnings(playerData, amount, monthStart, "monthly")

	savePlayerData(player.UserId, playerData)

	local success = pcall(function()
		return coinsDataStore:SetAsync(player.UserId, amount)
	end)
	if not success then
		warn("Failed to update all-time coins leaderboard for player", player.Name)
	end

	success = pcall(function()
		return dailyCoinsDataStore:SetAsync(player.UserId, dailyEarnings)
	end)
	if not success then
		warn("Failed to update daily coins leaderboard for player", player.Name)
	end

	success = pcall(function()
		return weeklyCoinsDataStore:SetAsync(player.UserId, weeklyEarnings)
	end)
	if not success then
		warn("Failed to update weekly coins leaderboard for player", player.Name)
	end

	success = pcall(function()
		return monthlyCoinsDataStore:SetAsync(player.UserId, monthlyEarnings)
	end)
	if not success then
		warn("Failed to update monthly coins leaderboard for player", player.Name)
	end
end

function PlayerLeaderboard.GetCoinLeaderboard(amount: number, refreshTime: number, leaderboardType: string?)
	leaderboardType = leaderboardType or "alltime"

	if type(amount) ~= "number" or type(refreshTime) ~= "number" or amount < 0 or refreshTime < 0 then
		warn("Invalid parameters for GetCoinLeaderboard - Amount:", amount, "RefreshTime:", refreshTime)
		return {}
	end
	if amount == 0 then
		return {}
	end

	checkAndResetPeriods()

	local targetDataStore
	local cacheKey = leaderboardType .. "_" .. tostring(amount)

	if leaderboardType == "daily" then
		targetDataStore = dailyCoinsDataStore
	elseif leaderboardType == "weekly" then
		targetDataStore = weeklyCoinsDataStore
	elseif leaderboardType == "monthly" then
		targetDataStore = monthlyCoinsDataStore
	else
		targetDataStore = coinsDataStore
	end

	if LeaderboardCache[cacheKey] then
		if (DateTime.now().UnixTimestamp - LeaderboardCache[cacheKey].TimeStamp) < refreshTime then
			return LeaderboardCache[cacheKey].Data
		end
	end

	local bestCachedAmount = nil
	local bestCachedData = nil
	for cachedKey, cachedData in pairs(LeaderboardCache) do
		if string.find(cachedKey, leaderboardType .. "_") then
			local cachedAmount = tonumber(string.match(cachedKey, leaderboardType .. "_(%d+)"))
			if cachedAmount and cachedAmount >= amount then
				local success, currentTime = pcall(function()
					return DateTime.now().UnixTimestamp
				end)
				if success and (currentTime - cachedData.TimeStamp) < refreshTime then
					if not bestCachedAmount or cachedAmount < bestCachedAmount then
						bestCachedAmount = cachedAmount
						bestCachedData = cachedData
					end
				end
			end
		end
	end

	if bestCachedData then
		local subset = {}
		for i = 1, math.min(amount, #bestCachedData.Data) do
			subset[i] = bestCachedData.Data[i]
		end
		LeaderboardCache[cacheKey] = {Data = subset, TimeStamp = bestCachedData.TimeStamp}
		return subset
	end

	local clampedAmount = math.clamp(amount, 1, 100)
	local success, pages = pcall(function()
		return targetDataStore:GetSortedAsync(false, clampedAmount)
	end)
	if not success then
		warn("Failed to get sorted leaderboard data:", pages)
		if LeaderboardCache[cacheKey] then
			return LeaderboardCache[cacheKey].Data
		end
		return {}
	end

	local totalData = {}
	local entriesCollected = 0

	while entriesCollected < amount do
		local dataSuccess, data = pcall(function()
			return pages:GetCurrentPage()
		end)

		if not dataSuccess then
			warn("Failed to get current page from leaderboard:", data)
			break
		end

		for _, entry in ipairs(data) do
			if entriesCollected < amount then
				entriesCollected = entriesCollected + 1
				totalData[entriesCollected] = entry
			else
				break
			end
		end

		if entriesCollected < amount then
			local hasNextPage = pcall(function()
				return pages.IsFinished
			end)

			if not hasNextPage or pages.IsFinished then
				break
			end

			local advanceSuccess = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)

			if not advanceSuccess then
				warn("Failed to advance to next page")
				break
			end
		end
	end

	local cacheSize = 0
	for _ in pairs(LeaderboardCache) do
		cacheSize = cacheSize + 1
	end
	if cacheSize >= 15 then
		local oldestTime = math.huge
		local oldestKey = nil
		for key, cachedData in pairs(LeaderboardCache) do
			if cachedData.TimeStamp < oldestTime then
				oldestTime = cachedData.TimeStamp
				oldestKey = key
			end
		end
		if oldestKey then
			LeaderboardCache[oldestKey] = nil
		end
	end

	LeaderboardCache[cacheKey] = {Data = totalData, TimeStamp = DateTime.now().UnixTimestamp}
	return totalData
end

function PlayerLeaderboard.GetPlayerPeriodEarnings(player: Player, leaderboardType: string)
	if not player:IsDescendantOf(Players) then
		warn("Invalid player parameter")
		return 0
	end

	leaderboardType = leaderboardType or "alltime"

	if leaderboardType == "alltime" then
		local success, amount = pcall(function()
			return coinsDataStore:GetAsync(player.UserId)
		end)
		return success and amount or 0
	elseif leaderboardType == "daily" then
		local success, amount = pcall(function()
			return dailyCoinsDataStore:GetAsync(player.UserId)
		end)
		return success and amount or 0
	elseif leaderboardType == "weekly" then
		local success, amount = pcall(function()
			return weeklyCoinsDataStore:GetAsync(player.UserId)
		end)
		return success and amount or 0
	elseif leaderboardType == "monthly" then
		local success, amount = pcall(function()
			return monthlyCoinsDataStore:GetAsync(player.UserId)
		end)
		return success and amount or 0
	end

	return 0
end

return PlayerLeaderboard