-- Turns server combat events into animation, hitstop, VFX, SFX and camera feedback for every
-- character in the game.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)

local FXHandler = {}

local player = Players.LocalPlayer
local ctx

local ATTACK_CLIPS = { "Jab", "Cross", "Hook", "Uppercut", "Heavy" }
local chargeStops = {} -- [Model] = stop function

local function isMe(model)
	return model ~= nil and model == player.Character
end

local function rigOf(model)
	return model and model.Parent and ctx.Animator.Get(model) or nil
end

local function stopAttacks(rig, fade)
	for _, name in ipairs(ATTACK_CLIPS) do
		rig:Stop(name, fade or 0.06)
	end
	ctx.VFX.SetTrail(rig.Model, "L", false)
	ctx.VFX.SetTrail(rig.Model, "R", false)
	local stop = chargeStops[rig.Model]
	if stop then
		chargeStops[rig.Model] = nil
		stop()
	end
end

local function hitstop(duration, ...)
	for _, model in ipairs({ ... }) do
		local rig = rigOf(model)
		if rig then
			rig:Freeze(duration)
		end
	end
end

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------------------------------------
-- Marker-driven effects (swings, charge, footsteps, landings)

local function onMarker(rig, track, marker)
	local model = rig.Model
	local name = marker.name
	if name == "Swing" then
		local heavy = track.Name == "Heavy"
		ctx.VFX.SetTrail(model, marker.arm or "R", true, if heavy then ctx.VFX.Palette.Heavy.Accent else nil)
		local root = rootOf(model)
		if root then
			ctx.SFX.Play(if heavy or track.Name == "Uppercut" then "SwingHeavy" else "Swing", root)
		end
	elseif name == "SwingEnd" then
		ctx.VFX.SetTrail(model, marker.arm or "R", false)
	elseif name == "Charge" then
		local old = chargeStops[model]
		if old then
			old()
		end
		chargeStops[model] = ctx.VFX.Charge(model, "R", Config.Heavy.Windup - 0.02)
		ctx.VFX.FlashModel(model, ctx.VFX.Palette.Heavy.Accent, Config.Heavy.Windup, 0.75)
		local root = rootOf(model)
		if root then
			ctx.SFX.Play("HeavyCharge", root)
		end
	elseif name == "Impact" then
		local stop = chargeStops[model]
		if stop then
			chargeStops[model] = nil
			stop()
		end
	elseif name == "Land" then
		local root = rootOf(model)
		if root then
			ctx.SFX.Play("BodySlam", root)
			ctx.VFX.Land(model, 1)
		end
	end
end

local function onLand(rig, impact)
	ctx.VFX.Land(rig.Model, impact)
	local root = rootOf(rig.Model)
	if root and impact > 0.45 then
		ctx.SFX.Play("Land", root, { Volume = 0.4 + impact * 0.6 })
	end
	if isMe(rig.Model) and impact > 0.5 then
		ctx.CameraFX.Shake(0.15 * impact)
	end
end

local function onStep(rig, runBlend)
	if runBlend > 0.5 then
		ctx.VFX.Footstep(rig.Model, runBlend)
	end
end

----------------------------------------------------------------------------------------------
-- Dodge visuals (also used directly by the local prediction)

function FXHandler.PlayDodge(model, dir)
	local rig = rigOf(model)
	if not rig then
		return
	end
	rig:Play("Dodge" .. dir)
	local root = rootOf(model)
	if not root then
		return
	end
	local vectors = {
		Forward = root.CFrame.LookVector,
		Back = -root.CFrame.LookVector,
		Left = -root.CFrame.RightVector,
		Right = root.CFrame.RightVector,
	}
	ctx.VFX.DodgeBurst(model, vectors[dir] or root.CFrame.LookVector)
	ctx.SFX.Play("Dodge", root)
	local accent = ctx.VFX.Palette.Dodge.Accent
	task.spawn(function()
		for _ = 1, 5 do
			if not model.Parent then
				break
			end
			ctx.VFX.Afterimage(model, accent, 0.28)
			task.wait(0.045)
		end
	end)
	if isMe(model) then
		ctx.CameraFX.Kick(3)
	end
end

----------------------------------------------------------------------------------------------
-- Server events

local handlers = {}

