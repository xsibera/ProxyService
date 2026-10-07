--!strict
--[[
	CombatClient (StarterPlayer > StarterPlayerScripts): blocking and parrying for this player, how a
	hit looks on them, and the parry / block / guard-break effects everyone sees.

	F (gamepad L1, or the on-screen Block button) - press to parry, hold to block. The parry window
	is the first Combat.Settings.ParryWindow seconds after the press; see Combat for the rules.
	The server decides everything; this only shows it: the block pose while the Blocking attribute is
	on, a reaction for as long as StunnedUntil lasts (by StunKind), the guard bar, and a word on
	screen when you parry, get parried or get your guard broken.
]]

local ContextActionService = game:GetService("ContextActionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Folder = ReplicatedStorage:WaitForChild("Combat")
local Combat = require(Folder:WaitForChild("Combat")) :: any
local VFX = require(Folder:WaitForChild("CombatVFX")) :: any
local Remote = Folder:WaitForChild("Remote") :: RemoteEvent
local AnimationFolder = Folder:WaitForChild("Animations")

local BLOCK_KEYS = { Enum.KeyCode.F, Enum.KeyCode.ButtonL1 }
-- the reaction played for each kind of stun
local REACTION = {
	Hit = "Hit",
	Launch = "Hit",
	Shock = "Shocked",
	GuardBreak = "GuardBreak",
	Parried = "Parried",
	Countered = "Hit",
}
local LOOPED = { Block = true, Shocked = true }

--------------------------------------------------------------------------- animations

local warned = false
local sources: { [string]: Animation | false } = {}

local function source(name: string): Animation?
	local cached = sources[name]
	if cached ~= nil then
		return cached or nil
	end
	local item = AnimationFolder:FindFirstChild(name)
	if not (item and item:IsA("Animation")) then
		return nil
	end
	local result: Animation? = nil
	if item.AnimationId ~= "" then
		result = item
	else
		-- unpublished: register the KeyframeSequence for a temporary id (works in Studio only)
		local sequence = item:FindFirstChildOfClass("KeyframeSequence")
		local ok, id = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence :: KeyframeSequence)
		end)
		if ok and typeof(id) == "string" then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			result = anim
		elseif not warned then
			warned = true
			warn("Combat: publish the reaction animations and set their AnimationIds in Combat.Animations")
		end
	end
	sources[name] = result or false
	return result
end

type Tracks = { [string]: AnimationTrack }

local function loadTracks(character: Model): Tracks
	local tracks: Tracks = {}
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return tracks
	end
	for _, item in AnimationFolder:GetChildren() do
		local anim = source(item.Name)
		if anim then
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action2
				track.Looped = LOOPED[item.Name] == true
				tracks[item.Name] = track
			end
		end
	end
	return tracks
end

local function play(tracks: Tracks, name: string, fade: number?)
	local track = tracks[name]
	if track then
		track:Play(fade or 0.08)
	end
end

local function stop(tracks: Tracks, name: string, fade: number?)
	local track = tracks[name]
	if track and track.IsPlaying then
		track:Stop(fade or 0.12)
	end
end

--------------------------------------------------------------------------- the guard bar and words on screen

local gui = Instance.new("ScreenGui")
gui.Name = "CombatUI"
gui.ResetOnSpawn = false

local guardBar = Instance.new("Frame")
guardBar.Name = "Guard"
guardBar.AnchorPoint = Vector2.new(0.5, 1)
guardBar.Position = UDim2.new(0.5, 0, 1, -86)
guardBar.Size = UDim2.fromOffset(220, 6)
guardBar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
guardBar.BackgroundTransparency = 0.3
guardBar.BorderSizePixel = 0
guardBar.Visible = false
guardBar.Parent = gui
local guardCorner = Instance.new("UICorner")
guardCorner.CornerRadius = UDim.new(1, 0)
guardCorner.Parent = guardBar
local guardFill = Instance.new("Frame")
guardFill.Name = "Fill"
guardFill.Size = UDim2.fromScale(1, 1)
guardFill.BackgroundColor3 = Color3.fromRGB(210, 220, 240)
guardFill.BorderSizePixel = 0
guardFill.Parent = guardBar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = guardFill

local word = Instance.new("TextLabel")
word.Name = "Word"
word.AnchorPoint = Vector2.new(0.5, 0.5)
word.Position = UDim2.fromScale(0.5, 0.36)
word.Size = UDim2.fromOffset(400, 40)
word.BackgroundTransparency = 1
word.Font = Enum.Font.GothamBlack
word.TextSize = 30
word.TextColor3 = Color3.new(1, 1, 1)
word.TextStrokeTransparency = 0.4
word.TextTransparency = 1
word.TextStrokeColor3 = Color3.new(0, 0, 0)
word.Parent = gui
local wordTween: Tween? = nil

local function say(text: string, color: Color3)
	if wordTween then
		wordTween:Cancel()
	end
	word.Text = text
	word.TextColor3 = color
	word.TextTransparency = 0
	word.TextStrokeTransparency = 0.4
	word.Size = UDim2.fromOffset(440, 46)
	wordTween = TweenService:Create(word, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Size = UDim2.fromOffset(400, 40),
	});
	(wordTween :: Tween):Play()
end

gui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------- blocking

local holding = false
local myTracks: Tracks = {}

