--!strict
--[[
	CombatServer (ServerScriptService): the F key for every player, and the guard filling back up.

	Client -> server (Combat.Remote:FireServer):
		"Block", true     F pressed: block, and open the parry window unless a parry was just tried
		                  and missed (Settings.ParryCooldown) - holding F still blocks
		"Block", false    F let go
	See Combat for the rules and the attributes it keeps on each character.
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Folder = ReplicatedStorage:WaitForChild("Combat")
local Combat = require(Folder:WaitForChild("Combat")) :: any
local Remote = Folder:WaitForChild("Remote") :: RemoteEvent

local lastParry: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function block(character: Model, on: boolean)
	if not on then
		Combat.setBlocking(character, false)
		return
	end
	if not Combat.alive(character) or Combat.isStunned(character) or Combat.isBusy(character) then
		return
	end
	local now = Combat.now()
	local last = lastParry[character]
	local fresh = last == nil
		or now - last >= Combat.Settings.ParryCooldown
		or character:GetAttribute("ParrySucceeded") == true
	Combat.setBlocking(character, true)
	if fresh then
		lastParry[character] = now
		character:SetAttribute("ParrySucceeded", false)
		Combat.openParry(character)
	end
end

Remote.OnServerEvent:Connect(function(player: Player, action: any, value: any)
	local character = player.Character
	if not character then
		return
	end
	if action == "Block" and typeof(value) == "boolean" then
		block(character, value)
	end
end)

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			Combat.setBlocking(character, false)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

RunService.Heartbeat:Connect(function(dt: number)
	Combat.step(dt)
end)
