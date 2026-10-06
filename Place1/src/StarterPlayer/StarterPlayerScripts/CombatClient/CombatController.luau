-- Local combat input + prediction.
--
-- Pressing a button plays the animation, swing sound and lunge immediately (prediction) and
-- asks the server. The server echoes the action with the same sequence number; if it
-- disagrees (different combo index) we correct, and if it rejects we roll back.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)

local CombatController = {}

local player = Players.LocalPlayer
local ctx

local HITS = Config.M1.Hits
local ATTACK_CLIPS = { "Jab", "Cross", "Hook", "Uppercut", "Heavy" }

local s = {
	Seq = 0,
	Combo = 0,
	LastM1End = -math.huge,
	ComboCooldownUntil = 0,
	ActionEnd = 0,
	HitTime = 0,
	ActionKind = nil,
	ActionSeq = nil,
	HeavyCooldownUntil = 0,
	DodgeCooldownUntil = 0,
	BlockHeld = false,
	Blocking = false,
	M1Held = false,
	BufferedAction = nil,
	BufferedAt = 0,
	Predicted = {},
}
CombatController.State = s

local function character()
	return player.Character
end

local function rig()
	local c = character()
	return c and ctx.Animator.Get(c)
end

local function combatState()
	local c = character()
	return c and c:GetAttribute("CombatState") or "Idle"
end

local function stunned()
	local state = combatState()
	return state == "Stunned" or state == "Parried" or state == "GuardBroken" or state == "Dead"
end

local function alive()
	local c = character()
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function CombatController.IsAttacking()
	return os.clock() < s.ActionEnd
end

function CombatController.AttackKind()
	return s.ActionKind
end

function CombatController.IsBlocking()
	return s.Blocking
end

function CombatController.IsBusy()
	return os.clock() < s.ActionEnd or s.Blocking
end

----------------------------------------------------------------------------------------------
-- Prediction

local function nextSeq()
	s.Seq += 1
	return s.Seq
end

local function beginAttack(kind, index, spec)
	local t = os.clock()
	local seq = nextSeq()
	s.ActionKind = kind
	s.ActionSeq = seq
	s.ActionEnd = t + spec.Duration
	s.HitTime = t + spec.Windup
	s.Predicted[seq] = { Kind = kind, Index = index, Anim = spec.Anim }
	ctx.Movement.StopSlide()
	ctx.Movement.AimAssist()
	local r = rig()
	if r then
		r:Play(spec.Anim)
	end
	ctx.Movement.Lunge(spec.Lunge, spec.Windup + 0.05)
	ctx.Send(kind, { Seq = seq })
end

local function tryM1()
	if not alive() or stunned() or s.Blocking or ctx.Movement.IsDodging() then
		return false
	end
	local t = os.clock()
	local readyAt = math.max(s.ActionEnd, s.ComboCooldownUntil)
	if t < readyAt then
		if readyAt - t <= Config.M1.InputBuffer then
			s.BufferedAction, s.BufferedAt = "M1", readyAt
		end
		return false
	end
	if t - s.LastM1End > Config.M1.ComboResetTime then
		s.Combo = 0
	end
	s.Combo = s.Combo % #HITS + 1
	local index = s.Combo
	local spec = HITS[index]
	beginAttack("M1", index, spec)
	s.LastM1End = t + spec.Duration
	if index == #HITS then
		s.Combo = 0
		s.ComboCooldownUntil = t + spec.Duration + Config.M1.ComboEndCooldown
	end
	return true
end

local function tryHeavy()
	if not alive() or stunned() or s.Blocking or ctx.Movement.IsDodging() then
		return false
	end
	local t = os.clock()
	if t < s.HeavyCooldownUntil then
		return false
	end
	if t < s.ActionEnd then
		if s.ActionEnd - t <= Config.M1.InputBuffer then
			s.BufferedAction, s.BufferedAt = "Heavy", s.ActionEnd
		end
		return false
	end
	s.Combo = 0
	s.HeavyCooldownUntil = t + Config.Heavy.Cooldown
	beginAttack("Heavy", 1, Config.Heavy)
	return true
