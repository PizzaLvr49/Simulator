local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ProfileStore = require(ServerStorage.Modules.Dependancies.ProfileStore)
local PlayerLeaderboard = require(script.Parent.PlayerLeaderboard)

local PlayerProfileStore = ProfileStore.New("PlayerData", {
	Coins = 500,
})

local Profiles = {}
local PlayerDataCache = {}
local LoadingStates = {}
local Leaderstats = {}

local ProfileLoadTimeOut = 10

local function PlayerAdded(player: Player)
	local success, profile = pcall(function()
		return PlayerProfileStore:StartSessionAsync("Player_" .. player.UserId, { Steal = false })
	end)

	if not success or not profile then
		if player:IsDescendantOf(Players) then
			player:Kick("Failed to load your data. Please rejoin.")
		end
		LoadingStates[player] = nil
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		PlayerDataCache[player] = nil
		LoadingStates[player] = nil
		if player:IsDescendantOf(Players) then
			player:Kick("Your data was loaded on another server.")
		end
	end)

	if player:IsDescendantOf(Players) then
		Profiles[player] = profile
		LoadingStates[player] = "loaded"
		local dataLoaded = Instance.new("StringValue")
		dataLoaded.Name = "DataLoaded"
		dataLoaded.Parent = player
		
		local leaderstats = Instance.new("Folder", player)
		leaderstats.Name = "leaderstats"
		
		local coinValue = Instance.new("NumberValue", leaderstats)
		coinValue.Name = "Coins"
		coinValue.Value = profile.Data.Coins
		
		Leaderstats[player] = leaderstats
		
	else
		profile:EndSession()
		LoadingStates[player] = nil
	end
	
	profile.OnSave:Connect(function()
		PlayerLeaderboard.UpdateCoins(player, profile.Data.Coins)
	end)
	
end

local function PlayerRemoved(player: Player)
	local profile = Profiles[player]
	if profile then
		profile:EndSession()
		Profiles[player] = nil
	end
	PlayerDataCache[player] = nil
	LoadingStates[player] = nil
end

Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(PlayerRemoved)

local PlayerDataModule = {}

export type PlayerData = {
	GetCoins: (PlayerData) -> number?,
	IncrementCoins: (PlayerData, amount: number?, immediateSave: boolean?) -> number?,
	SetCoins: (PlayerData, amount: number, immediateSave: boolean?) -> number?
}

function PlayerDataModule.GetPlayerDataAsync(player: Player): PlayerData?
	if not player:IsDescendantOf(Players) then
		return
	end

	if LoadingStates[player] == "loading" then
		local startTime = os.time()
		while LoadingStates[player] == "loading" and player:IsDescendantOf(Players) do
			if os.time() - startTime > ProfileLoadTimeOut then
				warn("Timeout waiting for profile to finish loading for player:", player.Name)
				LoadingStates[player] = nil
				return
			end
			task.wait(0.1)
		end
	end

	if PlayerDataCache[player] then
		local profile = Profiles[player]
		if profile and profile:IsActive() then
			return PlayerDataCache[player]
		else
			PlayerDataCache[player] = nil
		end
	end

	LoadingStates[player] = "loading"

	local profile = Profiles[player]
	local startTime = os.time()
	while not profile and player:IsDescendantOf(Players) do
		if os.time() - startTime > ProfileLoadTimeOut then
			warn("Timeout waiting for profile to load for player:", player.Name)
			LoadingStates[player] = nil
			return
		end
		task.wait(0.1)
		profile = Profiles[player]
	end

	if not profile or not profile:IsActive() then
		warn("Profile is not active for player:", player.Name)
		LoadingStates[player] = nil
		return
	end

	local selfData = {}

	function selfData:GetCoins()
		if not profile:IsActive() then
			warn("Attempted to access inactive profile for GetCoins:", player.Name)
			return
		end
		return profile.Data.Coins
	end

	function selfData:IncrementCoins(amount, immediateSave)
		local inc = amount or 1
		return self:SetCoins(profile.Data.Coins + inc, immediateSave)
	end

	function selfData:SetCoins(amount, immediateSave)
		if not profile:IsActive() then
			warn("Attempted to access inactive profile for SetCoins:", player.Name)
			return
		end

		local amount = math.max(0, amount)

		profile.Data.Coins = amount
		Leaderstats[player]:FindFirstChild("Coins").Value = amount

		if immediateSave then
			profile:Save()
			PlayerLeaderboard.UpdateCoins(player, amount)
		end

		return profile.Data.Coins
	end

	PlayerDataCache[player] = selfData
	LoadingStates[player] = "loaded"
	return selfData
end

function PlayerDataModule.GetCoinLeaderboardAsync(amount: number, refreshTime: number, leaderboardType: string?)
	local result = {}
	for position, Data in ipairs(PlayerLeaderboard.GetCoinLeaderboard(amount, refreshTime, leaderboardType)) do
		local success, nameResult = pcall(function()
			return Players:GetNameFromUserIdAsync(Data.key)
		end)
		local name
		if success then
			name = nameResult
		else
			warn("Error getting player name: " .. nameResult)
			name = Data.key
		end
		result[position] = {
			Username = name,
			Coins = Data.value
		}
	end 
	return result
end

function PlayerDataModule.IsDataLoaded(player: Player)
	local profile = Profiles[player]
	return profile ~= nil and profile:IsActive() or false
end

function PlayerDataModule.ForceCleanupPlayer(player: Player)
	PlayerDataCache[player] = nil
	LoadingStates[player] = nil
end

ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
	warn("ProfileStore critical state:", isCritical)
end)

ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
	warn("ProfileStore error for store", storeName, "key", profileKey, ":", message)
end)

ProfileStore.OnOverwrite:Connect(function(storeName: string, profileKey: string)
	warn("Profile overwritten for store", storeName, "key", profileKey)
end)

return PlayerDataModule