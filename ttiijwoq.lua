-- ============================================================
-- Wanted 脚本 → Obsidian 版（只要功能）
-- PlaceId: 14438406081
-- ============================================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local RootPart = nil

-- ============================================================
-- 弹道颜色
-- ============================================================
getgenv().TrailColors = {
	StartColor = Color3.fromRGB(0, 170, 255),
	EndColor = Color3.fromRGB(255, 0, 0),
	MiddleColor1 = Color3.fromRGB(255, 0, 255),
	MiddleColor2 = Color3.fromRGB(255, 255, 0)
}
getgenv().TrailTransparency = 0.3
getgenv().ShootInterval = 0.2

-- ============================================================
-- 愤怒机器人
-- ============================================================
local AutoShoot = false
local ShooterModule = nil
local OriginalShoot = nil

local function createBezierCurve(p0, p1, p2, t)
	return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

local function createBeautifulTrail(origin, targetPos)
	local trailContainer = Instance.new("Folder")
	trailContainer.Name = "MagicTrail"
	trailContainer.Parent = Workspace

	local midPoint = (origin + targetPos) / 2
	local direction = (targetPos - origin).Unit
	local perpendicular = Vector3.new(-direction.Z, direction.Y, direction.X) * 3
	local controlPoint = midPoint + perpendicular + Vector3.new(0, math.random(-3, 3), 0)

	local curvePoints = {}
	local numSegments = 20
	for i = 0, numSegments do
		local t = i / numSegments
		table.insert(curvePoints, createBezierCurve(origin, controlPoint, targetPos, t))
	end

	local transparency = getgenv().TrailTransparency or 0.3

	for i = 1, #curvePoints - 1 do
		local startPoint = curvePoints[i]
		local endPoint = curvePoints[i + 1]
		local distance = (endPoint - startPoint).Magnitude

		local beamPart = Instance.new("Part")
		beamPart.Size = Vector3.new(0.15, 0.15, distance)
		beamPart.Anchored = true
		beamPart.CanCollide = false
		beamPart.Material = Enum.Material.Neon
		beamPart.Transparency = transparency
		beamPart.CFrame = CFrame.new(startPoint, endPoint) * CFrame.new(0, 0, -distance / 2)
		beamPart.Parent = trailContainer

		local t = i / (#curvePoints - 1)
		local color
		if t < 0.3 then
			color = getgenv().TrailColors.StartColor
		elseif t < 0.6 then
			color = getgenv().TrailColors.MiddleColor1
		elseif t < 0.9 then
			color = getgenv().TrailColors.MiddleColor2
		else
			color = getgenv().TrailColors.EndColor
		end
		beamPart.Color = color

		local pointLight = Instance.new("PointLight")
		pointLight.Brightness = 5
		pointLight.Range = 3
		pointLight.Color = color
		pointLight.Parent = beamPart

		local particles = Instance.new("ParticleEmitter")
		particles.Size = NumberSequence.new(0.1, 0.3)
		particles.Transparency = NumberSequence.new(0.3, 0.8)
		particles.Lifetime = NumberRange.new(0.5, 1)
		particles.Rate = 50
		particles.Speed = NumberRange.new(1, 2)
		particles.VelocitySpread = 180
		particles.Color = ColorSequence.new(color)
		particles.Parent = beamPart
	end

	task.delay(1.5, function()
		if trailContainer and trailContainer.Parent then
			trailContainer:Destroy()
		end
	end)

	return trailContainer
end

local function hasLineOfSight(shooterPos, targetPos)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
	raycastParams.IgnoreWater = true

	local direction = (targetPos - shooterPos).Unit
	local distance = (targetPos - shooterPos).Magnitude
	local raycastResult = Workspace:Raycast(shooterPos, direction * distance, raycastParams)

	if raycastResult then
		local hitPart = raycastResult.Instance
		if hitPart then
			local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
			if hitCharacter and hitCharacter:FindFirstChild("Humanoid") then
				return true
			end
			return false
		end
	end
	return true
end

local function enableRageBot()
	task.spawn(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local clientTool = ReplicatedStorage:FindFirstChild("Client", true)
			and ReplicatedStorage.Client:FindFirstChild("Wanted", true)
			and ReplicatedStorage.Client.Wanted:FindFirstChild("Objects", true)
			and ReplicatedStorage.Client.Wanted.Objects:FindFirstChild("ClientTool", true)
			and ReplicatedStorage.Client.Wanted.Objects.ClientTool:FindFirstChild("Components", true)
			and ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components:FindFirstChild("Guns", true)
			and ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns:FindFirstChild("Shooter", true)

		if not clientTool then
			Library:Notify({Title = "错误", Description = "未找到枪械模块", Time = 3})
			AutoShoot = false
			return
		end

		ShooterModule = require(clientTool)
		OriginalShoot = ShooterModule._shoot

		ShooterModule._shoot = function(self)
			if not self or not self.tool then
				return OriginalShoot(self)
			end

			local LocalCharacter = LocalPlayer.Character
			if not LocalCharacter then
				return OriginalShoot(self)
			end

			local shooterPos = LocalCharacter.HumanoidRootPart and LocalCharacter.HumanoidRootPart.Position
				or LocalCharacter.PrimaryPart.Position

			local nearestPlayer = nil
			local nearestDistance = math.huge

			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					local targetPos = player.Character.HumanoidRootPart.Position
					local distance = (shooterPos - targetPos).Magnitude
					if hasLineOfSight(shooterPos, targetPos) and distance < nearestDistance then
						nearestDistance = distance
						nearestPlayer = player
					end
				end
			end

			if nearestPlayer and nearestPlayer.Character and nearestPlayer.Character:FindFirstChild("HumanoidRootPart") then
				local targetPos = nearestPlayer.Character.HumanoidRootPart.Position
				self.aimpoint = targetPos
				self.aimpoint2 = targetPos

				if self.tool.model and self.tool.model.PrimaryPart then
					createBeautifulTrail(self.tool.model.PrimaryPart.Position, targetPos)
				else
					createBeautifulTrail(shooterPos, targetPos)
				end

				if self.tool then
					self.tool.shooting = true
					self.tool.fireDebounce = 0
					self.tool.fireMode = "auto"
				end
			else
				if self.tool then
					self.tool.shooting = false
				end
			end

			return OriginalShoot(self)
		end

		while AutoShoot do
			if ShooterModule and ShooterModule._shoot then
				local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
				if tool then
					local shooter = tool:FindFirstChild("Shooter") or {tool = tool}
					pcall(function()
						ShooterModule._shoot(shooter)
					end)
				end
			end
			task.wait(getgenv().ShootInterval or 0.2)
		end

		if OriginalShoot then
			ShooterModule._shoot = OriginalShoot
		end
	end)
end

local function disableRageBot()
	if ShooterModule and OriginalShoot then
		ShooterModule._shoot = OriginalShoot
	end
end

-- ============================================================
-- 自动刷钱
-- ============================================================
local GizmoFolder = workspace:FindFirstChild("Local") and workspace.Local:FindFirstChild("Gizmos") and workspace.Local.Gizmos:FindFirstChild("White") or nil

local PatrolPoints = {
	Vector3.new(-1137, 78, -1953),
	Vector3.new(-44, 63, -2083),
	Vector3.new(194, 60, -2884),
	Vector3.new(-412, 106, -1301),
	Vector3.new(-377, 410, -741),
	Vector3.new(-985, 380, -1145),
	Vector3.new(-854, 406, -1505)
}

local IsAutoFarmRunning = false
local AutoFarmThread = nil

local function GetBasePart(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then return instance end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then return descendant end
	end
	return nil
end

local function IsValidTarget(instance)
	local typeAttr = instance:GetAttribute("gizmoType")
	return typeAttr == "ATM" or typeAttr == "Register"
end

local function FindClosestTarget()
	if not GizmoFolder or not RootPart then return nil end
	local minDistance = math.huge
	local closestPart = nil
	for _, item in ipairs(GizmoFolder:GetChildren()) do
		if IsValidTarget(item) then
			local part = GetBasePart(item)
			if part then
				local dist = (RootPart.Position - part.Position).Magnitude
				if dist < minDistance then
					closestPart = part
					minDistance = dist
				end
			end
		end
	end
	return closestPart
end

local function TeleportToTarget(target)
	if not RootPart then return end
	if typeof(target) ~= "Instance" then
		if typeof(target) == "Vector3" then RootPart.CFrame = CFrame.new(target) end
	else
		RootPart.CFrame = target.CFrame * CFrame.new(0, 1, 0)
	end
end

local function SpamInteract(duration)
	local start = tick()
	while tick() - start < duration do
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		task.wait(0.01)
	end
end

local function ProcessCollection(targetPart)
	SpamInteract(1.5)
end

local function StartAutoFarm()
	if AutoFarmThread or not GizmoFolder or not RootPart then return end
	IsAutoFarmRunning = true
	AutoFarmThread = task.spawn(function()
		while IsAutoFarmRunning do
			pcall(function()
				local target = FindClosestTarget()
				if target then
					TeleportToTarget(target)
					ProcessCollection(target)
				else
					TeleportToTarget(PatrolPoints[math.random(1, #PatrolPoints)])
				end
				task.wait(1.5)
			end)
		end
	end)
end

local function StopAutoFarm()
	IsAutoFarmRunning = false
	if AutoFarmThread then task.cancel(AutoFarmThread) AutoFarmThread = nil end
end

-- ============================================================
-- Hitbox 扩大
-- ============================================================
local HitboxHeadSize = 20
local HitboxDisabled = true
local HitboxTransparency = 0.7
local HitboxColor = Color3.fromRGB(255, 255, 255)
local HitboxRainbow = false
local HitboxTargetedUser = ""

local function GenerateRainbowColor()
	local HueValue = tick() % 5 / 5
	return Color3.fromHSV(HueValue, 1, 1)
end

local function IsTargetedUser(PlayerName)
	local TargetLower = HitboxTargetedUser:lower()
	return PlayerName:lower():find(TargetLower, 1, true) ~= nil
end

RunService.RenderStepped:Connect(function()
	pcall(function()
		if HitboxDisabled then
			for _, NextPlayer in pairs(Players:GetPlayers()) do
				if NextPlayer ~= LocalPlayer then
					pcall(function()
						local Character = NextPlayer.Character
						local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
						if HRP then
							HRP.Size = Vector3.new(2, 2, 1)
							HRP.Transparency = 1
							HRP.BrickColor = BrickColor.new("Medium stone grey")
							HRP.Material = Enum.Material.Plastic
							HRP.CanCollide = true
						end
					end)
				end
			end
		else
			for _, NextPlayer in pairs(Players:GetPlayers()) do
				if NextPlayer ~= LocalPlayer then
					pcall(function()
						local Character = NextPlayer.Character
						local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
						if HRP then
							if HitboxTargetedUser == "" or IsTargetedUser(NextPlayer.Name) then
								HRP.Size = Vector3.new(HitboxHeadSize, HitboxHeadSize, HitboxHeadSize)
								HRP.Transparency = HitboxTransparency
								HRP.BrickColor = HitboxRainbow and BrickColor.new(GenerateRainbowColor()) or BrickColor.new(HitboxColor)
								HRP.Material = Enum.Material.Neon
								HRP.CanCollide = false
							else
								HRP.Size = Vector3.new(2, 2, 1)
								HRP.Transparency = 1
								HRP.BrickColor = BrickColor.new("Medium stone grey")
								HRP.Material = Enum.Material.Plastic
								HRP.CanCollide = true
							end
						end
					end)
				end
			end
		end
	end)
end)

-- ============================================================
-- 无限跳 / 加速
-- ============================================================
local InfiniteJumpEnabled = false
local DefaultJumpPower = 50
local speedMultiplier = 2
local isSpeedEnabled = false

local function InfiniteJumpLogic()
	UserInputService.JumpRequest:Connect(function()
		if not InfiniteJumpEnabled then return end
		pcall(function()
			local char = LocalPlayer.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.JumpPower = DefaultJumpPower
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end)

	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		local char = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and InfiniteJumpEnabled then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.JumpPower = DefaultJumpPower
		end
	end)
end
task.spawn(InfiniteJumpLogic)

local function updateSpeed()
	local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if isSpeedEnabled then
		humanoid.WalkSpeed = 16 * speedMultiplier
	else
		humanoid.WalkSpeed = 16
	end
end

LocalPlayer.CharacterAdded:Connect(function(char)
	char:WaitForChildOfClass("Humanoid")
	updateSpeed()
end)

-- ============================================================
-- 传送函数
-- ============================================================
local function TeleportTo(x, y, z)
	pcall(function()
		local player = Players.LocalPlayer
		local character = player.Character or player.CharacterAdded:Wait(3)
		local hrp = character:WaitForChild("HumanoidRootPart", 3)
		hrp.CFrame = CFrame.new(x, y, z)
	end)
end

-- ============================================================
-- 初始化 RootPart
-- ============================================================
local function InitRootPart()
	pcall(function()
		local char = LocalPlayer.Character
		if not char then
			char = LocalPlayer.CharacterAdded:Wait()
		end
		if char then
			RootPart = char:WaitForChild("HumanoidRootPart", 5)
		end
	end)
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	InitRootPart()
end)

InitRootPart()

-- ============================================================
-- 窗口
-- ============================================================
local Window = Library:CreateWindow({
	Title = "Script",
	Footer = "v1.0",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Rage = Window:AddTab("愤怒机器人", "swords"),
	Weapon = Window:AddTab("武器修改", "target"),
	Player = Window:AddTab("本地玩家", "user"),
	Money = Window:AddTab("金钱", "dollar-sign"),
	Teleport = Window:AddTab("传送", "map-pin"),
	["UI Settings"] = Window:AddTab("UI 设置", "settings"),
}

-- ============================================================
-- 愤怒机器人
-- ============================================================
local RageBox = Tabs.Rage:AddLeftGroupbox("愤怒机器人")

RageBox:AddToggle("RageBotEnabled", {
	Text = "启用愤怒机器人",
	Default = false,
})

Toggles.RageBotEnabled:OnChanged(function()
	AutoShoot = Toggles.RageBotEnabled.Value
	if AutoShoot then
		enableRageBot()
		Library:Notify({Title = "成功", Description = "愤怒机器人已启用", Time = 3})
	else
		disableRageBot()
		Library:Notify({Title = "提示", Description = "愤怒机器人已关闭", Time = 3})
	end
end)

RageBox:AddSlider("ShootInterval", {
	Text = "射击间隔",
	Default = 0.2,
	Min = 0.1,
	Max = 1.0,
	Rounding = 2,
})

Options.ShootInterval:OnChanged(function()
	getgenv().ShootInterval = Options.ShootInterval.Value
end)

-- ============================================================
-- 弹道颜色
-- ============================================================
local TrailBox = Tabs.Rage:AddRightGroupbox("弹道颜色")

TrailBox:AddLabel("起始颜色"):AddColorPicker("TrailColorStart", {
	Default = Color3.fromRGB(0, 170, 255),
	Title = "弹道起始颜色",
})

Options.TrailColorStart:OnChanged(function()
	getgenv().TrailColors.StartColor = Options.TrailColorStart.Value
end)

TrailBox:AddLabel("中间颜色1"):AddColorPicker("TrailColorMiddle1", {
	Default = Color3.fromRGB(255, 0, 255),
	Title = "弹道中间颜色1",
})

Options.TrailColorMiddle1:OnChanged(function()
	getgenv().TrailColors.MiddleColor1 = Options.TrailColorMiddle1.Value
end)

TrailBox:AddLabel("中间颜色2"):AddColorPicker("TrailColorMiddle2", {
	Default = Color3.fromRGB(255, 255, 0),
	Title = "弹道中间颜色2",
})

Options.TrailColorMiddle2:OnChanged(function()
	getgenv().TrailColors.MiddleColor2 = Options.TrailColorMiddle2.Value
end)

TrailBox:AddLabel("结束颜色"):AddColorPicker("TrailColorEnd", {
	Default = Color3.fromRGB(255, 0, 0),
	Title = "弹道结束颜色",
})

Options.TrailColorEnd:OnChanged(function()
	getgenv().TrailColors.EndColor = Options.TrailColorEnd.Value
end)

TrailBox:AddSlider("TrailTransparency", {
	Text = "弹道透明度",
	Default = 0.3,
	Min = 0,
	Max = 1,
	Rounding = 2,
})

Options.TrailTransparency:OnChanged(function()
	getgenv().TrailTransparency = Options.TrailTransparency.Value
end)

TrailBox:AddButton({
	Text = "测试弹道效果",
	Func = function()
		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local startPos = LocalPlayer.Character.HumanoidRootPart.Position
			local endPos = startPos + Vector3.new(0, 0, -20)

			local trailContainer = Instance.new("Folder")
			trailContainer.Name = "TestTrail"
			trailContainer.Parent = Workspace

			local beam = Instance.new("Part")
			beam.Size = Vector3.new(0.2, 0.2, 20)
			beam.Anchored = true
			beam.CanCollide = false
			beam.Material = Enum.Material.Neon
			beam.Transparency = getgenv().TrailTransparency or 0.3
			beam.CFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -10)
			beam.Color = getgenv().TrailColors.StartColor or Color3.fromRGB(0, 170, 255)
			beam.Parent = trailContainer

			local pointLight = Instance.new("PointLight")
			pointLight.Brightness = 5
			pointLight.Range = 5
			pointLight.Color = beam.Color
			pointLight.Parent = beam

			local particles = Instance.new("ParticleEmitter")
			particles.Size = NumberSequence.new(0.1, 0.3)
			particles.Transparency = NumberSequence.new(0.3, 0.8)
			particles.Lifetime = NumberRange.new(0.5, 1)
			particles.Rate = 50
			particles.Speed = NumberRange.new(1, 2)
			particles.VelocitySpread = 180
			particles.Color = ColorSequence.new(
				getgenv().TrailColors.StartColor or Color3.fromRGB(0, 170, 255),
				getgenv().TrailColors.MiddleColor1 or Color3.fromRGB(255, 0, 255),
				getgenv().TrailColors.MiddleColor2 or Color3.fromRGB(255, 255, 0),
				getgenv().TrailColors.EndColor or Color3.fromRGB(255, 0, 0)
			)
			particles.Parent = beam

			task.delay(3, function()
				if trailContainer and trailContainer.Parent then
					trailContainer:Destroy()
				end
			end)

			Library:Notify({Title = "测试成功", Description = "弹道颜色预览已生成", Time = 3})
		else
			Library:Notify({Title = "错误", Description = "无法找到角色位置", Time = 3})
		end
	end,
})

TrailBox:AddButton({
	Text = "重置颜色设置",
	Func = function()
		getgenv().TrailColors = {
			StartColor = Color3.fromRGB(0, 170, 255),
			EndColor = Color3.fromRGB(255, 0, 0),
			MiddleColor1 = Color3.fromRGB(255, 0, 255),
			MiddleColor2 = Color3.fromRGB(255, 255, 0)
		}
		Options.TrailColorStart:SetValue(Color3.fromRGB(0, 170, 255))
		Options.TrailColorMiddle1:SetValue(Color3.fromRGB(255, 0, 255))
		Options.TrailColorMiddle2:SetValue(Color3.fromRGB(255, 255, 0))
		Options.TrailColorEnd:SetValue(Color3.fromRGB(255, 0, 0))
		Library:Notify({Title = "重置完成", Description = "所有颜色已恢复为默认值", Time = 3})
	end,
})

-- ============================================================
-- 武器修改
-- ============================================================
local WeaponBox = Tabs.Weapon:AddLeftGroupbox("武器修改")

WeaponBox:AddButton({
	Text = "无限子弹",
	Func = function()
		local Shooter = require(ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns.Shooter)
		local originalShoot = Shooter._shoot
		Shooter._shoot = function(self)
			self.ammo = 9999
			self.totalAmmo = 9999
			return originalShoot(self)
		end
	end,
})

WeaponBox:AddButton({
	Text = "无后坐力",
	Func = function()
		local Shooter = require(ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns.Shooter)
		local originalShoot = Shooter._shoot
		Shooter._shoot = function(self)
			self.recoil = {firstShotKick = 0, climb = 0, spread = 0}
			return originalShoot(self)
		end
	end,
})

WeaponBox:AddButton({
	Text = "无扩散",
	Func = function()
		local Shooter = require(ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns.Shooter)
		local originalShoot = Shooter._shoot
		Shooter._shoot = function(self)
			self.aim = {spreadAngle = 0, zeroing = 1000}
			return originalShoot(self)
		end
	end,
})

WeaponBox:AddButton({
	Text = "快速射击",
	Func = function()
		local Shooter = require(ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns.Shooter)
		local originalShoot = Shooter._shoot
		Shooter._shoot = function(self)
			self.tool.fireDebounce = 0
			self.tool.fireMode = "auto"
			return originalShoot(self)
		end
	end,
})

WeaponBox:AddButton({
	Text = "无装弹",
	Func = function()
		local Shooter = require(ReplicatedStorage.Client.Wanted.Objects.ClientTool.Components.Guns.Shooter)
		local originalShoot = Shooter._shoot
		Shooter._shoot = function(self)
			self.ammoData = {reloadTime = 0, magSize = 9999}
			return originalShoot(self)
		end
	end,
})

-- ============================================================
-- 本地玩家
-- ============================================================
local PlayerBox = Tabs.Player:AddLeftGroupbox("本地玩家")

PlayerBox:AddToggle("InfiniteJump", {
	Text = "启用无限跳",
	Default = false,
})

Toggles.InfiniteJump:OnChanged(function()
	InfiniteJumpEnabled = Toggles.InfiniteJump.Value
	if InfiniteJumpEnabled then
		pcall(function()
			local char = LocalPlayer.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				humanoid.JumpPower = DefaultJumpPower
			end
		end)
	end
end)

PlayerBox:AddToggle("SpeedEnabled", {
	Text = "加速移动",
	Default = false,
})

Toggles.SpeedEnabled:OnChanged(function()
	isSpeedEnabled = Toggles.SpeedEnabled.Value
	updateSpeed()
end)

PlayerBox:AddSlider("SpeedMultiplier", {
	Text = "速度倍数",
	Default = 2,
	Min = 1,
	Max = 5,
	Rounding = 1,
})

Options.SpeedMultiplier:OnChanged(function()
	speedMultiplier = Options.SpeedMultiplier.Value
	if isSpeedEnabled then updateSpeed() end
end)

-- Hitbox
local HitboxBox = Tabs.Player:AddRightGroupbox("Hitbox 扩大")

HitboxBox:AddToggle("HitboxEnabled", {
	Text = "启用 Hitbox Extender",
	Default = false,
})

Toggles.HitboxEnabled:OnChanged(function()
	HitboxDisabled = not Toggles.HitboxEnabled.Value
end)

HitboxBox:AddSlider("HitboxHeadSize", {
	Text = "Hitbox 大小",
	Default = 20,
	Min = 5,
	Max = 50,
	Rounding = 0,
})

Options.HitboxHeadSize:OnChanged(function()
	HitboxHeadSize = Options.HitboxHeadSize.Value
end)

HitboxBox:AddSlider("HitboxTransparency", {
	Text = "Hitbox 透明度",
	Default = 0.7,
	Min = 0,
	Max = 1,
	Rounding = 2,
})

Options.HitboxTransparency:OnChanged(function()
	HitboxTransparency = Options.HitboxTransparency.Value
end)

HitboxBox:AddToggle("HitboxRainbow", {
	Text = "彩虹 Hitbox",
	Default = false,
})

Toggles.HitboxRainbow:OnChanged(function()
	HitboxRainbow = Toggles.HitboxRainbow.Value
end)

HitboxBox:AddInput("HitboxTargetUser", {
	Default = "",
	Text = "只对指定玩家",
	Placeholder = "留空 = 全部",
})

Options.HitboxTargetUser:OnChanged(function()
	HitboxTargetedUser = Options.HitboxTargetUser.Value
end)

-- ============================================================
-- 金钱
-- ============================================================
local MoneyBox = Tabs.Money:AddLeftGroupbox("金钱")

MoneyBox:AddToggle("AutoFarmEnabled", {
	Text = "自动全图刷钱",
	Default = false,
})

Toggles.AutoFarmEnabled:OnChanged(function()
	if Toggles.AutoFarmEnabled.Value then
		StartAutoFarm()
	else
		StopAutoFarm()
	end
end)

-- ============================================================
-- 传送
-- ============================================================
local PlacesBox = Tabs.Teleport:AddLeftGroupbox("地点传送")

PlacesBox:AddButton({Text = "枪店", Func = function() TeleportTo(-180.77, 43.13, -2805.05) end})
PlacesBox:AddButton({Text = "手机店", Func = function() TeleportTo(-905.70, 42.98, -1563.35) end})
PlacesBox:AddButton({Text = "黑市", Func = function() TeleportTo(-2907.39, 37.58, 1652.25) end})

local CrimeBox = Tabs.Teleport:AddRightGroupbox("犯罪地点")

CrimeBox:AddButton({Text = "犯罪窝点", Func = function() TeleportTo(-7939.26, 21.74, 1073.52) end})
CrimeBox:AddButton({Text = "银行外", Func = function() TeleportTo(-431.54, 40.09, -1400.08) end})
CrimeBox:AddButton({Text = "小银行", Func = function() TeleportTo(-6852.36, 42.61, 965.86) end})
CrimeBox:AddButton({Text = "银行内部", Func = function() TeleportTo(-399.28, 617.63, -1245.29) end})
CrimeBox:AddButton({Text = "警察局", Func = function() TeleportTo(1583.31, 119.86, -716.63) end})
CrimeBox:AddButton({Text = "烈焰要塞", Func = function() TeleportTo(-1412.96, 181.18, 3054.46) end})

-- 武器点
local WeaponPointsBox = Tabs.Teleport:AddLeftGroupbox("武器地点")

WeaponPointsBox:AddButton({Text = "AWP 狙击枪", Func = function() TeleportTo(-822.97, 326.09, -506.58) end})
WeaponPointsBox:AddButton({Text = "UMP 45", Func = function() TeleportTo(1665.20, 143.84, -644.01) end})
WeaponPointsBox:AddButton({Text = "贝内利 M1014", Func = function() TeleportTo(1345.20, 141.52, -4809.11) end})
WeaponPointsBox:AddButton({Text = "M4", Func = function() TeleportTo(-6342.43, 134.86, -4326.83) end})
WeaponPointsBox:AddButton({Text = "AK47", Func = function() TeleportTo(-7835.20, 21.84, 1192.14) end})
WeaponPointsBox:AddButton({Text = "火箭筒", Func = function() TeleportTo(-1392.87, 209.34, 3217.20) end})
WeaponPointsBox:AddButton({Text = "UZI", Func = function() TeleportTo(-1348.55, 40.68, 2033.74) end})

-- ============================================================
-- UI 设置
-- ============================================================
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("菜单", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame.Visible,
	Text = "打开快捷键菜单",
	Callback = function(value)
		Library.KeybindFrame.Visible = value
	end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
	Text = "自定义光标",
	Default = true,
	Callback = function(Value)
		Library.ShowCustomCursor = Value
	end,
})

MenuGroup:AddDropdown("NotificationSide", {
	Values = {"Left", "Right"},
	Default = "Right",
	Text = "通知位置",
	Callback = function(Value)
		Library:SetNotifySide(Value)
	end,
})

MenuGroup:AddDivider()

MenuGroup:AddLabel("菜单快捷键"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "菜单快捷键",
})

MenuGroup:AddButton("卸载", function()
	Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("ScriptHub")
SaveManager:SetFolder("ScriptHub/wanted")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()