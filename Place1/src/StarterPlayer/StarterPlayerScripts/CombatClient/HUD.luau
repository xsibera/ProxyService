-- Combat HUD: health + posture, cooldowns, combo counter, parry banner, controls panel, and
-- overhead health/posture/state plates on every other fighter.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)
local Util = require(Combat.Util)

local create = Util.create
local lerp = Util.lerp

local HUD = {}

local player = Players.LocalPlayer
local ctx

local FONT = Enum.Font.GothamBlack
local FONT_BODY = Enum.Font.GothamBold
local COLORS = {
	Panel = Color3.fromRGB(14, 16, 22),
	Health = Color3.fromRGB(92, 230, 120),
	HealthLow = Color3.fromRGB(255, 80, 70),
	Chip = Color3.fromRGB(255, 236, 200),
	Posture = Color3.fromRGB(120, 190, 255),
	PostureLow = Color3.fromRGB(255, 120, 90),
	Gold = Color3.fromRGB(255, 220, 90),
}

local STATE_TAGS = {
	Stunned = { "STUNNED", Color3.fromRGB(255, 170, 80) },
	Parried = { "PARRIED", Color3.fromRGB(255, 220, 90) },
	GuardBroken = { "GUARD BROKEN", Color3.fromRGB(110, 180, 255) },
	Blocking = { "BLOCKING", Color3.fromRGB(170, 215, 255) },
	Dodging = { "DODGE", Color3.fromRGB(170, 225, 255) },
}

local gui
local healthFill, healthChip, healthText, postureFill
local cooldownSlots = {}
local comboFrame, comboNumber, comboScale
local bannerLabel, bannerScale
local helpFrame
local comboCount, lastHit = 0, -math.huge
local shownHealth, chipHealth, chipHoldUntil = 1, 1, 0
local postureFlashUntil = 0

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function stroke(parent, thickness, transparency)
	return create("UIStroke", {
		Thickness = thickness or 1.5,
		Color = Color3.new(0, 0, 0),
		Transparency = transparency or 0.2,
		Parent = parent,
	})
end

local function bar(parent, size, position, color)
	local back = create("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = Color3.fromRGB(8, 9, 12),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(back, 4)
	local chip = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Chip,
		BorderSizePixel = 0,
		Parent = back,
	})
	corner(chip, 4)
	local fill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = back,
	})
	corner(fill, 4)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
		Rotation = 90,
		Parent = fill,
	})
	return back, fill, chip
end

----------------------------------------------------------------------------------------------
-- Build

