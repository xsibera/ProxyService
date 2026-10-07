--!strict
--[[
	LoadoutClient (StarterPlayer > StarterPlayerScripts): the hotbar, the ability menu, and the four
	ability keys.

	The keys (Loadout.Slots: Z X C V, gamepad X Y B R1, on-screen buttons on touch devices) belong to
	this script: a press goes to whichever kit registered the ability in that slot (Loadout.bind).
	Press M (or the Abilities button) to open the menu: pick an ability, then a key - or a key, then
	an ability. Presets fill all four at once. Right-click a key in the menu to empty it.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Folder = ReplicatedStorage:WaitForChild("Loadout")
local Loadout = require(Folder:WaitForChild("Loadout")) :: any
local Remote = Folder:WaitForChild("Remote") :: RemoteEvent

local ACCENT = {
	Gon = Color3.fromRGB(255, 140, 40),
	Killua = Color3.fromRGB(120, 205, 255),
	Leorio = Color3.fromRGB(110, 240, 210),
}
local PANEL = Color3.fromRGB(18, 20, 26)
local CARD = Color3.fromRGB(30, 33, 42)
local TEXT = Color3.fromRGB(236, 238, 245)
local DIM = Color3.fromRGB(150, 156, 172)
local DENY = Color3.fromRGB(150, 36, 30)

local function accentOf(ability: string): Color3
	local info = Loadout.Abilities[ability]
	return if info then ACCENT[info.Character] or TEXT else DIM
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: number, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font
	l.TextColor3 = color
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function keyName(slot: number): string
	local key = Loadout.Slots[slot]
	return if key then key.Name else tostring(slot)
end

local gui = Instance.new("ScreenGui")
gui.Name = "LoadoutUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false

--------------------------------------------------------------------------- the hotbar

type HotSlot = { frame: Frame, name: TextLabel, shade: Frame, seconds: TextLabel, bar: Frame, border: UIStroke }
local hotbar: { HotSlot } = {}

local bar = Instance.new("Frame")
bar.Name = "Hotbar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -14)
local BAR_WIDTH = #Loadout.Slots * 104 - 8
bar.Size = UDim2.fromOffset(BAR_WIDTH, 64)
bar.BackgroundTransparency = 1
bar.Parent = gui

for slot = 1, #Loadout.Slots do
	local frame = Instance.new("Frame")
	frame.Name = "Slot" .. slot
	frame.Position = UDim2.fromOffset((slot - 1) * 104, 0)
	frame.Size = UDim2.fromOffset(96, 64)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.15
	frame.ClipsDescendants = true
	frame.Parent = bar
	corner(frame, 8)
	local border = stroke(frame, DIM, 1.5, 0.4)
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(1, 0, 0, 3)
	accentBar.BorderSizePixel = 0
	accentBar.BackgroundColor3 = DIM
	accentBar.Parent = frame
	local key = label(frame, keyName(slot), 12, Enum.Font.GothamBlack, DIM)
	key.Position = UDim2.fromOffset(7, 6)
	key.Size = UDim2.fromOffset(20, 14)
	key.TextXAlignment = Enum.TextXAlignment.Left
	local name = label(frame, "", 13, Enum.Font.GothamBold, TEXT)
	name.Name = "AbilityName"
	name.Position = UDim2.fromOffset(4, 20)
	name.Size = UDim2.new(1, -8, 1, -24)
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.ZIndex = 2
	shade.Parent = frame
	local seconds = label(frame, "", 18, Enum.Font.GothamBlack, TEXT)
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.ZIndex = 3
	hotbar[slot] = { frame = frame, name = name, shade = shade, seconds = seconds, bar = accentBar, border = border }
end

--------------------------------------------------------------------------- the menu

-- one column of cards per character, ~215 px each
local characterCount = 0
do
	local seen = {}
	for _, ability in Loadout.Order do
		local character = Loadout.Abilities[ability].Character
		if not seen[character] then
			seen[character] = true
			characterCount += 1
		end
	end
end
local MENU_W = math.max(660, 40 + 215 * characterCount)
local MENU_H = 470

local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.AnchorPoint = Vector2.new(0.5, 0.5)
menu.Position = UDim2.fromScale(0.5, 0.47)
menu.Size = UDim2.fromOffset(MENU_W, MENU_H)
menu.BackgroundColor3 = PANEL
menu.BackgroundTransparency = 0.05
menu.Visible = false
menu.Parent = gui
corner(menu, 12)
stroke(menu, Color3.fromRGB(70, 76, 92), 1.5)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(MENU_W, MENU_H)
sizeLimit.Parent = menu
local scale = Instance.new("UIScale")
scale.Parent = menu

local title = label(menu, "Abilities", 22, Enum.Font.GothamBlack, TEXT)
title.Position = UDim2.fromOffset(20, 14)
title.Size = UDim2.fromOffset(200, 28)
title.TextXAlignment = Enum.TextXAlignment.Left
local help = label(menu, "Pick an ability, then a key.", 13, Enum.Font.Gotham, DIM)
help.Name = "Help"
help.Position = UDim2.fromOffset(20, 42)
help.Size = UDim2.new(1, -40, 0, 18)
help.TextXAlignment = Enum.TextXAlignment.Left

local close = Instance.new("TextButton")
close.Name = "Close"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 14)
close.Size = UDim2.fromOffset(30, 30)
close.BackgroundColor3 = CARD
close.Text = "X"
close.Font = Enum.Font.GothamBlack
close.TextSize = 14
close.TextColor3 = TEXT
close.AutoButtonColor = true
close.Parent = menu
corner(close, 6)

-- presets
local presetRow = Instance.new("Frame")
presetRow.Name = "Presets"
presetRow.AnchorPoint = Vector2.new(1, 0)
presetRow.Position = UDim2.new(1, -54, 0, 14)
presetRow.Size = UDim2.fromOffset(118 * #Loadout.PresetOrder, 30)
presetRow.BackgroundTransparency = 1
presetRow.Parent = menu
local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
presetLayout.Padding = UDim.new(0, 8)
presetLayout.Parent = presetRow
for i, name in Loadout.PresetOrder do
	local b = Instance.new("TextButton")
	b.Name = "Preset" .. name
	b.LayoutOrder = i
	b.Size = UDim2.fromOffset(110, 30)
	b.BackgroundColor3 = CARD
	b.Text = "All " .. name
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = ACCENT[name] or TEXT
	b.Parent = presetRow
	corner(b, 6)
	stroke(b, ACCENT[name] or TEXT, 1, 0.5)
	b.Activated:Connect(function()
		Remote:FireServer("Preset", name)
	end)
end

-- the abilities, one column per character
type Card = { button: TextButton, badge: TextLabel, border: UIStroke }
local cards: { [string]: Card } = {}
local columns: { [string]: Frame } = {}
local columnOrder: { string } = {}
for _, ability in Loadout.Order do
	local character = Loadout.Abilities[ability].Character
	if not columns[character] then
		table.insert(columnOrder, character)
		local column = Instance.new("Frame")
		column.Name = character
		column.BackgroundTransparency = 1
		column.Parent = menu
		local header = label(column, character, 16, Enum.Font.GothamBlack, ACCENT[character] or TEXT)
		header.Size = UDim2.new(1, 0, 0, 22)
		header.TextXAlignment = Enum.TextXAlignment.Left
		local list = Instance.new("Frame")
		list.Name = "List"
		list.Position = UDim2.fromOffset(0, 26)
		list.Size = UDim2.new(1, 0, 1, -26)
		list.BackgroundTransparency = 1
		list.Parent = column
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		columns[character] = column
	end
end
for i, character in columnOrder do
	local column = columns[character]
	local width = 1 / #columnOrder
	column.Position = UDim2.new(width * (i - 1), if i == 1 then 20 else 8, 0, 70)
	column.Size = UDim2.new(width, -28, 1, -170)
end

local selectedAbility: string? = nil
local selectedSlot: number? = nil
local refresh: () -> ()

for order, ability in Loadout.Order do
	local info = Loadout.Abilities[ability]
	local list = columns[info.Character]:FindFirstChild("List") :: Frame
	local button = Instance.new("TextButton")
	button.Name = ability
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 58)
	button.BackgroundColor3 = CARD
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = list
	corner(button, 8)
	local border = stroke(button, accentOf(ability), 1.5, 0.75)
	local name = label(button, info.Name, 15, Enum.Font.GothamBold, TEXT)
	name.Position = UDim2.fromOffset(12, 6)
	name.Size = UDim2.new(1, -60, 0, 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local hint = label(button, info.Hint, 11, Enum.Font.Gotham, DIM)
	hint.Position = UDim2.fromOffset(12, 25)
	hint.Size = UDim2.new(1, -60, 0, 30)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	local badge = label(button, "", 15, Enum.Font.GothamBlack, PANEL)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -12, 0.5, 0)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundColor3 = accentOf(ability)
	badge.BackgroundTransparency = 1
	corner(badge, 6)
	cards[ability] = { button = button, badge = badge, border = border }
	button.Activated:Connect(function()
		if selectedSlot then
			Remote:FireServer("Set", selectedSlot, ability)
			selectedSlot, selectedAbility = nil, nil
		else
			selectedAbility = if selectedAbility == ability then nil else ability
		end
		refresh()
	end)
end

-- the four keys, along the bottom of the menu
type MenuSlot = { button: TextButton, name: TextLabel, border: UIStroke }
local menuSlots: { MenuSlot } = {}
local slotRow = Instance.new("Frame")
slotRow.Name = "Keys"
slotRow.AnchorPoint = Vector2.new(0.5, 1)
slotRow.Position = UDim2.new(0.5, 0, 1, -18)
slotRow.Size = UDim2.new(1, -40, 0, 66)
slotRow.BackgroundTransparency = 1
slotRow.Parent = menu
for slot = 1, #Loadout.Slots do
	local button = Instance.new("TextButton")
	button.Name = "Key" .. slot
	button.Position = UDim2.new((slot - 1) / #Loadout.Slots, 4, 0, 0)
	button.Size = UDim2.new(1 / #Loadout.Slots, -8, 1, 0)
	button.BackgroundColor3 = CARD
	button.Text = ""
	button.Parent = slotRow
	corner(button, 8)
	local border = stroke(button, DIM, 1.5, 0.5)
	local key = label(button, keyName(slot), 13, Enum.Font.GothamBlack, DIM)
	key.Position = UDim2.fromOffset(10, 6)
	key.Size = UDim2.fromOffset(24, 16)
	key.TextXAlignment = Enum.TextXAlignment.Left
	local name = label(button, "", 14, Enum.Font.GothamBold, TEXT)
	name.Position = UDim2.fromOffset(8, 22)
	name.Size = UDim2.new(1, -16, 1, -26)
	menuSlots[slot] = { button = button, name = name, border = border }
	button.Activated:Connect(function()
		if selectedAbility then
			Remote:FireServer("Set", slot, selectedAbility)
			selectedSlot, selectedAbility = nil, nil
		else
			selectedSlot = if selectedSlot == slot then nil else slot
		end
		refresh()
	end)
	button.MouseButton2Click:Connect(function()
		Remote:FireServer("Set", slot, "")
		selectedSlot, selectedAbility = nil, nil
		refresh()
	end)
end

-- the button that opens it
local open = Instance.new("TextButton")
open.Name = "OpenMenu"
open.AnchorPoint = Vector2.new(0, 1)
open.Position = UDim2.new(0.5, BAR_WIDTH / 2 + 10, 1, -14)
open.Size = UDim2.fromOffset(92, 30)
open.BackgroundColor3 = PANEL
open.BackgroundTransparency = 0.15
open.Text = "Abilities [" .. Loadout.MenuKey.Name .. "]"
open.Font = Enum.Font.GothamBold
open.TextSize = 12
open.TextColor3 = TEXT
open.Parent = gui
corner(open, 6)
stroke(open, DIM, 1, 0.4)

local function setMenu(visible: boolean)
	menu.Visible = visible
	selectedAbility, selectedSlot = nil, nil
	refresh()
end
open.Activated:Connect(function()
	setMenu(not menu.Visible)
end)
close.Activated:Connect(function()
	setMenu(false)
end)

--------------------------------------------------------------------------- keeping it all in step

local function displayName(ability: string): string
	local info = Loadout.Abilities[ability]
	return if info then info.Name else ""
end

local actions: { string } = {}

function refresh()
	local slots = Loadout.get(player)
	for slot, hot in hotbar do
		local ability = slots[slot]
		hot.name.Text = if ability ~= "" then displayName(ability) else "-"
		hot.name.TextColor3 = if ability ~= "" then TEXT else DIM
		hot.bar.BackgroundColor3 = accentOf(ability)
		hot.border.Color = accentOf(ability)
		local entry = menuSlots[slot]
		entry.name.Text = if ability ~= "" then displayName(ability) else "empty"
		entry.name.TextColor3 = if ability ~= "" then accentOf(ability) else DIM
		entry.border.Color = if selectedSlot == slot then TEXT else accentOf(ability)
		entry.border.Transparency = if selectedSlot == slot then 0 else 0.5
		entry.border.Thickness = if selectedSlot == slot then 2.5 else 1.5
		if actions[slot] then
			ContextActionService:SetTitle(actions[slot], if ability ~= "" then displayName(ability) else "")
		end
	end
	for ability, card in cards do
		local slot = Loadout.slotOf(player, ability)
		card.badge.Text = if slot then keyName(slot) else ""
		card.badge.BackgroundTransparency = if slot then 0 else 1
		card.border.Transparency = if selectedAbility == ability then 0 elseif slot then 0.35 else 0.75
		card.border.Thickness = if selectedAbility == ability then 2.5 else 1.5
	end
	help.Text = if selectedAbility
		then "Now pick a key for " .. displayName(selectedAbility) .. "."
		elseif selectedSlot then "Now pick an ability for " .. keyName(selectedSlot) .. "."
		else "Pick an ability, then a key. Right-click a key to empty it."
end

player:GetAttributeChangedSignal("Loadout"):Connect(refresh)

--------------------------------------------------------------------------- the keys

-- which ability got the press, so the release goes to the same one even if the loadout changed
local pressed: { [number]: string } = {}

for slot = 1, #Loadout.Slots do
	local action = "AbilitySlot" .. slot
	actions[slot] = action
	local inputs = { Loadout.Slots[slot] }
	if Loadout.GamepadSlots[slot] then
		table.insert(inputs, Loadout.GamepadSlots[slot])
	end
	ContextActionService:BindAction(action, function(_, state: Enum.UserInputState)
		local ability: string?
		if state == Enum.UserInputState.Begin then
			ability = Loadout.get(player)[slot]
			pressed[slot] = ability
		else
			ability = pressed[slot]
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				pressed[slot] = nil
			end
		end
		local handler = if ability and ability ~= "" then Loadout.handler(ability) else nil
		if handler then
			handler(state)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, true, table.unpack(inputs))
end

ContextActionService:BindAction("LoadoutMenu", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setMenu(not menu.Visible)
	end
	return Enum.ContextActionResult.Sink
end, false, Loadout.MenuKey)

--------------------------------------------------------------------------- every frame: cooldowns

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local slots = Loadout.get(player)
	for slot, hot in hotbar do
		local ability = slots[slot]
		local left, total = Loadout.cooldown(ability, now)
		hot.shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
		hot.seconds.Text = if left > 0.05 then string.format(if left < 10 then "%.1f" else "%d", left) else ""
		local sinceDeny = now - Loadout.deniedAt(ability)
		hot.frame.BackgroundColor3 = if sinceDeny < 0.3 then DENY:Lerp(PANEL, sinceDeny / 0.3) else PANEL
	end
	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / (MENU_W + 40), viewport.Y / (MENU_H + 50)), 0.5, 1)
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
refresh()

-- a quick nudge the first time, so the menu gets found
local tip = label(gui, "Press " .. Loadout.MenuKey.Name .. " to change your abilities", 14, Enum.Font.GothamBold, TEXT)
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.Position = UDim2.new(0.5, 0, 1, -86)
tip.Size = UDim2.fromOffset(360, 20)
tip.TextStrokeTransparency = 0.5
task.delay(6, function()
	TweenService:Create(tip, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end)
