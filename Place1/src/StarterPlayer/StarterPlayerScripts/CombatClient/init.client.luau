-- Fist combat client entry point.
-- Animates every combatant (ProceduralAnimator), handles input/prediction, movement, effects
-- and the HUD.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Remotes = Combat:WaitForChild("Remotes")

local Animator = require(Combat:WaitForChild("ProceduralAnimator"))
local VFX = require(Combat:WaitForChild("VFX"))
local SFX = require(Combat:WaitForChild("SFX"))

local CameraFX = require(script.CameraFX)
local HUD = require(script.HUD)
local Movement = require(script.MovementController)
local CombatController = require(script.CombatController)
local FXHandler = require(script.FXHandler)

local actionRemote = Remotes:WaitForChild("Action")

local ctx = {
	Animator = Animator,
	VFX = VFX,
	SFX = SFX,
	CameraFX = CameraFX,
	HUD = HUD,
	Movement = Movement,
	CombatController = CombatController,
	FX = FXHandler,
	Remotes = { Action = actionRemote, FX = Remotes:WaitForChild("FX") },
}

function ctx.Send(action, payload)
	actionRemote:FireServer(action, payload)
end

-- Every combatant gets a procedural rig + fist trails as soon as its body exists.
local function track(model)
	task.spawn(function()
		if not (model:WaitForChild("HumanoidRootPart", 10) and model:WaitForChild("Torso", 10)) then
			return
		end
		for _, part in ipairs({ "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
			model:WaitForChild(part, 5)
		end
		-- joints can arrive a moment after the parts
		local torso = model:FindFirstChild("Torso")
		for _, joint in ipairs({ "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }) do
			torso:WaitForChild(joint, 5)
		end
		model.HumanoidRootPart:WaitForChild("RootJoint", 5)
		if model.Parent and Animator.Get(model) then
			VFX.EnsureTrails(model)
		end
	end)
end

Animator.Start()
SFX.Preload()
CameraFX.Start()
Movement.Start(ctx)
CombatController.Start(ctx)
FXHandler.Start(ctx)
HUD.Start(ctx)

for _, model in ipairs(CollectionService:GetTagged("Combatant")) do
	track(model)
end
CollectionService:GetInstanceAddedSignal("Combatant"):Connect(track)
CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(function(model)
	Animator.Remove(model)
end)
