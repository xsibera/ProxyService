-- Local player movement: sprint, slide (slope-aware, steerable, slide-jump momentum), dodge,
-- attack lunges, aim assist and knockback. Also owns the local Humanoid's WalkSpeed and
-- JumpHeight, derived each frame from the combat state the server replicates.
--
-- All velocity changes go through one "mover" (a LinearVelocity on the root) with priorities,
-- so a knockback always wins over a dodge, a dodge over a slide, and so on.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)
local Util = require(Combat.Util)

local create = Util.create
local flat = Util.flat

local Movement = {}

local player = Players.LocalPlayer
local ctx
local character, humanoid, root, rootAttachment

local PRIORITY = { Lunge = 1, Slide = 2, Dodge = 3, Knockback = 4 }

local sprintHeld = false
local sprintToggle = false
local lastForwardTap = -math.huge
local stillTime = 0
local currentSpeed = Config.Movement.WalkSpeed
local sprinting = false

local slide = nil
local slideCooldownUntil = 0
local momentum, momentumPeak = 0, 0
local dodgeState = nil
local mover = nil
local windSound = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

----------------------------------------------------------------------------------------------
-- Mover

local function stopMover()
	local m = mover
	if m then
		mover = nil
		if m.Constraint.Parent then
			m.Constraint:Destroy()
		end
		if m.OnStop then
			m.OnStop()
		end
	end
end

local function startMover(name, mode, duration, update, onStop)
	if not root or not rootAttachment then
		return false
	end
	local priority = PRIORITY[name]
	if mover and mover.Priority > priority then
		return false
	end
	stopMover()
	local lv = create("LinearVelocity", {
		Name = "Mover_" .. name,
		Attachment0 = rootAttachment,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = mode,
		PrimaryTangentAxis = Vector3.xAxis,
		SecondaryTangentAxis = Vector3.zAxis,
		MaxForce = 1e6,
	})
	mover = {
		Name = name,
		Priority = priority,
		Constraint = lv,
		Update = update,
		Start = os.clock(),
		Duration = duration,
		OnStop = onStop,
	}
	update(0, 0, lv)
	lv.Parent = root
	return true
end

local function setPlane(lv, v)
	lv.PlaneVelocity = Vector2.new(v.X, v.Z)
end

----------------------------------------------------------------------------------------------
-- Queries

local function combatState()
	return character and character:GetAttribute("CombatState") or "Idle"
end

local function isStunnedState(state)
	return state == "Stunned" or state == "Parried" or state == "GuardBroken" or state == "Dead"
end

function Movement.IsSliding()
	return slide ~= nil
end

function Movement.IsDodging()
	return dodgeState ~= nil
end

function Movement.IsSprinting()
	return sprinting
end

function Movement.Character()
	return character, humanoid, root
end

-- Nearest living combatant in front of us (for aim assist / lunge spacing).
function Movement.NearestEnemy(range, minDot)
	if not root then
		return nil
	end
	local look = flat(root.CFrame.LookVector).Unit
	local best, bestDist = nil, range
	for model in pairs(ctx.Animator.All()) do
		if model ~= character and Util.isAlive(model) then
			local delta = flat(model.HumanoidRootPart.Position - root.Position)
			local dist = delta.Magnitude
			if dist < bestDist and dist > 0.05 and look:Dot(delta.Unit) >= (minDot or -1) then
				best, bestDist = model, dist
			end
		end
	end
	return best, bestDist
end

----------------------------------------------------------------------------------------------
-- Actions

local function endSlide(keepMomentum)
	if not slide then
		return
	end
	local s = slide
	slide = nil
	if keepMomentum then
		momentum = s.Speed * Config.Slide.JumpKeep
		momentumPeak = momentum
	end
	if mover and mover.Name == "Slide" then
		stopMover()
	end
	ctx.Animator.Get(character):Stop("Slide")
	s.StopFx()
	if s.Sound then
		s.Sound:Stop(0.15)
	end
	slideCooldownUntil = os.clock() + Config.Slide.Cooldown
	ctx.Send("Slide", { Active = false })
end

function Movement.StopSlide()
	endSlide(false)
end