end

local function startBlockVisual()
	if s.Blocking then
		return
	end
	s.Blocking = true
	ctx.Movement.StopSlide()
	ctx.Movement.StopSprint()
	local r = rig()
	if r then
		r:Play("BlockHold")
	end
end

local function stopBlockVisual()
	if not s.Blocking then
		return
	end
	s.Blocking = false
	local r = rig()
	if r then
		r:Stop("BlockHold")
	end
end

local function canBlockNow()
	return alive() and not stunned() and os.clock() >= s.ActionEnd and not ctx.Movement.IsDodging()
end

local function blockPressed()
	s.BlockHeld = true
	ctx.Send("BlockStart")
	if canBlockNow() then
		startBlockVisual()
	end
end

local function blockReleased()
	s.BlockHeld = false
	ctx.Send("BlockEnd")
	stopBlockVisual()
end

local function tryDodge()
	if not alive() or stunned() then
		return false
	end
	local t = os.clock()
	if t < s.DodgeCooldownUntil then
		return false
	end
	if t < s.ActionEnd then
		if not Config.Dodge.CanCancelRecovery or t < s.HitTime then
			return false
		end
		-- dodge-cancel the recovery of a punch
		local r = rig()
		if r and s.ActionSeq and s.Predicted[s.ActionSeq] then
			r:Stop(s.Predicted[s.ActionSeq].Anim, 0.08)
		end
		s.ActionEnd = t
	end
	local dir = ctx.Movement.DodgeDirection()
	if not ctx.Movement.Dodge(dir) then
		return false
	end
	stopBlockVisual()
	s.DodgeCooldownUntil = t + Config.Dodge.Cooldown
	local seq = nextSeq()
	s.Predicted[seq] = { Kind = "Dodge", Dir = dir }
	local c = character()
	ctx.FX.PlayDodge(c, dir)
	ctx.Send("Dodge", { Dir = dir, Seq = seq })
	return true
end

----------------------------------------------------------------------------------------------
-- Server reconciliation (called by FXHandler for events about our own character)

function CombatController.OnOwnAttack(data)
	local predicted = data.Seq and s.Predicted[data.Seq]
	if predicted and predicted.Index == data.Index then
		return true -- already playing
	end
	-- server picked a different hit (or it was queued server-side): follow the server
	local spec = if data.Kind == "Heavy" then Config.Heavy else HITS[data.Index]
	if spec then
		local t = os.clock()
		local r = rig()
		if r then
			for _, name in ipairs(ATTACK_CLIPS) do
				if name ~= spec.Anim then
					r:Stop(name, 0.05)
				end
			end
			r:Play(spec.Anim)
		end
		s.ActionKind = data.Kind
		s.ActionEnd = t + spec.Duration
		s.HitTime = t + spec.Windup
		if data.Kind == "M1" then
			s.Combo = if data.Index >= #HITS then 0 else data.Index
			s.LastM1End = t + spec.Duration
		end
	end
	return true
end

function CombatController.OnReject(data)
	local predicted = data.Seq and s.Predicted[data.Seq]
	if not predicted then
		return
	end
	local r = rig()
	if predicted.Kind == "M1" or predicted.Kind == "Heavy" then
		if r then
			r:Stop(predicted.Anim, 0.08)
		end
		if s.ActionSeq == data.Seq then
			s.ActionEnd = 0
			s.ActionKind = nil
		end
		s.Combo = 0
		if predicted.Kind == "Heavy" then
			s.HeavyCooldownUntil = 0
		end
	end
	s.Predicted[data.Seq] = nil
end

-- Our action got interrupted (hit, parried, guard broken).
function CombatController.OnInterrupted(releaseBlock)
	s.ActionEnd = 0
	s.ActionKind = nil
	s.BufferedAction = nil
	s.Combo = 0
	stopBlockVisual()
	if releaseBlock then
		s.BlockHeld = false
	end
	local r = rig()
	if r then
		for _, name in ipairs(ATTACK_CLIPS) do
			r:Stop(name, 0.06)
		end
	end
