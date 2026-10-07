--!strict
-- Test dummies: each one is put back where it started a few seconds after it's knocked out.

local RESPAWN_AFTER = 3

local function watch(dummy: Model, original: Model)
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		task.wait(RESPAWN_AFTER)
		local fresh = original:Clone()
		dummy:Destroy()
		fresh.Parent = script.Parent
		watch(fresh, original)
	end)
end

for _, dummy in script.Parent:GetChildren() do
	if dummy:IsA("Model") and dummy:FindFirstChildOfClass("Humanoid") then
		watch(dummy, dummy:Clone())
	end
end
