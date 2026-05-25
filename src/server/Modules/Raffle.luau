local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

type RaffleData = {
	TotalTickets: number,
	PlayerTickets: {[string]: number},
	StartTime: number,
	IsActive: boolean
}

local RaffleDuration = 600
local raffleMemoryStore = MemoryStoreService:GetMemoryStore("RaffleSystem")
local currentRaffleId: string = ""
local raffleEndConnection: RBXScriptConnection? = nil

local RaffleSystem = {}

function RaffleSystem.startNewRaffle(): ()
	if raffleEndConnection then
		raffleEndConnection:Disconnect()
	end

	currentRaffleId = HttpService:GenerateGUID(false)

	local raffleData: RaffleData = {
		TotalTickets = 0,
		PlayerTickets = {},
		StartTime = tick(),
		IsActive = true
	}

	local success, error = pcall(function()
		raffleMemoryStore:SetAsync(currentRaffleId, raffleData, RaffleDuration + 60)
	end)

	if not success then
		warn("Failed to create raffle: " .. tostring(error))
		return
	end

	print("New raffle started: " .. currentRaffleId)

	task.spawn(function()
		task.wait(RaffleDuration)
		RaffleSystem.endRaffle()
	end)
end

function RaffleSystem.getRaffleData(): RaffleData?
	local success, raffleData = pcall(function()
		return raffleMemoryStore:GetAsync(currentRaffleId)
	end)

	if success and raffleData then
		return raffleData
	end

	return nil
end

function RaffleSystem.selectWinner(raffleData: RaffleData): string?
	if raffleData.TotalTickets == 0 then
		return nil
	end

	local winningTicket = math.random(1, raffleData.TotalTickets)
	local currentCount = 0

	for playerId, ticketCount in pairs(raffleData.PlayerTickets) do
		currentCount = currentCount + ticketCount
		if winningTicket <= currentCount then
			return playerId
		end
	end

	return nil
end

function RaffleSystem.awardPrize(winnerId: string): ()
	print("Awarding prize to player: " .. winnerId)
end

function RaffleSystem.endRaffle(): ()
	local raffleData = RaffleSystem.getRaffleData()

	if not raffleData or not raffleData.IsActive then
		return
	end

	raffleData.IsActive = false

	local updateSuccess = pcall(function()
		raffleMemoryStore:SetAsync(currentRaffleId, raffleData, 300)
	end)

	if not updateSuccess then
		warn("Failed to update raffle end status")
	end

	if raffleData.TotalTickets > 0 then
		local winnerId = RaffleSystem.selectWinner(raffleData)

		if winnerId then
			local winner = Players:GetPlayerByUserId(tonumber(winnerId))
			local winnerName = winner and winner.Name or "Unknown Player"

			print("Raffle " .. currentRaffleId .. " ended!")
			print("Winner: " .. winnerName .. " (ID: " .. winnerId .. ")")
			print("Winning tickets: " .. raffleData.PlayerTickets[winnerId])
			print("Total tickets: " .. raffleData.TotalTickets)

			RaffleSystem.awardPrize(winnerId)
		else
			print("No winner could be determined")
		end
	else
		print("Raffle ended with no participants")
	end

	task.wait(5)
	RaffleSystem.startNewRaffle()
end

function RaffleSystem.AddTickets(player: Player, ticketCount: number): boolean
	if ticketCount <= 0 then
		return false
	end

	local success, raffleData = pcall(function()
		return raffleMemoryStore:GetAsync(currentRaffleId)
	end)

	if not success or not raffleData or not raffleData.IsActive then
		return false
	end

	local playerId = tostring(player.UserId)
	raffleData.PlayerTickets[playerId] = (raffleData.PlayerTickets[playerId] or 0) + ticketCount
	raffleData.TotalTickets = raffleData.TotalTickets + ticketCount

	local updateSuccess, updateError = pcall(function()
		raffleMemoryStore:SetAsync(currentRaffleId, raffleData, RaffleDuration + 60)
	end)

	if updateSuccess then
		print(player.Name .. " added " .. ticketCount .. " tickets. Total: " .. raffleData.PlayerTickets[playerId])
		return true
	else
		warn("Failed to add tickets: " .. tostring(updateError))
		return false
	end
end

function RaffleSystem.GetPlayerTickets(player: Player): number
	local raffleData = RaffleSystem.getRaffleData()

	if not raffleData then
		return 0
	end

	return raffleData.PlayerTickets[tostring(player.UserId)] or 0
end

function RaffleSystem.GetTotalTickets(): number
	local raffleData = RaffleSystem.getRaffleData()

	if not raffleData then
		return 0
	end

	return raffleData.TotalTickets
end

function RaffleSystem.GetTimeRemaining(): number
	local raffleData = RaffleSystem.getRaffleData()

	if not raffleData or not raffleData.IsActive then
		return 0
	end

	local elapsed = tick() - raffleData.StartTime
	return math.max(0, RaffleDuration - elapsed)
end

function RaffleSystem.Initialize(): ()
	RaffleSystem.startNewRaffle()
end

return RaffleSystem