function Movement.TrySlide()
	if not root or slide or os.clock() < slideCooldownUntil or humanoid.Health <= 0 then
		return false
	end
	local state = combatState()
	if isStunnedState(state) or state == "Attacking" or state == "Blocking" then
		return false
	end
	if ctx.CombatController.IsBusy() or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local v = flat(root.AssemblyLinearVelocity)
	local speed = v.Magnitude
	if speed < Config.Slide.MinSpeed then
		return false
	end
	local s = {
		Dir = v.Unit,
		Speed = math.min(speed + Config.Slide.Boost, Config.Slide.MaxStartSpeed),
		AirTime = 0,
	}
	slide = s
	local ok = startMover("Slide", Enum.VelocityConstraintMode.Plane, Config.Slide.MaxDuration, function(dt, _, lv)
		if slide ~= s then
			return false
		end
		local move = flat(humanoid.MoveDirection)
		if move.Magnitude > 0.1 and dt > 0 then
			local target = move.Unit
			local angle = math.acos(math.clamp(s.Dir:Dot(target), -1, 1))
			if angle > 1e-3 then
				local step = math.min(1, Config.Slide.Steering * dt / angle)
				s.Dir = s.Dir:Lerp(target, step).Unit
			end
		end
		rayParams.FilterDescendantsInstances = { character, ctx.VFX.Folder() }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -4.2, 0), rayParams)
		if hit then
			s.AirTime = 0
			local n = hit.Normal
			local downhill = flat(Vector3.new(0, -1, 0) + n * n.Y)
			s.Speed += Config.Slide.SlopeGravity * downhill:Dot(s.Dir) * dt
			s.Speed -= Config.Slide.Friction * dt
		else
			s.AirTime += dt
			if s.AirTime > 0.18 then
				-- slid off a ledge: carry the speed into the fall
				task.defer(endSlide, true)
				return false
			end
		end
		if s.Speed < Config.Slide.EndSpeed then
			task.defer(endSlide, false)
			return false
		end
		setPlane(lv, s.Dir * s.Speed)
		return true
	end, function()
		if slide == s then
			task.defer(endSlide, false)
		end
	end)
	if not ok then
		slide = nil
		return false
	end
	local rig = ctx.Animator.Get(character)
	rig:Play("Slide")
	s.StopFx = ctx.VFX.SlideTrail(character)
	s.Sound = ctx.SFX.Play("SlideLoop", root)
	ctx.SFX.Play("SlideStart", root)
	ctx.CameraFX.Kick(5)
	ctx.Send("Slide", { Active = true })
	return true
end

local DODGE_VECTORS = {
	Forward = function(cf)
		return cf.LookVector
	end,
	Back = function(cf)
		return -cf.LookVector
	end,
	Left = function(cf)
		return -cf.RightVector
	end,
	Right = function(cf)
		return cf.RightVector
	end,
}

-- Which way should a dodge go, given the current movement input?
function Movement.DodgeDirection()
	if not root or not humanoid then
		return "Back"
	end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return "Back"
	end
	local rel = root.CFrame:VectorToObjectSpace(move)
	local forward, right = -rel.Z, rel.X
	if math.abs(forward) >= math.abs(right) then
		return if forward > 0 then "Forward" else "Back"
	end
	return if right > 0 then "Right" else "Left"
end

function Movement.Dodge(dirName)
	if not root then
		return false
	end
	endSlide(false)
	local dir = flat(DODGE_VECTORS[dirName](root.CFrame)).Unit
	local d = Config.Dodge
	local state = { Dir = dirName }
	dodgeState = state
	humanoid.AutoRotate = false
	local ok = startMover("Dodge", Enum.VelocityConstraintMode.Plane, d.Duration, function(_, elapsed, lv)
		local a = math.clamp(elapsed / d.Duration, 0, 1)
		setPlane(lv, dir * Util.lerp(d.Speed, d.EndSpeed, Util.outQuad(a)))
		return true
	end, function()
		if dodgeState == state then
			dodgeState = nil
		end
		if humanoid then
			humanoid.AutoRotate = true
		end
	end)
	if not ok then
		dodgeState = nil
		humanoid.AutoRotate = true
	end
	return ok
end

-- Small forward step that sells each punch. Skipped when already in someone's face.
function Movement.Lunge(speed, duration)
	if not root or not speed or speed <= 0 then
		return
	end
	local _, dist = Movement.NearestEnemy(6, 0.3)
	if dist and dist < 3.4 then
		return
	end
	local dir = flat(root.CFrame.LookVector).Unit
	startMover("Lunge", Enum.VelocityConstraintMode.Plane, duration, function(_, elapsed, lv)
		local a = math.clamp(elapsed / duration, 0, 1)
		setPlane(lv, dir * speed * (1 - Util.outQuad(a)))
		return true
	end)
end

-- Turn toward a nearby enemy so close-range punches land where you meant them.
function Movement.AimAssist()
	if not root then
		return
	end
	local target = Movement.NearestEnemy(9, 0.25)
	if target then
		local delta = flat(target.HumanoidRootPart.Position - root.Position)
		if delta.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + delta.Unit)
		end
	end
end

