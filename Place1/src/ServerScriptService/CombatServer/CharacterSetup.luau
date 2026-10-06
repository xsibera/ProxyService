-- Registers player characters with the combat system and guarantees they're R6.
-- The place's avatar type is set to R6, but if a character still spawns as R15 (for example
-- after copying these scripts into a place with different avatar settings) it gets rebuilt as
-- an R6 rig wearing the same avatar.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)

local CharacterSetup = {}

local rebuilding = {}

local function rebuildAsR6(player, character, humanoid)
	if rebuilding[player] then
		return
	end
	rebuilding[player] = true
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(math.max(1, player.UserId))
		end)
	end
	local model
	if ok and description then
		local built, result = pcall(function()
			return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R6)
		end)
		if built then
			model = result
		else
			warn("[CharacterSetup] couldn't build an R6 rig:", result)
		end
	end
	if model and character.Parent then
		model.Name = player.Name
		local old = model:FindFirstChild("Animate")
		if old then
			old:Destroy()
		end
		for _, script in ipairs(StarterPlayer:WaitForChild("StarterCharacterScripts"):GetChildren()) do
			script:Clone().Parent = model
		end
		model:PivotTo(character:GetPivot())
		player.Character = model
		model.Parent = Workspace
		character:Destroy()
	else
		warn("[CharacterSetup] " .. player.Name .. " is not R6; set Avatar Settings > Avatar Type to R6")
	end
	rebuilding[player] = nil
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		task.defer(rebuildAsR6, player, character, humanoid)
		return
	end
	if not character:FindFirstChild("Torso") then
		character:WaitForChild("Torso", 5)
	end
	CombatService.Register(character, { Player = player })
end

function CharacterSetup.Start()
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return CharacterSetup
