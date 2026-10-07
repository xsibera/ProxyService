--!strict
--[[
	JajankenClient (StarterPlayer > StarterPlayerScripts): the keys, the animations, the charge bar
	and every Jajanken effect this player sees.

	Hold Z / X / C (Config.Keys) to charge Rock / Paper / Scissors and let go to cast. Tapping casts
	at once with no charge; holding builds it up for Config.MaxCharge seconds, and at full charge it
	casts by itself. Your own charge shows the moment you press. Everyone else's arrives from the
	server, which owns the timing, cooldowns and hits (see JajankenServer).
]]

local ContextActionService = game:GetService("ContextActionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Jajanken = ReplicatedStorage:WaitForChild("Jajanken")
local Config = require(Jajanken:WaitForChild("Config")) :: any
local VFX = require(Jajanken:WaitForChild("JajankenVFX"))
local Remote = Jajanken:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Jajanken:WaitForChild("Animations")

type Attached = VFX.Attached

local HAND = CFrame.new(0, -1.05, 0) -- the fist, in an R6 Right Arm
local SHOUT = { Rock = "GUU!", Paper = "PAA!", Scissors = "CHII!" }

--------------------------------------------------------------------------- animations

local animations: { [string]: Animation } = {}
local warnedStudioOnly = false

local function animation(name: string): Animation?
	if animations[name] then
		return animations[name]
	end
	local id = Config.Animations[name]
	local source = AnimationFolder:FindFirstChild(name)
	local result: Animation? = nil
	if typeof(id) == "string" and id ~= "" then
		result = Instance.new("Animation")
		result.AnimationId = id
	elseif source and source:IsA("Animation") then
		if source.AnimationId ~= "" then
			result = source
		else
			-- unpublished: register the KeyframeSequence for a temporary id (works in Studio only)
			local sequence = source:FindFirstChildOfClass("KeyframeSequence")
			local ok, temporary = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence :: KeyframeSequence)
			end)
			if ok and typeof(temporary) == "string" then
				result = Instance.new("Animation")
				result.AnimationId = temporary
			elseif not warnedStudioOnly then
				warnedStudioOnly = true
				warn("Jajanken: publish the animations and put their ids in Jajanken.Config.Animations")
			end
		end
	end
	if result then
		animations[name] = result
	end
	return result
end

local tracks: { [string]: AnimationTrack } = {}

local function loadTracks(character: Model)
	table.clear(tracks)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	for _, name in { "Charge", "Hold", "Rock", "Paper", "Scissors" } do
		local source = animation(name)
		if source then
			local ok, track = pcall(function()
				return animator:LoadAnimation(source)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = name == "Hold"
				tracks[name] = track
			end
		end
	end
end

local function play(name: string, fade: number)
	local track = tracks[name]
	if track then
		track:Play(fade)
	end
end

local function stop(name: string, fade: number)
	local track = tracks[name]
	if track and track.IsPlaying then
		track:Stop(fade)
	end
end

--------------------------------------------------------------------------- the charge bar

local ui = {}
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "JajankenUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -96)
	panel.Size = UDim2.fromOffset(300, 92)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local chant = Instance.new("TextLabel")
	chant.Name = "Chant"
	chant.BackgroundTransparency = 1
	chant.Size = UDim2.new(1, 0, 0, 30)
	chant.Font = Enum.Font.GothamBlack
	chant.TextSize = 24
	chant.TextColor3 = Color3.fromRGB(255, 226, 170)
	chant.TextStrokeColor3 = Color3.fromRGB(70, 30, 0)
	chant.TextStrokeTransparency = 0.3
	chant.Text = ""
	chant.Parent = panel

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(0, 34)
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(25, 20, 16)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = panel
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 120, 20), Color3.fromRGB(255, 220, 120))
	gradient.Parent = fill

	local slots: { [string]: { frame: Frame, shade: Frame } } = {}
	for i, mode in Config.Modes do
		local slot = Instance.new("Frame")
		slot.Name = mode
		slot.Position = UDim2.new((i - 1) / 3, 3, 0, 52)
		slot.Size = UDim2.new(1 / 3, -6, 0, 34)
		slot.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
		slot.BackgroundTransparency = 0.3
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.Parent = panel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = slot
		local shade = Instance.new("Frame")
		shade.Name = "Cooldown"
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.fromScale(0, 1)
		shade.Size = UDim2.fromScale(1, 0)
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.45
		shade.BorderSizePixel = 0
		shade.Parent = slot
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextColor3 = Color3.fromRGB(255, 236, 205)
		local key = Config.Keys[mode]
		label.Text = (if key then key.Name .. "  " else "") .. mode
		label.ZIndex = 2
		label.Parent = slot
		slots[mode] = { frame = slot, shade = shade }
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	local shoutTween: Tween? = nil
	function ui.charge(alpha: number)
		bar.Visible = true
		fill.Size = UDim2.fromScale(alpha, 1)
		if Config.Chant then
			chant.TextTransparency = 0
			chant.Text = if alpha < 1 / 3 then "Saisho wa guu..." elseif alpha < 2 / 3 then "Jan..." else "Ken..."
		end
	end
	function ui.release(mode: string)
		bar.Visible = false
		if shoutTween then
			shoutTween:Cancel()
		end
		if Config.Chant then
			chant.Text = SHOUT[mode] or mode
			chant.TextTransparency = 0
			shoutTween =
				TweenService:Create(chant, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1,
				})
			shoutTween:Play()
		end
	end
	function ui.hide()
		bar.Visible = false
		chant.Text = ""
	end
	function ui.cooldowns(ready: { [string]: number }, now: number)
		for mode, slot in slots do
			local left = math.max(ready[mode] - now, ready.All - now, 0)
			local total = math.max(Config.Cooldown[mode], 0.01)
			slot.shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
		end
	end
	function ui.deny(mode: string)
		local slot = slots[mode]
		if slot then
			slot.frame.BackgroundColor3 = Color3.fromRGB(120, 30, 20)
			TweenService:Create(slot.frame, TweenInfo.new(0.35), { BackgroundColor3 = Color3.fromRGB(30, 24, 18) })
				:Play()
		end
	end