function handlers.Attack(data)
	if isMe(data.Model) then
		ctx.CombatController.OnOwnAttack(data)
		return
	end
	local rig = rigOf(data.Model)
	if rig and data.Anim then
		stopAttacks(rig, 0.04)
		rig:Play(data.Anim)
	end
end

function handlers.Cancel(data)
	local rig = rigOf(data.Model)
	if rig then
		stopAttacks(rig)
	end
end

function handlers.Hit(data)
	local attacker, victim = data.Attacker, data.Victim
	local heavy = data.Kind == "Heavy"
	local kind = if heavy then "Heavy" elseif data.Finisher then "Finisher" else "Light"
	local stopTime = if heavy
		then Config.HitStop.Heavy
		elseif data.Finisher then Config.HitStop.Finisher
		else Config.HitStop.Light
	hitstop(stopTime, attacker, victim)

	local victimRig = rigOf(victim)
	if victimRig then
		stopAttacks(victimRig)
		victimRig:Stop("BlockHold", 0.05)
		victimRig:Stop("Slide", 0.08)
		local clip
		if heavy or data.Finisher then
			clip = "Knockback"
		elseif data.Index == 3 then
			clip = "HitBody"
		else
			clip = if (data.Index or 1) % 2 == 1 then "HitA" else "HitB"
		end
		victimRig:Play(clip)
		victimRig:Shake(if heavy then 9 else 5, stopTime + 0.12)
	end

	ctx.VFX.Hit(data.Position, data.Direction, kind, victim)
	ctx.SFX.Play(if heavy then "HitHeavy" elseif data.Finisher then "HitFinisher" else "Hit", data.Position)
	if Config.Damage.ShowNumbers and data.Damage then
		ctx.VFX.DamageNumber(data.Position + Vector3.new(0, 1.2, 0), data.Damage, kind)
	end

	if isMe(attacker) then
		ctx.CameraFX.Shake(if heavy then 0.45 elseif data.Finisher then 0.32 else 0.14)
		ctx.CameraFX.Kick(if heavy then -6 else -1.5)
		ctx.HUD.RegisterHit()
		if heavy then
			ctx.CameraFX.Flash(Color3.fromRGB(255, 200, 170), 0.6, 5)
		end
	end
	if isMe(victim) then
		ctx.CombatController.OnInterrupted(false)
		ctx.Movement.ApplyKnockback(data.Knockback, data.KnockTime or 0.12)
		ctx.CameraFX.Shake(if heavy then 0.6 elseif data.Finisher then 0.45 else 0.25)
		ctx.CameraFX.Flash(Color3.fromRGB(255, 120, 120), if heavy then 0.8 else 0.35, 7)
		if heavy then
			ctx.CameraFX.Blur(10, 5)
		end
	end
end

function handlers.Blocked(data)
	hitstop(Config.HitStop.Block, data.Attacker, data.Victim)
	local victimRig = rigOf(data.Victim)
	if victimRig then
		victimRig:Play("BlockImpact")
		victimRig:Shake(2.5, 0.12)
	end
	ctx.VFX.Block(data.Position, data.Direction, data.Victim)
	ctx.SFX.Play("Block", data.Position)
	if data.Damage and data.Damage > 0 and Config.Damage.ShowNumbers then
		ctx.VFX.DamageNumber(data.Position + Vector3.new(0, 1.2, 0), data.Damage, "Chip")
	end
	if isMe(data.Victim) then
		ctx.CameraFX.Shake(0.12)
		ctx.Movement.ApplyKnockback(data.Knockback, 0.1)
		ctx.HUD.FlashPosture()
	end
	if isMe(data.Attacker) then
		ctx.CameraFX.Shake(0.08)
	end
end

