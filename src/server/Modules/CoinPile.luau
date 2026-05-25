local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local PlayerData = require(ServerStorage.Modules.PlayerData)

local CoinPile = {}
local activePiles = {}

local PileSizes = {"Small", "Medium", "Large"}
local PileValues = {
	Small = 150,
	Medium = 200,
	Large = 250
}

local coinsPerClick = 50
local spawnInterval = 1
local maxPilesPerZone = 18
local paddingMultiplier = 1.25

local pileBounds = {}

local function initializePileBounds()
	for _, size in ipairs(PileSizes) do
		local model = ServerStorage.Assets.CoinPiles:FindFirstChild(size)
		if model then
			local _, boundsSize = model:GetBoundingBox()
			pileBounds[size] = {
				X = boundsSize.X * paddingMultiplier,
				Z = boundsSize.Z * paddingMultiplier,
				Y = boundsSize.Y / 2
			}
		end
	end
end

local function getRandomPileSize()
	return PileSizes[math.random(#PileSizes)]
end

local function isPositionValid(position, bounds, existingPiles, newPositions)
	local currentRadius = math.max(bounds.X, bounds.Z) / 2

	for _, pile in ipairs(existingPiles) do
		if pile.Model and pile.Model.Parent then
			local existingBounds = pileBounds[pile.Model.Name] or bounds
			local existingRadius = math.max(existingBounds.X, existingBounds.Z) / 2
			local minDistance = currentRadius + existingRadius + 3

			local dx = position.X - pile.Position.X
			local dz = position.Z - pile.Position.Z
			local distance = math.sqrt(dx*dx + dz*dz)

			if distance < minDistance then
				return false
			end
		end
	end

	for _, posData in ipairs(newPositions) do
		local otherBounds = pileBounds[posData.size]
		local otherRadius = math.max(otherBounds.X, otherBounds.Z) / 2
		local minDistance = currentRadius + otherRadius + 3

		local dx = position.X - posData.position.X
		local dz = position.Z - posData.position.Z
		local distance = math.sqrt(dx*dx + dz*dz)

		if distance < minDistance then
			return false
		end
	end

	return true
end

local function isWithinZoneBounds(position, bounds, zoneSize, zoneCenter)
	local halfZoneX = zoneSize.X / 2
	local halfZoneY = zoneSize.Y / 2
	local pileRadius = math.max(bounds.X, bounds.Z) / 2
	local buffer = pileRadius + 1

	return position.X - buffer >= zoneCenter.X - halfZoneX and
		position.X + buffer <= zoneCenter.X + halfZoneX and
		position.Z - buffer >= zoneCenter.Z - halfZoneY and
		position.Z + buffer <= zoneCenter.Z + halfZoneY
end

local function generateOptimalPositions(zoneSize, zoneCenter, existingPiles, maxPositions)
	local positions = {}
	local attempts = 0
	local maxAttempts = 2000

	if zoneSize.X <= 0 or zoneSize.Y <= 0 then
		return positions
	end

	while #positions < maxPositions and attempts < maxAttempts do
		attempts += 1

		local pileSize = getRandomPileSize()
		local bounds = pileBounds[pileSize]
		local pileRadius = math.max(bounds.X, bounds.Z) / 2

		local availableWidth = zoneSize.X - (pileRadius * 2 + 2)
		local availableHeight = zoneSize.Y - (pileRadius * 2 + 2)

		if availableWidth <= 0 or availableHeight <= 0 then
			break
		end

		local x = zoneCenter.X + (math.random() - 0.5) * availableWidth
		local z = zoneCenter.Z + (math.random() - 0.5) * availableHeight
		local position = Vector3.new(x, bounds.Y, z)

		if isWithinZoneBounds(position, bounds, zoneSize, zoneCenter)
			and isPositionValid(position, bounds, existingPiles, positions) then
			table.insert(positions, {position = position, size = pileSize})
		end
	end

	return positions
end

local function createPileScaleTween(scaleValue)
	local spawnTween = TweenService:Create(scaleValue, TweenInfo.new(0.1), {Value = 1})
	spawnTween:Play()
	return scaleValue
end

local function updatePileUI(pile)
	local display = pile.Model.HealthDisplay
	local fill = display.Holder.Bar.Fill
	local textLabel = display.Holder.Text

	display.Enabled = pile.CoinsLeft ~= pile.TotalCoins

	local healthRatio = pile.CoinsLeft / pile.TotalCoins
	local sizeTween = TweenService:Create(fill, TweenInfo.new(0.25), {Size = UDim2.fromScale(healthRatio, 1)})
	local colorTween = TweenService:Create(fill, TweenInfo.new(0.25), {
		BackgroundColor3 = Color3.fromHSV((healthRatio / 359) * 120, 180 / 255, 1)
	})

	sizeTween:Play()
	colorTween:Play()
	textLabel.Text = string.format("%d / %d", pile.CoinsLeft, pile.TotalCoins)
end

local function createClickAnimation(scaleValue)
	local scaleUpTween = TweenService:Create(scaleValue, TweenInfo.new(0.05), {Value = 0.9})
	local scaleDownTween = TweenService:Create(scaleValue, TweenInfo.new(0.05), {Value = 1})

	scaleUpTween:Play()
	scaleUpTween.Completed:Connect(function()
		task.wait(0.05)
		scaleDownTween:Play()
	end)

	return scaleDownTween
end

local function removePileFromActive(targetPile)
	for i, pile in ipairs(activePiles) do
		if pile == targetPile then
			table.remove(activePiles, i)
			break
		end
	end
end

local function handlePileClick(pile, player, scaleValue, pileSize, position, parent)
	if pile.IsFinished then return end

	local playerData = PlayerData.GetPlayerDataAsync(player)
	playerData:IncrementCoins(coinsPerClick)
	pile.CoinsLeft -= coinsPerClick

	updatePileUI(pile)

	local scaleDownTween = createClickAnimation(scaleValue)

	if pile.CoinsLeft <= 0 then
		pile.IsFinished = true
		scaleDownTween.Completed:Connect(function()
			pile.Model:Destroy()
			removePileFromActive(pile)
			-- Auto-respawn removed
		end)
	end
end

function CoinPile.SpawnPile(pileSize, position, parent)
	local pileModel = ServerStorage.Assets.CoinPiles:FindFirstChild(pileSize)
	if not pileModel then return end

	local newPileModel = pileModel:Clone()
	newPileModel.Parent = parent or workspace.CoinPiles
	newPileModel:MoveTo(position)

	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = 0.1
	scaleValue.Changed:Connect(function()
		newPileModel.Model:ScaleTo(scaleValue.Value)
	end)

	createPileScaleTween(scaleValue)

	local pile = {
		Model = newPileModel,
		Position = position,
		TotalCoins = PileValues[pileSize],
		CoinsLeft = PileValues[pileSize],
		IsFinished = false
	}

	updatePileUI(pile)

	local clickDetector = newPileModel.ClickDetector
	clickDetector.MouseClick:Connect(function(player)
		handlePileClick(pile, player, scaleValue, pileSize, position, parent)
	end)

	table.insert(activePiles, pile)
	return pile
end

function CoinPile.CreateZone(position, size)
	local zonePart = Instance.new("Part")
	zonePart.Name = "ZonePart"
	zonePart.Material = Enum.Material.SmoothPlastic
	zonePart.TopSurface = Enum.SurfaceType.Smooth
	zonePart.Color = Color3.new(1, 1, 1)
	zonePart.Anchored = true
	zonePart.Size = Vector3.new(size.X, 0.5, size.Y)
	zonePart.BottomSurface = Enum.SurfaceType.Smooth
	zonePart.CanCollide = false
	zonePart.Transparency = 0.5
	zonePart.Position = Vector3.new(position.X, 0.25, position.Y)
	zonePart.Parent = workspace.CoinPiles

	local zoneCenter = Vector3.new(position.X, 0, position.Y)
	local lastSpawnTime = 0

	local connection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()

		if currentTime - lastSpawnTime >= spawnInterval then
			lastSpawnTime = currentTime

			local activePilesInZone = {}
			for _, pile in ipairs(activePiles) do
				if pile.Model and pile.Model.Parent == zonePart then
					table.insert(activePilesInZone, pile)
				end
			end

			local currentPileCount = #activePilesInZone

			if currentPileCount < maxPilesPerZone then
				local neededPiles = maxPilesPerZone - currentPileCount
				local positions = generateOptimalPositions(size, zoneCenter, activePilesInZone, neededPiles)

				for i = 1, #positions do
					CoinPile.SpawnPile(positions[i].size, positions[i].position, zonePart)
				end
			end
		end
	end)

	return function()
		if connection then
			connection:Disconnect()
		end
	end
end

initializePileBounds()

return CoinPile
