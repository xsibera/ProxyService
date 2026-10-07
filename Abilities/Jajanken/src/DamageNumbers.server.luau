--!strict
-- Test area only: floats each Jajanken hit's damage over the victim.

local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local server = ServerScriptService:WaitForChild("JajankenServer")
local onHit = server:WaitForChild("OnHit") :: BindableEvent

onHit.Event:Connect(function(_attacker: Player, victim: Model, mode: string, damage: number, charge: number)
	local head = victim:FindFirstChild("Head") or victim:FindFirstChild("HumanoidRootPart")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "JajankenDamage"
	board.Size = UDim2.fromOffset(140, 44)
	board.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2.4, 0)
	board.AlwaysOnTop = true
	board.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 196, 92)
	label.TextStrokeTransparency = 0.2
	label.Text = string.format("%d  %s %d%%", math.round(damage), mode, math.round(charge * 100))
	label.Parent = board
	board.Parent = head
	local rise = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(board, rise, { StudsOffsetWorldSpace = board.StudsOffsetWorldSpace + Vector3.new(0, 2, 0) })
		:Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.2, function()
		board:Destroy()
	end)
end)