end

function CombatController.OnServerBlock(active)
	if active and s.BlockHeld then
		startBlockVisual()
	elseif not active then
		stopBlockVisual()
	end
end

----------------------------------------------------------------------------------------------
-- Input

local function bind(name, fn, touchTitle, position, ...)
	ContextActionService:BindAction(name, fn, touchTitle ~= nil, ...)
	if touchTitle then
		ContextActionService:SetTitle(name, touchTitle)
		ContextActionService:SetPosition(name, position)
	end
end

local function onAttack(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		s.M1Held = true
		tryM1()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		s.M1Held = false
	end
	return Enum.ContextActionResult.Pass
end

local function onBlock(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		blockPressed()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		blockReleased()
	end
	return Enum.ContextActionResult.Sink
end

local function onHeavy(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		tryHeavy()
	end
	return Enum.ContextActionResult.Sink
end

local function onDodge(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		tryDodge()
	end
	return Enum.ContextActionResult.Sink
end

local function onSlide(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		ctx.Movement.TrySlide()
	end
	return Enum.ContextActionResult.Sink
end

local function onSprint(_, inputState, input)
	local toggle = input.KeyCode == Config.Keybinds.GamepadSprint or input.UserInputType == Enum.UserInputType.Touch
	if toggle then
		if inputState == Enum.UserInputState.Begin then
			ctx.Movement.ToggleSprint()
		end
	elseif inputState == Enum.UserInputState.Begin then
		ctx.Movement.SetSprintHeld(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		ctx.Movement.SetSprintHeld(false)
	end
	return Enum.ContextActionResult.Sink
end

local function onHelp(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		ctx.HUD.ToggleHelp()
	end
	return Enum.ContextActionResult.Sink
end

function CombatController.Start(context)
	ctx = context
	local k = Config.Keybinds
	bind("CombatAttack", onAttack, "Punch", UDim2.new(1, -95, 0, 10), k.Attack, k.GamepadAttack)
	bind("CombatBlock", onBlock, "Block", UDim2.new(1, -170, 0, 10), k.Block, k.GamepadBlock)
	bind("CombatHeavy", onHeavy, "Heavy", UDim2.new(1, -95, 0, -65), k.Heavy, k.GamepadHeavy)
	bind("CombatDodge", onDodge, "Dodge", UDim2.new(1, -170, 0, -65), k.Dodge, k.GamepadDodge)
	bind("CombatSlide", onSlide, "Slide", UDim2.new(1, -245, 0, 10), k.Slide, k.GamepadSlide)
	bind("CombatSprint", onSprint, "Sprint", UDim2.new(1, -245, 0, -65), k.SprintHold, k.GamepadSprint)
	bind("CombatHelp", onHelp, nil, nil, Enum.KeyCode.H)

	-- buffered presses + hold-to-chain
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		if s.BufferedAction and t >= s.BufferedAt then
			local action = s.BufferedAction
			s.BufferedAction = nil
			if action == "M1" then
				tryM1()
			else
				tryHeavy()
			end
		elseif s.M1Held and t >= math.max(s.ActionEnd, s.ComboCooldownUntil) and not s.Blocking then
			tryM1()
		end
		if s.ActionKind and t >= s.ActionEnd then
			s.ActionKind = nil
		end
		-- a held block starts as soon as we're free (after a punch, a stun, a dodge)
		if s.BlockHeld and not s.Blocking and canBlockNow() then
			startBlockVisual()
		end
		-- forget old predictions
		for seq in pairs(s.Predicted) do
			if seq < s.Seq - 40 then
				s.Predicted[seq] = nil
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		s.ActionEnd, s.ActionKind, s.Combo = 0, nil, 0
		s.Blocking, s.BlockHeld, s.M1Held, s.BufferedAction = false, false, false, nil
		s.HeavyCooldownUntil, s.DodgeCooldownUntil = 0, 0
	end)
end

return CombatController