end

--------------------------------------------------------------------------- effects

local function parts(who: Player): (Model?, BasePart?, BasePart?, Humanoid?)
	local character = who.Character
	if not character then
		return nil, nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local arm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character,
		if root and root:IsA("BasePart") then root else nil,
		if arm and arm:IsA("BasePart") then arm else nil,
		humanoid
end

-- the aura round the body and the charge gathering in the hand
local function startAura(who: Player): (Attached?, Attached?)
	local character, root, arm = parts(who)
	if not (character and root) then
		return nil, nil
	end
	local aura = VFX.Attach("Aura", root, nil, { Charge = 0, Ignore = { character } })
	local hand = if arm
		then VFX.Attach(
			"HandCharge", -- the same for all three: the mode only shows on the release
			arm,
			if arm.Name == "Right Arm" then HAND else CFrame.identity,
			{ Charge = 0 }
		)
		else nil
	return aura, hand
end

local function stopAura(aura: Attached?, hand: Attached?, handFor: number?)
	if aura then
		aura:Stop()
	end
	if hand then
		if handFor and handFor > 0 then
			task.delay(handFor, function()
				hand:Stop()
			end)
		else
			hand:Stop()
		end
	end
end

local function scaleFor(charge: number): number
	return 0.7 + 0.6 * charge
end

-- the release flare now, then the hit's effects when it lands
local function castEffects(caster: Player, mode: string, charge: number, hitAt: number)
	local character, root = parts(caster)
	if not (character and root) then
		return
	end
	local options = { Charge = charge, Scale = scaleFor(charge), Ignore = { character } }
	VFX.Play("Release", root.CFrame, options)
	task.delay(math.max(0, hitAt - workspace:GetServerTimeNow()), function()
		if not root.Parent then
			return
		end
		local at = root.CFrame
		if mode == "Rock" then
			local fist = at * CFrame.new(0.85, 0.15, -3.8)
			VFX.Play("RockBlast", fist, options)
			VFX.Sound("RockHit", fist.Position, 0.7 + 0.6 * charge)
		elseif mode == "Scissors" then
			VFX.Play("ScissorsSlash", at * CFrame.new(0.2, 0.35, -1.9), options)
			VFX.Sound("ScissorsCast", root, 0.7 + 0.6 * charge)
		end
	end)
end

--------------------------------------------------------------------------- charging

type Charging = { mode: string, started: number, aura: Attached?, hand: Attached? }
local charging: Charging? = nil
local busyUntil = 0
local ready = { Rock = 0, Paper = 0, Scissors = 0, All = 0 }

type Other = { mode: string, startedAt: number, aura: Attached?, hand: Attached? }
local others: { [Player]: Other } = {}
local projectiles: { [number]: Attached } = {}

local function setJump(enabled: boolean)
	local _, _, _, humanoid = parts(player)
	if humanoid and not Config.CanJumpWhileCharging then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	end
end

local function beginCharge(mode: string)
	local now = os.clock()
	if charging or now < busyUntil then
		return
	end
	if now < ready[mode] or now < ready.All then
		ui.deny(mode)
		return
	end
	local character, root, _, humanoid = parts(player)
	if not (character and root and humanoid and humanoid.Health > 0) then
		return
	end
	local aura, hand = startAura(player)
	charging = { mode = mode, started = now, aura = aura, hand = hand }
	stop("Hold", 0)
	play("Charge", 0.08)
	local chargeTrack = tracks.Charge
	local holdAfter = if chargeTrack and chargeTrack.Length > 0 then chargeTrack.Length - 0.08 else 0.35
	local this = charging
	task.delay(holdAfter, function()
		if charging == this then
			play("Hold", 0.12)
		end
	end)
	setJump(false)
	Remote:FireServer("Charge", mode)
	ui.charge(0)
end