local function blockInput(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		holding = true
		local character = player.Character
		if
			character
			and Combat.alive(character)
			and not Combat.isStunned(character)
			and not Combat.isBusy(character)
		then
			play(myTracks, "Parry", 0.04) -- the parry flourish at once; the block pose follows from the attribute
		end
		Remote:FireServer("Block", true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		holding = false
		Remote:FireServer("Block", false)
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("CombatBlock", blockInput, true, table.unpack(BLOCK_KEYS))
ContextActionService:SetTitle("CombatBlock", "Block")

--------------------------------------------------------------------------- reactions: this player and NPCs

-- the block pose while Blocking is on, the parry flourish, and a reaction while StunnedUntil lasts.
-- For this player's character (other players' clients animate theirs, and it replicates) and for
-- every NPC (a test dummy, say): nobody owns those, so each client animates them for itself.
local function animate(character: Model, mine: boolean): { RBXScriptConnection }
	local tracks = loadTracks(character)
	if mine then
		myTracks = tracks
	end
	local connections: { RBXScriptConnection } = {}
	local reacting: string? = nil
	local function onBlocking()
		if character:GetAttribute("Blocking") then
			play(tracks, "Block", 0.1)
		else
			stop(tracks, "Block", 0.15)
			stop(tracks, "Parry", 0.1)
		end
	end
	local function onParry() -- NPCs: a parry opened (this player's plays on the key press)
		if typeof(character:GetAttribute("ParryAt")) == "number" and not reacting then
			play(tracks, "Parry", 0.04)
		end
	end
	local function onStun()
		local untilTime = character:GetAttribute("StunnedUntil")
		local left = if typeof(untilTime) == "number" then untilTime - workspace:GetServerTimeNow() else 0
		if left <= 0 then
			return
		end
		local kind = character:GetAttribute("StunKind")
		local name = REACTION[if typeof(kind) == "string" then kind else "Hit"] or "Hit"
		if reacting and reacting ~= name then
			stop(tracks, reacting, 0.05)
		end
		reacting = name
		stop(tracks, "Block", 0.05)
		play(tracks, name, 0.05)
		if mine and kind == "GuardBreak" then
			say("GUARD BROKEN", Color3.fromRGB(255, 120, 90))
		end
		task.delay(left, function()
			local now = workspace:GetServerTimeNow()
			local current = character:GetAttribute("StunnedUntil")
			if reacting == name and (typeof(current) ~= "number" or current <= now + 0.02) then
				stop(tracks, name, 0.2)
				reacting = nil
				if mine and holding then -- still holding F: back into the block
					Remote:FireServer("Block", true)
				elseif character:GetAttribute("Blocking") then
					play(tracks, "Block", 0.15)
				end
			end
		end)
	end
	table.insert(connections, character:GetAttributeChangedSignal("Blocking"):Connect(onBlocking))
	table.insert(connections, character:GetAttributeChangedSignal("StunnedUntil"):Connect(onStun))
	if not mine then
		table.insert(connections, character:GetAttributeChangedSignal("ParryAt"):Connect(onParry))
		if character:GetAttribute("Blocking") then
			onBlocking()
		end
	end
	return connections
end

local mine: { RBXScriptConnection } = {}
local function onCharacter(character: Model)
	for _, c in mine do
		c:Disconnect()
	end
	mine = animate(character, true)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

local npcs: { [Model]: boolean } = {}
local function isCharacter(model: Model): boolean
	return Players:GetPlayerFromCharacter(model) ~= nil
end
local function maybeNpc(humanoid: Instance)
	if not humanoid:IsA("Humanoid") then
		return
	end
	task.defer(function() -- a player's character is theirs by the time it's in the world
		local model = humanoid.Parent
		if
			not (model and model:IsA("Model"))
			or npcs[model]
			or isCharacter(model)
			or not model:IsDescendantOf(workspace)
		then
			return
		end
		npcs[model] = true
		local connections = animate(model, false)
		local gone: RBXScriptConnection
		gone = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				gone:Disconnect()
				for _, c in connections do
					c:Disconnect()
				end
				npcs[model] = nil
			end
		end)
	end)
end
workspace.DescendantAdded:Connect(maybeNpc)
for _, d in workspace:GetDescendants() do
	maybeNpc(d)
end

--------------------------------------------------------------------------- what everyone sees

local function ignoreOf(...: Instance?): { Instance }
	local list = {}
	for _, item in { ... } do
		if item then
			table.insert(list, item)
		end
	end
	return list
end

local function facingFrame(at: Vector3, toward: Instance?): CFrame
	local root = toward and toward:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - at).Magnitude > 0.1 then
		return CFrame.lookAt(at, root.Position)
	end
	return CFrame.new(at)
end

Remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
	if kind == "Parried" then -- a: the parrier, b: the attacker, c: where
		VFX:Play("ParrySpark", facingFrame(c, b), { Ignore = ignoreOf(a, b) })
		VFX:Sound("Parry", c, 1)
		if a == player.Character then
			say("PARRY", Color3.fromRGB(255, 236, 160))
		elseif b == player.Character then
			say("PARRIED", Color3.fromRGB(255, 140, 110))
		end
	elseif kind == "Blocked" then -- a: the blocker, b: where
		VFX:Play("BlockSpark", CFrame.new(b), { Ignore = ignoreOf(a) })
		VFX:Sound("Block", b, 0.8)
	elseif kind == "GuardBroken" then -- a: the blocker, b: where
		VFX:Play("GuardBreak", CFrame.new(b), { Ignore = ignoreOf(a) })
		VFX:Sound("GuardBreak", b, 1)
	end
end)

--------------------------------------------------------------------------- every frame: the guard bar

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		guardBar.Visible = false
		return
	end
	local guard = Combat.guard(character)
	local max = Combat.Settings.GuardMax
	guardBar.Visible = character:GetAttribute("Blocking") == true or guard < max - 0.5
	local share = math.clamp(guard / max, 0, 1)
	guardFill.Size = UDim2.fromScale(share, 1)
	guardFill.BackgroundColor3 = Color3.fromRGB(255, 110, 90):Lerp(Color3.fromRGB(210, 220, 240), share)
end)
