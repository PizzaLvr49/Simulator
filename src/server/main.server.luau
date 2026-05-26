local ServerStorage = game:GetService("ServerStorage")

local CoinPile = require(ServerStorage.Modules.CoinPile)

local _cleanup = CoinPile.CreateZone(Vector3.new(0, 0, 0), Vector2.new(75, 50))