-- let go (or full charge, or the server cast it first)
local function release(mode: string, toldByServer: boolean)
	local current = charging
	if not current or current.mode ~= mode then
		return
	end
	charging = nil
	local now = os.clock()
	local settings = Config[mode]
	stop("Charge", 0.05)
	stop("Hold", 0.05)
	play(mode, 0.05)
	busyUntil = now + settings.Recovery
	ready[mode] = now + Config.Cooldown[mode]
	ready.All = now + Config.SharedCooldown
	stopAura(current.aura, current.hand, settings.HitDelay)
	task.delay(settings.Recovery, function()
		if not charging then
			setJump(true)
		end
	end)
	if not toldByServer then
		local camera = workspace.CurrentCamera
		Remote:FireServer("Release", if camera then camera.CFrame.LookVector else nil)
	end
	ui.release(mode)
end

local function cancelCharge()
	local current = charging
	if not current then
		return
	end
	charging = nil
	stop("Charge", 0.1)
	stop("Hold", 0.1)
	stopAura(current.aura, current.hand, nil)
	setJump(true)
	ui.hide()
end

local function stopOther(who: Player, handFor: number?)
	local other = others[who]
	if other then
		others[who] = nil
		stopAura(other.aura, other.hand, handFor)
	end
end

--------------------------------------------------------------------------- input

local ACTIONS: { [string]: string } = {}
for _, mode in Config.Modes do
	local action = "Jajanken" .. mode
	ACTIONS[action] = mode
	local inputs = {}
	if Config.Keys[mode] then
		table.insert(inputs, Config.Keys[mode])
	end
	if Config.GamepadButtons[mode] then
		table.insert(inputs, Config.GamepadButtons[mode])
	end
	ContextActionService:BindAction(action, function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			beginCharge(mode)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			release(mode, false)
		end
		return Enum.ContextActionResult.Sink
	end, Config.MobileButtons, table.unpack(inputs))
	if Config.MobileButtons then
		ContextActionService:SetTitle(action, mode)
	end
end

--------------------------------------------------------------------------- server events

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any, f: any, g: any, h: any)
	if kind == "Charge" then -- a: caster, b: mode, c: startedAt
		if a ~= player then
			stopOther(a, nil)
			local aura, hand = startAura(a)
			others[a] = { mode = b, startedAt = c, aura = aura, hand = hand }
		end
	elseif kind == "Stop" then -- a: caster
		if a == player then
			cancelCharge()
		else
			stopOther(a, nil)
		end
	elseif kind == "Cast" then -- a: caster, b: mode, c: charge, d: hitAt
		if a == player then
			release(b, true) -- only does anything if the server cast it first (full charge)
		else
			stopOther(a, math.max(0, d - workspace:GetServerTimeNow()))
		end
		castEffects(a, b, c, d)
	elseif kind == "Launch" then -- a: caster, b: id, c: from, d: direction, e: speed, f: range, g: launchAt, h: charge
		local character = a.Character
		projectiles[b] = VFX.Projectile("PaperBall", c, d, e, f, g, { Scale = scaleFor(h), Ignore = { character } })
		VFX.Sound("ScissorsCast", c, 0.5 + 0.5 * h)
	elseif kind == "Explode" then -- a: caster, b: id, c: position, d: charge
		local ball = projectiles[b]
		projectiles[b] = nil
		if ball then
			ball:Stop()
		end
		VFX.Play("PaperBlast", CFrame.new(c), { Charge = d, Scale = scaleFor(d), Ignore = { a.Character } })
		VFX.Sound("PaperHit", c, 0.7 + 0.6 * d)
	elseif kind == "Hit" then -- a: victim, b: mode, c: position, d: direction
		VFX.Play("NenHit", CFrame.lookAt(c, c + d), { Ignore = { a } })
	elseif kind == "Denied" then -- a: mode, b: seconds left
		if charging and charging.mode == a then
			cancelCharge()
		end
		ready[a] = math.max(ready[a], os.clock() + b)
		ui.deny(a)
	end
end)

Players.PlayerRemoving:Connect(function(who: Player)
	stopOther(who, nil)
end)

--------------------------------------------------------------------------- every frame

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local current = charging
	if current then
		local alpha = math.clamp((now - current.started) / Config.MaxCharge, 0, 1)
		if current.aura then
			current.aura:SetCharge(alpha)
		end
		if current.hand then
			current.hand:SetCharge(alpha)
		end
		ui.charge(alpha)
		if alpha >= 1 then
			release(current.mode, false)
		end
	end
	local serverNow = workspace:GetServerTimeNow()
	for _, other in others do
		local alpha = math.clamp((serverNow - other.startedAt) / Config.MaxCharge, 0, 1)
		if other.aura then
			other.aura:SetCharge(alpha)
		end
		if other.hand then
			other.hand:SetCharge(alpha)
		end
	end
	ui.cooldowns(ready, now)
end)

--------------------------------------------------------------------------- the character

local function onCharacter(character: Model)
	cancelCharge()
	busyUntil = 0
	loadTracks(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if charging then
				cancelCharge()
				Remote:FireServer("Cancel")
			end
		end)
	end
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
