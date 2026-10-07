--!strict
--[[
	LoadoutServer (ServerScriptService): gives every player a loadout and changes it when they ask.

	Client -> server (Loadout.Remote:FireServer):
		"Set", slot, ability     put an ability in a slot ("" empties it); if it was in another slot
		                         the two swap
		"Preset", name           a whole preset (Loadout.Presets)
	The loadout is the "Loadout" attribute on the Player; the ability servers check it with
	Loadout.has before letting anything be cast. It can't change mid-attack or while stunned.
]]

if not script:IsDescendantOf(game:GetService("ServerScriptService")) then
	return -- still in the package's folders: it only runs from ServerScriptService
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Folder = ReplicatedStorage:WaitForChild("Loadout")
local Loadout = require(Folder:WaitForChild("Loadout")) :: any
local Remote = Folder:WaitForChild("Remote") :: RemoteEvent

local CombatFolder = ReplicatedStorage:FindFirstChild("Combat")
local CombatModule = CombatFolder and CombatFolder:FindFirstChild("Combat")
local Combat = if CombatModule and CombatModule:IsA("ModuleScript") then require(CombatModule) :: any else nil

local function locked(player: Player): boolean
	local character = player.Character
	return Combat ~= nil and character ~= nil and (Combat.isBusy(character) or Combat.isStunned(character))
end

local function apply(player: Player, slots: { string })
	player:SetAttribute("Loadout", Loadout.format(slots))
end

Remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if locked(player) then
		return
	end
	if action == "Set" then
		local slot = if typeof(a) == "number" then math.floor(a) else 0
		if slot < 1 or slot > #Loadout.Slots or a ~= slot then
			return
		end
		if typeof(b) ~= "string" or (b ~= "" and Loadout.Abilities[b] == nil) then
			return
		end
		apply(player, Loadout.place(Loadout.get(player), slot, b))
	elseif action == "Preset" then
		local preset = if typeof(a) == "string" then Loadout.Presets[a] else nil
		if preset then
			apply(player, Loadout.parse(table.concat(preset, ",")))
		end
	end
end)

local function onPlayer(player: Player)
	if player:GetAttribute("Loadout") == nil then
		apply(player, Loadout.parse(table.concat(Loadout.Presets[Loadout.Default], ",")))
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