function Movement.ApplyKnockback(vector, duration)
	if not root then
		return
	end
	endSlide(false)
	sprintToggle = false
	local lift = vector.Y > 0.5
	startMover("Knockback", Enum.VelocityConstraintMode.Vector, duration, function(_, elapsed, lv)
		local a = math.clamp(elapsed / duration, 0, 1)
		local v = vector * (1 - 0.35 * a)
		lv.VectorVelocity = if lift then v else Vector3.new(v.X, root.AssemblyLinearVelocity.Y, v.Z)
		return true
	end)
end

function Movement.StopSprint()
	sprintToggle = false
end

----------------------------------------------------------------------------------------------
-- Input

function Movement.SetSprintHeld(held)
	sprintHeld = held
end

function Movement.ToggleSprint()
	sprintToggle = not sprintToggle
end

local FORWARD_KEYS = { [Enum.KeyCode.W] = true, [Enum.KeyCode.Up] = true }

local function onInputBegan(input, processed)
	if processed then
		return
	end
	if FORWARD_KEYS[input.KeyCode] then
		local t = os.clock()
		if t - lastForwardTap <= Config.Sprint.DoubleTapWindow then
			sprintToggle = true
		end
		lastForwardTap = t
	end
end

local function onJumpRequest()
	if slide then
		endSlide(true)
	end
end

----------------------------------------------------------------------------------------------
-- Per-frame

local function update(dt)
	if not humanoid or not root or not root.Parent or humanoid.Health <= 0 then
		return
	end
	local t = os.clock()
	local state = combatState()
	local stunned = isStunnedState(state)
	local combat = ctx.CombatController
	local attacking = combat.IsAttacking() or state == "Attacking"
	local blocking = combat.IsBlocking() or state == "Blocking"
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	if moving then
		stillTime = 0
	else
		stillTime += dt
		if stillTime > 0.2 then
			sprintToggle = false
		end
	end
	sprinting = (sprintHeld or sprintToggle) and moving and not attacking and not blocking and not stunned and not slide

	local m = Config.Movement
	local target
	if stunned then
		target = m.StunWalkSpeed
	elseif attacking then
		target = if combat.AttackKind() == "Heavy" then m.HeavyWalkSpeed else m.AttackWalkSpeed
	elseif blocking then
		target = m.BlockWalkSpeed
	elseif sprinting then
		target = Config.Sprint.Speed
	else
		target = m.WalkSpeed
	end
	if target > currentSpeed then
		currentSpeed = math.min(target, currentSpeed + Config.Sprint.Acceleration * dt)
	else
		currentSpeed = target
	end

	-- slide-jump momentum: keep it while airborne, bleed it off once landed
	if momentum > 0 then
		if stunned or attacking or blocking then
			momentum = 0
		elseif grounded then
			momentum = math.max(0, momentum - momentumPeak / Config.Slide.MomentumDecay * dt)
		end
	end
	local walkSpeed = math.max(currentSpeed, if stunned then 0 else momentum)
	if math.abs(humanoid.WalkSpeed - walkSpeed) > 0.01 then
		humanoid.WalkSpeed = walkSpeed
	end
	local jump = if stunned or attacking or blocking then 0 else m.JumpHeight
	if humanoid.JumpHeight ~= jump then
		humanoid.JumpHeight = jump
	end
	if humanoid.UseJumpPower then
		humanoid.UseJumpPower = false
	end

	-- mover
	if mover then
		local elapsed = t - mover.Start
		if elapsed >= mover.Duration or mover.Update(dt, elapsed, mover.Constraint) == false then
			stopMover()
		end
	end

	-- camera + wind
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	local runFactor = math.clamp((speed - 17) / 9, 0, 1)
	local sprintCfg = Config.Sprint
	ctx.CameraFX.SetFOV(
		sprintCfg.BaseFOV + (sprintCfg.SprintFOV - sprintCfg.BaseFOV) * runFactor + (if slide then 4 else 0)
	)
	ctx.CameraFX.SetSpeedLines((speed - sprintCfg.SpeedLinesFrom) / 22)
	if windSound then
		windSound:SetVolume(math.clamp((speed - 18) / 20, 0, 1))
	end
end

local function onCharacter(newCharacter)
	stopMover()
	slide, dodgeState = nil, nil
	momentum, sprintToggle = 0, false
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	root = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then
		return
	end
	rootAttachment = root:FindFirstChild("RootAttachment")
		or create("Attachment", { Name = "RootAttachment", Parent = root })
	currentSpeed = Config.Movement.WalkSpeed
	if windSound then
		windSound:Stop()
	end
	windSound = ctx.SFX.Play("SprintWind", root, { Volume = 1 })
	if windSound then
		windSound:SetVolume(0)
	end
end

function Movement.Start(context)
	ctx = context
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.JumpRequest:Connect(onJumpRequest)
	RunService.PreSimulation:Connect(update)
end

return Movement
