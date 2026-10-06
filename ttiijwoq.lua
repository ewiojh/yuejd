-- 持续生效的改移速脚本
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lplr = Players.LocalPlayer

local SPEED = 100

local conn
conn = RunService.Heartbeat:Connect(function()
    local char = lplr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed ~= SPEED then
        hum.WalkSpeed = SPEED
    end
end)

print("WalkSpeed locked to: " .. SPEED)