function handlers.Parry(data)
	local parried, parrier = data.Attacker, data.Victim
	hitstop(Config.HitStop.Parry, parried, parrier)
	local parriedRig = rigOf(parried)
	if parriedRig then
		stopAttacks(parriedRig, 0.03)
		parriedRig:Play("Parried")
		parriedRig:Shake(6, 0.25)
	end
	local parrierRig = rigOf(parrier)
	if parrierRig then
		parrierRig:Play("ParryDeflect")
	end
	ctx.VFX.Parry(data.Position, data.Direction, parrier, parried, data.Stun)
	ctx.SFX.Play("Parry", data.Position)

	local gold = ctx.VFX.Palette.Parry.Accent
	if isMe(parrier) then
		ctx.CameraFX.Shake(0.35)
		ctx.CameraFX.Kick(-7)
		ctx.CameraFX.Flash(gold, 1, 4)
		ctx.CameraFX.Blur(8, 6)
		ctx.HUD.ParryBanner()
	end
	if isMe(parried) then
		ctx.CombatController.OnInterrupted(false)
		ctx.Movement.ApplyKnockback(data.Knockback, 0.12)
		ctx.CameraFX.Shake(0.5)
		ctx.CameraFX.Flash(gold, 0.7, 4)
		ctx.CameraFX.Blur(12, 4)
	end
end

function handlers.GuardBreak(data)
	hitstop(Config.HitStop.GuardBreak, data.Attacker, data.Victim)
	local victimRig = rigOf(data.Victim)
	if victimRig then
		stopAttacks(victimRig)
		victimRig:Stop("BlockHold", 0.03)
		victimRig:Play("GuardBroken")
		victimRig:Shake(7, 0.25)
	end
	ctx.VFX.GuardBreak(data.Position, data.Direction, data.Victim, data.Stun)
	ctx.SFX.Play("GuardBreak", data.Position)
	if data.Damage and data.Damage > 0 and Config.Damage.ShowNumbers then
		ctx.VFX.DamageNumber(data.Position + Vector3.new(0, 1.2, 0), data.Damage, "Heavy")
	end
	if isMe(data.Victim) then
		ctx.CombatController.OnInterrupted(true)
		ctx.Movement.ApplyKnockback(data.Knockback, 0.12)
		ctx.CameraFX.Shake(0.5)
		ctx.CameraFX.Flash(ctx.VFX.Palette.GuardBreak.Accent, 0.8, 4)
	end
	if isMe(data.Attacker) then
		ctx.CameraFX.Shake(0.3)
		ctx.CameraFX.Kick(-4)
	end
end

function handlers.BlockStart(data)
	if isMe(data.Model) then
		ctx.CombatController.OnServerBlock(true)
		return
	end
	local rig = rigOf(data.Model)
	if rig then
		rig:Play("BlockHold")
	end
end

function handlers.BlockEnd(data)
	if isMe(data.Model) then
		ctx.CombatController.OnServerBlock(false)
		return
	end
	local rig = rigOf(data.Model)
	if rig then
		rig:Stop("BlockHold")
	end
end

function handlers.Dodge(data)
	if isMe(data.Model) then
		return -- already played locally
	end
	FXHandler.PlayDodge(data.Model, data.Dir)
end

function handlers.Dodged(data)
	local victim = data.Victim
	local head = victim and victim:FindFirstChild("Head")
	if head then
		ctx.VFX.PopText(head.Position + Vector3.new(0, 1.2, 0), "DODGE", ctx.VFX.Palette.Dodge.Accent, 1.1, 0.7, 1.6)
	end
end

local slideFx = {} -- [Model] = { Stop, Sound }

function handlers.Slide(data)
	local model = data.Model
	if isMe(model) then
		return
	end
	local rig = rigOf(model)
	local current = slideFx[model]
	if data.Active then
		if current or not rig then
			return
		end
		rig:Play("Slide")
		local root = rootOf(model)
		slideFx[model] = {
			Stop = ctx.VFX.SlideTrail(model),
			Sound = root and ctx.SFX.Play("SlideLoop", root),
		}
		if root then
			ctx.SFX.Play("SlideStart", root)
		end
	elseif current then
		slideFx[model] = nil
		if rig then
			rig:Stop("Slide")
		end
		current.Stop()
		if current.Sound then
			current.Sound:Stop(0.15)
		end
	end
end

function handlers.Reject(data)
	ctx.CombatController.OnReject(data)
end

function FXHandler.Start(context)
	ctx = context
	ctx.Animator.OnMarker(onMarker)
	ctx.Animator.OnLand(onLand)
	ctx.Animator.OnStep(onStep)
	ctx.Remotes.FX.OnClientEvent:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler and type(data) == "table" then
			local ok, err = pcall(handler, data)
			if not ok then
				warn("[FXHandler]", kind, err)
			end
		end
	end)
end

return FXHandler