local function buildHUD()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = create("ScreenGui", {
		Name = "CombatHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	-- bottom status block
	local status = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(380, 92),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local healthBack
	healthBack, healthFill, healthChip = bar(status, UDim2.fromOffset(380, 16), UDim2.fromOffset(0, 0), COLORS.Health)
	healthText = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "100",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 13,
		Font = FONT,
		ZIndex = 3,
		Parent = healthBack,
	})
	stroke(healthText, 1.2)
	_, postureFill = bar(status, UDim2.fromOffset(380, 6), UDim2.fromOffset(0, 21), COLORS.Posture)

	local slots = create("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.fromOffset(380, 52),
		BackgroundTransparency = 1,
		Parent = status,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = slots,
	})
	local function slot(key, label)
		local frame = create("Frame", {
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.25,
			Parent = slots,
		})
		corner(frame, 8)
		create(
			"UIStroke",
			{ Thickness = 1.5, Color = Color3.fromRGB(255, 255, 255), Transparency = 0.8, Parent = frame }
		)
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 5),
			BackgroundTransparency = 1,
			Text = key,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 22,
			Font = FONT,
			ZIndex = 2,
			Parent = frame,
		})
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -17),
			BackgroundTransparency = 1,
			Text = label,
			TextColor3 = Color3.fromRGB(200, 205, 215),
			TextSize = 10,
			Font = FONT_BODY,
			ZIndex = 2,
			Parent = frame,
		})
		local shade = create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 3,
			Parent = frame,
		})
		corner(shade, 8)
		local timer = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			Font = FONT,
			ZIndex = 4,
			Parent = frame,
		})
		stroke(timer, 1.2)
		return { Frame = frame, Shade = shade, Timer = timer }
	end
	cooldownSlots.Heavy = slot("R", "HEAVY")
	cooldownSlots.Dodge = slot("Q", "DODGE")
	cooldownSlots.Slide = slot("C", "SLIDE")
	cooldownSlots.Block = slot("F", "PARRY")

	-- combo counter
	comboFrame = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.42, 0),
		Size = UDim2.fromOffset(200, 90),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	comboNumber = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		Text = "0",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 64,
		Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = comboFrame,
	})
	stroke(comboNumber, 3, 0)
	comboScale = create("UIScale", { Parent = comboNumber })
	local hitsLabel = create("TextLabel", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "HIT COMBO",
		TextColor3 = Color3.fromRGB(255, 205, 130),
		TextSize = 20,
		Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = comboFrame,
	})
	stroke(hitsLabel, 2, 0)

	-- parry banner
	bannerLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(600, 80),
		BackgroundTransparency = 1,
		Text = "PERFECT PARRY",
		TextColor3 = COLORS.Gold,
		TextSize = 54,
		Font = FONT,
		TextTransparency = 1,
		Parent = gui,
	})
	create("UIStroke", { Thickness = 3, Color = Color3.fromRGB(70, 40, 0), Transparency = 1, Parent = bannerLabel })
	bannerScale = create("UIScale", { Parent = bannerLabel })

	-- controls
	helpFrame = create("Frame", {
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	corner(helpFrame, 10)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = helpFrame,
	})
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = helpFrame })
	local lines = {
		{ "FIST COMBAT", nil },
		{ "LMB", "Punch (4-hit combo, hold to chain)" },
		{ "F", "Block (tap right before a hit = PARRY)" },
		{ "R", "Heavy (breaks blocks, can be parried)" },
		{ "Q", "Dodge (i-frames, use WASD for direction)" },
		{ "W W / Ctrl", "Sprint" },
		{ "C", "Slide while sprinting (jump to keep speed)" },
		{ "H", "Hide this panel" },
	}
	for i, line in ipairs(lines) do
		local key, desc = line[1], line[2]
		if not desc then
			create("TextLabel", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				Text = key,
				TextColor3 = COLORS.Gold,
				TextSize = 17,
				Font = FONT,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = helpFrame,
			})
		else
			local row = create("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Parent = helpFrame,
			})
			create("TextLabel", {
				Size = UDim2.fromOffset(70, 18),
				BackgroundTransparency = 1,
				Text = key,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 13,
				Font = FONT,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			create("TextLabel", {
				Position = UDim2.fromOffset(72, 0),
				Size = UDim2.new(1, -72, 0, 18),
				BackgroundTransparency = 1,
				Text = desc,
				TextColor3 = Color3.fromRGB(200, 205, 215),
				TextSize = 12,
				Font = FONT_BODY,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Parent = row,
			})
		end
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		helpFrame.Visible = false
	end
end

----------------------------------------------------------------------------------------------
-- Overheads

local overheads = {} -- [Model] = data

local function addOverhead(model)
	if overheads[model] or model == player.Character then
		return
	end
	local head = model:WaitForChild("Head", 5)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (head and humanoid) or overheads[model] then
		return
	end
	local owner = Players:GetPlayerFromCharacter(model)
	local name = model:GetAttribute("DisplayName") or (owner and owner.DisplayName) or model.Name
	local billboard = create("BillboardGui", {
		Name = "Overhead_" .. model.Name,
		Adornee = head,
		Size = UDim2.fromOffset(170, 58),
		StudsOffset = Vector3.new(0, 2.7, 0),
		LightInfluence = 0,
		MaxDistance = 90,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local nameLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		Font = FONT,
		Parent = billboard,
	})
	stroke(nameLabel, 1.5, 0.1)
	local _, fill, chip = bar(billboard, UDim2.fromOffset(150, 7), UDim2.fromOffset(10, 21), COLORS.Health)
	local postureBack, postureBar = bar(billboard, UDim2.fromOffset(150, 4), UDim2.fromOffset(10, 31), COLORS.Posture)
	local tag = create("TextLabel", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 13,
		Font = FONT,
		Parent = billboard,
	})
	stroke(tag, 1.3, 0.1)
	overheads[model] = {
		Gui = billboard,
		Humanoid = humanoid,
		Fill = fill,
		Chip = chip,
		PostureBack = postureBack,
		PostureBar = postureBar,
		Tag = tag,
		Shown = 1,
		ChipValue = 1,
		ChipHold = 0,
	}
end

local function removeOverhead(model)
	local data = overheads[model]
	if data then
		overheads[model] = nil
		data.Gui:Destroy()
	end
end

local function updateOverheads(dt)
	local t = os.clock()
	for model, data in pairs(overheads) do
		if not model.Parent then
			removeOverhead(model)
			continue
		end
		local humanoid = data.Humanoid
		local pct = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		if pct < data.Shown - 0.001 then
			data.ChipHold = t + 0.45
		end
		data.Shown = lerp(data.Shown, pct, 1 - math.exp(-18 * dt))
		if t > data.ChipHold then
			data.ChipValue = lerp(data.ChipValue, data.Shown, 1 - math.exp(-6 * dt))
		end
		data.ChipValue = math.max(data.ChipValue, data.Shown)
		data.Fill.Size = UDim2.fromScale(data.Shown, 1)
		data.Fill.BackgroundColor3 = COLORS.HealthLow:Lerp(COLORS.Health, math.clamp(pct * 1.6, 0, 1))
		data.Chip.Size = UDim2.fromScale(data.ChipValue, 1)

		local posture = model:GetAttribute("Posture") or Config.Block.MaxPosture
		local maxPosture = model:GetAttribute("MaxPosture") or Config.Block.MaxPosture
		local postureFrac = math.clamp(posture / maxPosture, 0, 1)
		data.PostureBack.Visible = postureFrac < 0.995
		data.PostureBar.Size = UDim2.fromScale(postureFrac, 1)
		data.PostureBar.BackgroundColor3 = COLORS.PostureLow:Lerp(COLORS.Posture, postureFrac)

		local tagInfo = STATE_TAGS[model:GetAttribute("CombatState") or ""]
		if tagInfo then
			data.Tag.Text = tagInfo[1]
			data.Tag.TextColor3 = tagInfo[2]
		else
			data.Tag.Text = ""
		end
	end
end

----------------------------------------------------------------------------------------------
-- Public

function HUD.RegisterHit()
	local t = os.clock()
	if t - lastHit > 1.6 then
		comboCount = 0
	end
	comboCount += 1
	lastHit = t
	if comboCount >= 2 and comboFrame then
		comboFrame.Visible = true
		comboNumber.Text = tostring(comboCount)
		comboNumber.TextTransparency = 0
		comboScale.Scale = 1.45
	end
end

function HUD.ParryBanner()
	if not bannerLabel then
		return
	end
	local strokeObj = bannerLabel:FindFirstChildOfClass("UIStroke")
	Util.animate(1.1, function(a)
		if a < 0.1 then
			bannerScale.Scale = lerp(1.8, 0.95, Util.outQuad(a / 0.1))
		elseif a < 0.2 then
			bannerScale.Scale = lerp(0.95, 1, (a - 0.1) / 0.1)
		else
			bannerScale.Scale = 1 + (a - 0.2) * 0.06
		end
		local fade = if a > 0.65 then (a - 0.65) / 0.35 else 0
		bannerLabel.TextTransparency = fade
		if strokeObj then
			strokeObj.Transparency = fade
		end
	end)
end

function HUD.FlashPosture()
	postureFlashUntil = os.clock() + 0.15
end

function HUD.ToggleHelp()
	if helpFrame then
		helpFrame.Visible = not helpFrame.Visible
	end
end

local function updateLocal(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local t = os.clock()
	if humanoid and healthFill then
		local pct = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		if pct < shownHealth - 0.001 then
			chipHoldUntil = t + 0.5
		end
		shownHealth = lerp(shownHealth, pct, 1 - math.exp(-18 * dt))
		if t > chipHoldUntil then
			chipHealth = lerp(chipHealth, shownHealth, 1 - math.exp(-5 * dt))
		end
		chipHealth = math.max(chipHealth, shownHealth)
		healthFill.Size = UDim2.fromScale(shownHealth, 1)
		healthFill.BackgroundColor3 = COLORS.HealthLow:Lerp(COLORS.Health, math.clamp(pct * 1.6, 0, 1))
		healthChip.Size = UDim2.fromScale(chipHealth, 1)
		healthText.Text = tostring(math.ceil(humanoid.Health))

		local posture = character:GetAttribute("Posture") or Config.Block.MaxPosture
		local frac = math.clamp(posture / Config.Block.MaxPosture, 0, 1)
		postureFill.Size = UDim2.fromScale(frac, 1)
		local flash = t < postureFlashUntil
		postureFill.BackgroundColor3 = if flash
			then Color3.new(1, 1, 1)
			else COLORS.PostureLow:Lerp(COLORS.Posture, frac)
	end

	local s = ctx.CombatController.State
	local function setCooldown(slotData, readyAt, total)
		local remaining = readyAt - t
		if remaining > 0 then
			slotData.Shade.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
			slotData.Timer.Text = string.format("%.1f", remaining)
		else
			slotData.Shade.Size = UDim2.fromScale(1, 0)
			slotData.Timer.Text = ""
		end
	end
	setCooldown(cooldownSlots.Heavy, s.HeavyCooldownUntil, Config.Heavy.Cooldown)
	setCooldown(cooldownSlots.Dodge, s.DodgeCooldownUntil, Config.Dodge.Cooldown)
	local blockSlot = cooldownSlots.Block
	blockSlot.Frame.BackgroundColor3 = if s.Blocking then Color3.fromRGB(40, 70, 110) else COLORS.Panel
	cooldownSlots.Slide.Frame.BackgroundColor3 = if ctx.Movement.IsSliding()
		then Color3.fromRGB(110, 80, 40)
		else COLORS.Panel

	if comboFrame and comboFrame.Visible then
		comboScale.Scale = lerp(comboScale.Scale, 1, 1 - math.exp(-14 * dt))
		local since = t - lastHit
		if since > 1.6 then
			comboNumber.TextTransparency = math.clamp((since - 1.6) / 0.3, 0, 1)
			if since > 1.9 then
				comboFrame.Visible = false
			end
		end
	end
end

function HUD.Start(context)
	ctx = context
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	buildHUD()
	for _, model in ipairs(CollectionService:GetTagged("Combatant")) do
		task.spawn(addOverhead, model)
	end
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(function(model)
		task.spawn(addOverhead, model)
	end)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(removeOverhead)
	RunService.RenderStepped:Connect(function(dt)
		updateLocal(dt)
		updateOverheads(dt)
	end)
end

return HUD
