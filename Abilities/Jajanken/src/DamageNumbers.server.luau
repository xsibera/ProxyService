--!strict
-- Test area only: floats what each hit did over the victim. With the parry system (Combat) in the
-- place, every hit from every kit shows (damage, BLOCKED and the chip damage, COUNTER, EVADED);
-- without it, Jajanken's hits (from JajankenServer.OnHit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local ORANGE = Color3.fromRGB(255, 196, 92)
local BLUE = Color3.fromRGB(150, 215, 255)
local GREY = Color3.fromRGB(190, 195, 205)
local WHITE = Color3.fromRGB(240, 242, 248)
local KIT_COLOR = { Jajanken = ORANGE, Killua = BLUE }

local function float(victim: Instance, text: string, color: Color3, scale: number?)
	local head = victim:FindFirstChild("Head") or victim:FindFirstChild("HumanoidRootPart")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "DamageNumber"
	board.Size = UDim2.fromOffset(160 * (scale or 1), 44 * (scale or 1))
	board.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2.4, 0)
	board.AlwaysOnTop = true
	board.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = board
	board.Parent = head
	local rise = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(board, rise, { StudsOffsetWorldSpace = board.StudsOffsetWorldSpace + Vector3.new(0, 2, 0) })
		:Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.2, function()
		board:Destroy()
	end)
end

local function optional(folderName: string, moduleName: string): any
	local folder = ReplicatedStorage:WaitForChild(folderName, 5)
	local module = folder and folder:FindFirstChild(moduleName)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end
local Combat = optional("Combat", "Combat")
local Loadout = optional("Loadout", "Loadout")

if Combat then
	local function named(ability: any): (string, Color3)
		local entry = Loadout and typeof(ability) == "string" and Loadout.Abilities[ability]
		if entry then
			return entry.Name, KIT_COLOR[entry.Kit] or ORANGE
		end
		return if typeof(ability) == "string" then ability else "", WHITE -- M1s and the dummies' punches
	end
	Combat.Resolved.Event:Connect(function(_attacker: Instance, victim: Instance, outcome: string, hit: any)
		local name, color = named(hit.Ability)
		local damage = math.round(hit.Damage or 0)
		if outcome == "Hit" then
			float(victim, string.format("%d  %s", damage, name), color)
		elseif outcome == "Blocked" then
			local chip = (hit.Damage or 0) * Combat.Settings.ChipDamage
			float(victim, string.format("BLOCKED  %.1f", chip), GREY, 0.8)
		elseif outcome == "Countered" then
			float(victim, "COUNTER", BLUE)
		elseif outcome == "Evaded" then
			float(victim, "EVADED", GREY, 0.7)
		end -- Parried and GuardBroken: CombatClient shows those
	end)
else
	local server = ServerScriptService:WaitForChild("JajankenServer")
	local onHit = server:WaitForChild("OnHit") :: BindableEvent
	onHit.Event:Connect(function(_attacker: Player, victim: Model, mode: string, damage: number, charge: number)
		float(victim, string.format("%d  %s %d%%", math.round(damage), mode, math.round(charge * 100)), ORANGE)
	end)
end
