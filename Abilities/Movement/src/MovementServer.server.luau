--!strict
--[[
	MovementServer (ServerScriptService): checks rolls and makes them untouchable.

	Sprinting is the client's own business (it only changes the player's walk speed, which the
	player's client already controls); rolls go through here so the dodge is real: the server makes
	the roller intangible to every hit through ReplicatedStorage.Combat, and busy (no attacking or
	blocking mid-roll).

	Client -> server (Movement.Remote:FireServer):  "Roll", direction
	Server -> clients (FireAllClients):  "Roll", player, direction
	Server -> one client: "Denied", secondsLeft
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Movement = ReplicatedStorage:WaitForChild("Movement")
local Config = require(Movement:WaitForChild("Config")) :: any
local Remote = Movement:WaitForChild("Remote") :: RemoteEvent
local Combat = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Combat")) :: any

local SLACK = 0.1 -- seconds of lag allowed on the cooldown
local readyAt: { [Player]: number } = {}

local function flat(v: any): Vector3?
	if typeof(v) ~= "Vector3" or not (v.Magnitude < math.huge) then
		return nil
	end
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else nil
end

local function roll(player: Player, direction: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local dir = flat(direction)
	if not (character and humanoid and humanoid.Health > 0 and dir) then
		return
	end
	local now = Combat.now()
	local left = (readyAt[player] or 0) - now
	if left > SLACK or Combat.isStunned(character) or Combat.isBusy(character) then
		Remote:FireClient(player, "Denied", math.max(left, 0))
		return
	end
	readyAt[player] = now + Config.Roll.Cooldown
	Combat.setBlocking(character, false) -- rolling out of a block lets go of it
	Combat.setIntangible(character, Config.Roll.Intangible)
	Combat.setBusy(character, Config.Roll.Busy)
	Remote:FireAllClients("Roll", player, dir)
end

Remote.OnServerEvent:Connect(function(player: Player, action: any, direction: any)
	if action == "Roll" then
		roll(player, direction)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	readyAt[player] = nil
end)
