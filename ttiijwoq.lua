-- ============================================================
-- Ink Game 脚本 → Obsidian 版（第 1 批：核心逻辑）
-- ============================================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Services = setmetatable({}, {
	__index = function(self, key)
		local suc, service = pcall(game.GetService, game, key)
		if suc and service then
			self[key] = service
			return service
		end
		return nil
	end
})

local Players = Services.Players
local RunService = Services.RunService
local HttpService = Services.HttpService
local TweenService = Services.TweenService
local UserInputService = Services.UserInputService
local ReplicatedStorage = Services.ReplicatedStorage

local lplr = Players.LocalPlayer
local localPlayer = lplr
local camera = workspace.CurrentCamera
local alive = false
local rootPart = nil

-- ============================================================
-- Maid
-- ============================================================
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({Tasks = {}}, Maid)
end

function Maid:Add(task)
	if typeof(task) == "RBXScriptConnection" or (typeof(task) == "Instance" and task.Destroy) or typeof(task) == "function" then
		table.insert(self.Tasks, task)
	end
	return task
end

function Maid:Clean()
	for _, task in ipairs(self.Tasks) do
		pcall(function()
			if typeof(task) == "RBXScriptConnection" then
				task:Disconnect()
			elseif typeof(task) == "Instance" then
				task:Destroy()
			elseif typeof(task) == "function" then
				task()
			end
		end)
	end
	table.clear(self.Tasks)
	self.Tasks = {}
end

-- ============================================================
-- 全局状态
-- ============================================================
local Script = {
	GameStateChanged = Instance.new("BindableEvent"),
	GameState = "unknown",
	Services = Services,
	Maid = Maid.new(),
	Connections = {},
	Functions = {},
	ESPTable = {
		Player = {},
		Seeker = {},
		Hider = {},
		Guard = {},
		Door = {},
		None = {},
		Key = {},
	},
	Temp = {}
}

local States = {}

-- ============================================================
-- 工具函数
-- ============================================================
function Script.Functions.Alert(message, time_obj)
	Library:Notify({
		Title = "提示",
		Description = message,
		Time = time_obj or 5,
	})
	local sound = Instance.new("Sound", workspace)
	sound.SoundId = "rbxassetid://4590662766"
	sound.Volume = 2
	sound.PlayOnRemove = true
	sound:Destroy()
end

function Script.Functions.Warn(message)
	warn("警告:", message)
end

function Script.Functions.GetRootPart()
	if not lplr.Character then return end
	return lplr.Character:WaitForChild("HumanoidRootPart", 10)
end

function Script.Functions.GetHumanoid()
	if not lplr.Character then return end
	return lplr.Character:WaitForChild("Humanoid", 10)
end

function Script.Functions.SafeRequire(module)
	if Script.Temp[tostring(module)] then return Script.Temp[tostring(module)] end
	local suc, err = pcall(function()
		return require(module)
	end)
	if not suc then
		warn("[安全加载] 失败: "..tostring(module).." ("..tostring(err)..")")
	else
		Script.Temp[tostring(module)] = err
	end
	return suc and err
end

function Script.Functions.DistanceFromCharacter(position)
	if typeof(position) == "Instance" then
		position = position:GetPivot().Position
	end
	if not alive then
		return (camera.CFrame.Position - position).Magnitude
	end
	return (rootPart.Position - position).Magnitude
end

function Script.Functions.ExecuteClick()
	local args = {"Clicked"}
	ReplicatedStorage:WaitForChild("Replication"):WaitForChild("Event"):FireServer(unpack(args))
end

function Script.Functions.CompleteDalgonaGame()
	Script.Functions.ExecuteClick()
	local args = {{Completed = true}}
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DALGONATEMPREMPTE"):FireServer(unpack(args))
end

function Script.Functions.PullRope(perfect)
	local args = {{PerfectQTE = true}}
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TemporaryReachedBindable"):FireServer(unpack(args))
end

function Script.Functions.GetDalgonaRemote()
	return ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DALGONATEMPREMPTE")
end

function Script.Functions.FixCamera()
	if workspace.CurrentCamera then
		pcall(function() workspace.CurrentCamera:Destroy() end)
	end
	local new = Instance.new("Camera")
	new.Parent = workspace
	workspace.CurrentCamera = new
	new.CameraType = Enum.CameraType.Custom
	if lplr.Character and lplr.Character:FindFirstChild("Humanoid") then
		new.CameraSubject = lplr.Character.Humanoid
	end
end

-- ============================================================
-- ESP 系统
-- ============================================================
function Script.Functions.ESP(args)
	if not args.Object then return Script.Functions.Warn("ESP 对象为空") end

	local ESPManager = {
		Object = args.Object,
		Text = args.Text or "无文本",
		TextParent = args.TextParent,
		Color = args.Color or Color3.new(),
		Offset = args.Offset or Vector3.zero,
		IsEntity = args.IsEntity or false,
		Type = args.Type or "None",
		Highlights = {},
		Humanoid = nil,
		RSConnection = nil,
		Connections = {}
	}

	local tableIndex = #Script.ESPTable[ESPManager.Type] + 1

	if ESPManager.IsEntity and ESPManager.Object.PrimaryPart and ESPManager.Object.PrimaryPart.Transparency == 1 then
		ESPManager.Object:SetAttribute("Transparency", ESPManager.Object.PrimaryPart.Transparency)
		ESPManager.Humanoid = Instance.new("Humanoid", ESPManager.Object)
		ESPManager.Object.PrimaryPart.Transparency = 0.99
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = ESPManager.Object
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = ESPManager.Color
	highlight.FillTransparency = Options.ESPFillTransparency.Value
	highlight.OutlineColor = ESPManager.Color
	highlight.OutlineTransparency = Options.ESPOutlineTransparency.Value
	highlight.Enabled = Toggles.ESPHighlight.Value
	highlight.Parent = ESPManager.Object
	table.insert(ESPManager.Highlights, highlight)

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Adornee = ESPManager.TextParent or ESPManager.Object
	billboardGui.AlwaysOnTop = true
	billboardGui.ClipsDescendants = false
	billboardGui.Size = UDim2.new(0, 1, 0, 1)
	billboardGui.StudsOffset = ESPManager.Offset
	billboardGui.Parent = ESPManager.TextParent or ESPManager.Object

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Oswald
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.Text = ESPManager.Text
	textLabel.TextColor3 = ESPManager.Color
	textLabel.TextSize = Options.ESPTextSize.Value
	textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	textLabel.TextStrokeTransparency = 0.75
	textLabel.Parent = billboardGui

	function ESPManager.SetColor(newColor)
		ESPManager.Color = newColor
		for _, hl in pairs(ESPManager.Highlights) do
			hl.FillColor = newColor
			hl.OutlineColor = newColor
		end
		textLabel.TextColor3 = newColor
	end

	function ESPManager.Destroy()
		if ESPManager.RSConnection then ESPManager.RSConnection:Disconnect() end
		if ESPManager.IsEntity and ESPManager.Object then
			if ESPManager.Object.PrimaryPart then
				ESPManager.Object.PrimaryPart.Transparency = ESPManager.Object.PrimaryPart:GetAttribute("Transparency")
			end
			if ESPManager.Humanoid then ESPManager.Humanoid:Destroy() end
		end
		for _, hl in pairs(ESPManager.Highlights) do hl:Destroy() end
		if billboardGui then billboardGui:Destroy() end
		if Script.ESPTable[ESPManager.Type][tableIndex] then
			Script.ESPTable[ESPManager.Type][tableIndex] = nil
		end
		for _, conn in pairs(ESPManager.Connections) do
			pcall(function() conn:Disconnect() end)
		end
		ESPManager.Connections = {}
	end

	ESPManager.RSConnection = RunService.RenderStepped:Connect(function()
		if not ESPManager.Object or not ESPManager.Object:IsDescendantOf(workspace) then
			ESPManager.Destroy()
			return
		end
		for _, hl in pairs(ESPManager.Highlights) do
			hl.Enabled = Toggles.ESPHighlight.Value
			hl.FillTransparency = Options.ESPFillTransparency.Value
			hl.OutlineTransparency = Options.ESPOutlineTransparency.Value
		end
		textLabel.TextSize = Options.ESPTextSize.Value
		if Toggles.ESPDistance.Value then
			textLabel.Text = string.format("%s\n[%s]", ESPManager.Text, math.floor(Script.Functions.DistanceFromCharacter(ESPManager.Object)))
		else
			textLabel.Text = ESPManager.Text
		end
	end)

	function ESPManager.GiveSignal(signal)
		table.insert(ESPManager.Connections, signal)
	end

	Script.ESPTable[ESPManager.Type][tableIndex] = ESPManager
	return ESPManager
end

function Script.Functions.SeekerESP(player)
	if player:GetAttribute("IsHunter") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		Script.Functions.ESP({
			Object = player.Character,
			Text = player.Name .. " (监管者)",
			Color = Options.SeekerEspColor.Value,
			Offset = Vector3.new(0, 3, 0),
			Type = "Seeker"
		})
	end
end

function Script.Functions.HiderESP(player)
	if player:GetAttribute("IsHider") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local esp = Script.Functions.ESP({
			Object = player.Character,
			Text = player.Name .. " (躲藏者)",
			Color = Options.HiderEspColor.Value,
			Offset = Vector3.new(0, 3, 0),
			Type = "Hider"
		})
		player:GetAttributeChangedSignal("IsHider"):Once(function()
			if not player:GetAttribute("IsHider") then esp.Destroy() end
		end)
	end
end

function Script.Functions.KeyESP(key)
	if key:IsA("Model") and key.PrimaryPart then
		Script.Functions.ESP({
			Object = key,
			Text = key.Name .. " (钥匙)",
			Color = Options.KeyEspColor.Value,
			Offset = Vector3.new(0, 1, 0),
			Type = "Key",
			IsEntity = true
		})
	end
end

function Script.Functions.DoorESP(door)
	if door:IsA("Model") and door.Name == "FullDoorAnimated" and door.PrimaryPart then
		local keyNeeded = door:GetAttribute("KeyNeeded") or "无"
		Script.Functions.ESP({
			Object = door,
			Text = "门 (钥匙: " .. keyNeeded .. ")",
			Color = Options.DoorEspColor.Value,
			Offset = Vector3.new(0, 2, 0),
			Type = "Door",
			IsEntity = true
		})
	end
end

function Script.Functions.GuardESP(character)
	if character and character:FindFirstChild("HumanoidRootPart") then
		Script.Functions.ESP({
			Object = character,
			Text = "守卫",
			Color = Options.GuardEspColor.Value,
			Offset = Vector3.new(0, 3, 0),
			Type = "Guard"
		})
	end
end

function Script.Functions.PlayerESP(player)
	if not (player.Character and player.Character.PrimaryPart and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0) then return end
	local playerEsp = Script.Functions.ESP({
		Type = "Player",
		Object = player.Character,
		Text = string.format("%s [%s]", player.DisplayName, player.Character.Humanoid.Health),
		TextParent = player.Character.PrimaryPart,
		Color = Options.PlayerEspColor.Value
	})
	playerEsp.GiveSignal(player.Character.Humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth > 0 then
			playerEsp.Text = string.format("%s [%s]", player.DisplayName, newHealth)
		else
			playerEsp.Destroy()
		end
	end))
end

-- ============================================================
-- 玻璃桥
-- ============================================================
function Script.Functions.RevealGlassBridge()
	local Effects = Script.Functions.SafeRequire(ReplicatedStorage.Modules.Effects) or {
		AnnouncementTween = function(args)
			Script.Functions.Alert(args.AnnouncementDisplayText, args.DisplayTime)
		end
	}
	local glassHolder = workspace:FindFirstChild("GlassBridge") and workspace.GlassBridge:FindFirstChild("GlassHolder")
	if not glassHolder then
		warn("未找到 GlassHolder")
		return
	end
	for _, tilePair in pairs(glassHolder:GetChildren()) do
		for _, tileModel in pairs(tilePair:GetChildren()) do
			if tileModel:IsA("Model") and tileModel.PrimaryPart then
				local primaryPart = tileModel.PrimaryPart
				local isBreakable = primaryPart:GetAttribute("exploitingisevil") == true
				local targetColor = isBreakable and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
				for _, part in pairs(tileModel:GetDescendants()) do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {
							Transparency = 0.5,
							Color = targetColor
						}):Play()
					end
				end
				local highlight = Instance.new("Highlight")
				highlight.FillColor = targetColor
				highlight.FillTransparency = 0.7
				highlight.OutlineTransparency = 0.5
				highlight.Parent = tileModel
			end
		end
	end
	Effects.AnnouncementTween({
		AnnouncementOneLine = true,
		FasterTween = true,
		DisplayTime = 10,
		AnnouncementDisplayText = "安全格是绿色，易碎格是红色！"
	})
end

-- ============================================================
-- 防摔 / 防僵直
-- ============================================================
function Script.Functions.BypassRagdoll()
	local SharedFunctions = Script.Functions.SafeRequire(ReplicatedStorage.Modules.SharedFunctions)
	local Character = lplr.Character
	if not Character then return end
	local Humanoid = Character:FindFirstChild("Humanoid")
	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	local Torso = Character:FindFirstChild("Torso")
	if not (Humanoid and HumanoidRootPart and Torso) then return end

	local function restoreHumanoidStates()
		Humanoid.PlatformStand = false
		Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		for _, state in pairs({
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Flying,
			Enum.HumanoidStateType.StrafingNoPhysics,
			Enum.HumanoidStateType.Ragdoll
		}) do
			Humanoid:SetStateEnabled(state, false)
		end
	end

	local function cleanupRagdoll()
		for _, obj in pairs(HumanoidRootPart:GetChildren()) do
			if obj:IsA("BallSocketConstraint") or obj.Name:match("^CacheAttachment") then
				obj:Destroy()
			end
		end
		local joints = {"Left Hip", "Left Shoulder", "Neck", "Right Hip", "Right Shoulder"}
		for _, jointName in pairs(joints) do
			local motor = Torso:FindFirstChild(jointName)
			if motor and motor:IsA("Motor6D") and not motor.Part0 then
				motor.Part0 = Torso
			end
		end
		for _, part in pairs(Character:GetChildren()) do
			if part:IsA("BasePart") and part:FindFirstChild("BoneCustom") then
				part.BoneCustom:Destroy()
			end
		end
		for _, folderName in pairs({"Ragdoll", "Stun", "RotateDisabled", "RagdollWakeupImmunity", "InjuredWalking"}) do
			local folder = Character:FindFirstChild(folderName)
			if folder then folder:Destroy() end
		end
		local LocalRagdolls = workspace.Effects:FindFirstChild("LocalRagdolls")
		if LocalRagdolls then
			local ragdollModel = LocalRagdolls:FindFirstChild(lplr.Name)
			if ragdollModel then ragdollModel:Destroy() end
		end
	end

	restoreHumanoidStates()
	cleanupRagdoll()
end

-- ============================================================
-- 恢复玩家可见性
-- ============================================================
Script.Functions.RestoreVisibility = function(character)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if part.Transparency >= 0.99 or part.LocalTransparencyModifier >= 0.99 then
				part.Transparency = 0
				part.LocalTransparencyModifier = 0
			end
		end
	end
	pcall(function() character.HumanoidRootPart.Transparency = 1 end)
	for _, item in pairs(character:GetChildren()) do
		if item:IsA("Accessory") or item:IsA("Clothing") then
			if item:IsA("Accessory") then
				local handle = item:FindFirstChild("Handle")
				if handle and handle.Transparency >= 0.99 then handle.Transparency = 0 end
			end
		end
	end
end

Script.Functions.CheckPlayersVisibility = function()
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character then
			Script.Functions.RestoreVisibility(player.Character)
		end
	end
end

-- ============================================================
-- 望远镜 / 传送点
-- ============================================================
function Script.Functions.WinRLGL()
	if not lplr.Character then return end
	local call = Toggles.AntiFlingToggle.Value
	if call then Toggles.AntiFlingToggle:SetValue(false) end
	lplr.Character:PivotTo(CFrame.new(Vector3.new(-100.8, 1030, 115)))
	if call then task.delay(0.5, function() Toggles.AntiFlingToggle:SetValue(true) end) end
end

function Script.Functions.TeleportSafe()
	if not lplr.Character then return end
	local call = Toggles.AntiFlingToggle.Value
	if call then Toggles.AntiFlingToggle:SetValue(false) end
	lplr.Character:PivotTo(CFrame.new(Vector3.new(-108, 329.1, 462.1)))
	if call then task.delay(0.5, function() Toggles.AntiFlingToggle:SetValue(true) end) end
end

function Script.Functions.WinGlassBridge()
	if not lplr.Character then return end
	local call = Toggles.AntiFlingToggle.Value
	if call then Toggles.AntiFlingToggle:SetValue(false) end
	lplr.Character:PivotTo(CFrame.new(Vector3.new(-203.9, 520.7, -1534.3485)))
	if call then task.delay(0.5, function() Toggles.AntiFlingToggle:SetValue(true) end) end
end

-- ============================================================
-- Dalgona 小游戏
-- ============================================================
Script.Functions.BypassDalgonaGame = function()
	local SharedFunctions = Script.Functions.SafeRequire(ReplicatedStorage.Modules.SharedFunctions)
	local Character = lplr.Character
	local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character and Character:FindFirstChild("Humanoid")
	local PlayerGui = lplr.PlayerGui
	local DebrisBD = lplr:WaitForChild("DebrisBD")
	local CurrentCamera = workspace.CurrentCamera
	local EffectsFolder = workspace:FindFirstChild("Effects")
	local ImpactFrames = PlayerGui:FindFirstChild("ImpactFrames")

	local shapeModel, outlineModel, pickModel, redDotModel
	if EffectsFolder then
		for _, obj in pairs(EffectsFolder:GetChildren()) do
			if obj:IsA("Model") and obj.Name:match("Outline$") then
				outlineModel = obj
			elseif obj:IsA("Model") and not obj.Name:match("Outline$") and obj.Name ~= "Pick" and obj.Name ~= "RedDot" then
				shapeModel = obj
			elseif obj.Name == "Pick" then
				pickModel = obj
			elseif obj.Name == "RedDot" then
				redDotModel = obj
			end
		end
	end

	local progressBar = ImpactFrames and ImpactFrames:FindFirstChild("ProgressBar")
	local pickViewportModel
	if ImpactFrames then
		for _, obj in pairs(ImpactFrames:GetChildren()) do
			if obj:IsA("ViewportFrame") and obj:FindFirstChild("PickModel") then
				pickViewportModel = obj.PickModel
				break
			end
		end
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local DalgonaRemote = Remotes:WaitForChild("DALGONATEMPREMPTE")

	task.spawn(function()
		SharedFunctions.CreateFolder(lplr, "RecentGameStartedMessage", 0.01)
		if shapeModel and shapeModel:FindFirstChild("shape") then
			TweenService:Create(shapeModel.shape, TweenInfo.new(2, Enum.EasingStyle.Quad), {
				Position = shapeModel.shape.Position + Vector3.new(0, 0.5, 0)
			}):Play()
		end
		if shapeModel then
			for _, part in pairs(shapeModel:GetChildren()) do
				if part.Name == "DalgonaClickPart" and part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(2, Enum.EasingStyle.Quad), {Transparency = 1}):Play()
				end
			end
		end
		if pickModel and pickModel.Parent then
			TweenService:Create(pickModel, TweenInfo.new(2, Enum.EasingStyle.Quad), {Transparency = 1}):Play()
		end
		if redDotModel and redDotModel.Parent then
			TweenService:Create(redDotModel, TweenInfo.new(2, Enum.EasingStyle.Quad), {Transparency = 1}):Play()
		end
		if pickViewportModel then
			for _, part in pairs(pickViewportModel:GetDescendants()) do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(2, Enum.EasingStyle.Quad), {Transparency = 1}):Play()
				end
			end
		end
		if HumanoidRootPart then
			TweenService:Create(CurrentCamera, TweenInfo.new(2, Enum.EasingStyle.Quad), {
				CFrame = HumanoidRootPart.CFrame * CFrame.new(0.0841674805, 8.45438766, 6.69675446, 0.999918401, -0.00898250192, 0.00907994807, 3.31699681e-08, 0.710912943, 0.703280032, -0.0127722733, -0.703222632, 0.710854948)
			}):Play()
		end
		SharedFunctions.Invisible(Character, 0, true)
		DalgonaRemote:FireServer({Success = true})
		task.wait(2)
		for _, obj in pairs({shapeModel, outlineModel, pickModel, redDotModel, progressBar}) do
			if obj and obj.Parent then obj:Destroy() end
		end
		UserInputService.MouseIconEnabled = true
		if PlayerGui:FindFirstChild("Hotbar") and PlayerGui.Hotbar:FindFirstChild("Backpack") then
			TweenService:Create(PlayerGui.Hotbar.Backpack, TweenInfo.new(1.5, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut), {
				Position = UDim2.new(0, 0, 0, 0)
			}):Play()
		end
		if progressBar then
			DebrisBD:Fire(progressBar, 2)
			TweenService:Create(progressBar, TweenInfo.new(1.5, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut), {
				Position = UDim2.new(progressBar.Position.X.Scale, 0, progressBar.Position.Y.Scale + 1, 0)
			}):Play()
		end
		CurrentCamera.CameraType = Enum.CameraType.Custom
		if Humanoid then CurrentCamera.CameraSubject = Humanoid end
		local cameraConnection
		local startTime = tick()
		cameraConnection = RunService.RenderStepped:Connect(function()
			if tick() - startTime >= 5 then
				cameraConnection:Disconnect()
				return
			end
			if CurrentCamera.CameraType ~= Enum.CameraType.Custom or CurrentCamera.CameraSubject ~= Humanoid then
				CurrentCamera.CameraType = Enum.CameraType.Custom
				if Humanoid then CurrentCamera.CameraSubject = Humanoid end
			end
		end)
	end)

	return function()
		for _, obj in pairs({shapeModel, outlineModel, pickModel, redDotModel, progressBar}) do
			if obj and obj.Parent then obj:Destroy() end
		end
		UserInputService.MouseIconEnabled = true
		CurrentCamera.CameraType = Enum.CameraType.Custom
		if Humanoid then CurrentCamera.CameraSubject = Humanoid end
	end
end

-- ============================================================
-- 叉子攻击
-- ============================================================
local tools = {"Fork", "Bottle", "Knife"}
Script.Functions.GetFork = function()
	local res
	for _, index in pairs(tools) do
		local tool = lplr.Character:FindFirstChild(index) or (lplr:FindFirstChild("Backpack") and lplr.Backpack:FindFirstChild(index))
		if tool then res = tool break end
	end
	return res
end

Script.Functions.FireForkRemote = function()
	local fork = Script.Functions.GetFork()
	if not fork then return end
	if fork.Parent.Name == "Backpack" then
		lplr.Character.Humanoid:EquipTool(fork)
	end
	fork = Script.Functions.GetFork()
	if not fork then return end
	local args = {"UsingMoveCustom", fork, [4] = {Clicked = true}}
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UsedTool"):FireServer(unpack(args))
	local args2 = {"UsingMoveCustom", fork, true, {Clicked = true}}
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UsedTool"):FireServer(unpack(args2))
end

-- ============================================================
-- Autowin
-- ============================================================
local lastCleanupFunction = function() end

function Script.Functions.HandleAutowin()
	if lastCleanupFunction then pcall(lastCleanupFunction) end
	pcall(function()
		Script.GameState = workspace.Values.CurrentGame.Value
	end)
	if States[Script.GameState] then
		Script.Functions.Alert("[自动胜利] 正在执行: "..tostring(Script.GameState))
		lastCleanupFunction = States[Script.GameState]()
	else
		Script.Functions.Alert("[自动胜利] 等待下一局游戏...")
	end
end

States = {
	RedLightGreenLight = function()
		local call = true
		task.spawn(function()
			repeat
				Script.Functions.WinRLGL()
				task.wait(5)
			until not call or not Toggles.InkGameAutowin.Value or Script.GameState ~= "RedLightGreenLight"
		end)
		if not Toggles.AntiFlingToggle.Value then Toggles.AntiFlingToggle:SetValue(true) end
		return function()
			call = false
			if Toggles.AntiFlingToggle.Value then Toggles.AntiFlingToggle:SetValue(false) end
		end
	end,
	Mingle = function()
		if not Toggles.AutoMingleQTE.Value then Toggles.AutoMingleQTE:SetValue(true) end
		return function()
			if Toggles.AutoMingleQTE.Value then Toggles.AutoMingleQTE:SetValue(false) end
		end
	end,
	TugOfWar = function()
		if not Toggles.AutoPull.Value then Toggles.AutoPull:SetValue(true) end
		if not Toggles.PerfectPull.Value then Toggles.PerfectPull:SetValue(true) end
		return function()
			if Toggles.AutoPull.Value then Toggles.AutoPull:SetValue(false) end
		end
	end,
	GlassBridge = function()
		Script.Functions.RevealGlassBridge()
		Script.Functions.WinGlassBridge()
	end,
	HideAndSeek = function()
		if lplr:GetAttribute("IsHider") then
			Script.Functions.TeleportSafe()
		else
			Script.Functions.Alert("[自动胜利] 捉迷藏监管者支持即将推出...")
		end
	end,
	LightsOut = Script.Functions.TeleportSafe,
	Dalgona = function()
		task.spawn(function()
			repeat task.wait() until Script.Functions.GetDalgonaRemote() or not Toggles.InkGameAutowin.Value or Library.Unloaded
			if not Toggles.InkGameAutowin.Value then return end
			task.wait(3)
			Script.Functions.CompleteDalgonaGame()
			Script.Functions.BypassDalgonaGame()
			Script.Functions.FixCamera()
		end)
		return function()
			Script.Functions.FixCamera()
			Script.Functions.CheckPlayersVisibility()
		end
	end
}

-- ============================================================
-- 其他玩家连接
-- ============================================================
function Script.Functions.SetupOtherPlayerConnection(player)
	if player.Character then
		if Toggles.PlayerESP.Value then
			Script.Functions.PlayerESP(player)
		end
	end
	player.CharacterAdded:Connect(function()
		task.delay(0.1, function()
			if Toggles.PlayerESP.Value then Script.Functions.PlayerESP(player) end
		end)
	end)
end

-- 游戏状态监听
workspace:WaitForChild("Values"):WaitForChild("CurrentGame"):GetPropertyChangedSignal("Value"):Connect(function()
	Script.GameState = workspace.Values.CurrentGame.Value
	Script.GameStateChanged:Fire(Script.GameState)
	if not Script.GameState then return end
	Script.GameState = tostring(Script.GameState)
	if Toggles.InkGameAutowin.Value then
		Script.Functions.HandleAutowin()
	end
end)

-- 相机更新
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then camera = workspace.CurrentCamera end
end)-- ============================================================
-- Ink Game 脚本 → Obsidian 版（第 2 批：UI）
-- ============================================================

-- ============================================================
-- 窗口
-- ============================================================
local Window = Library:CreateWindow({
	Title = "Ink Game",
	Footer = "v1.0",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main = Window:AddTab("主要", "home"),
	Visuals = Window:AddTab("视觉", "eye"),
	["UI Settings"] = Window:AddTab("UI 设置", "settings"),
}

-- ============================================================
-- 主要 Tab
-- ============================================================
local FunBox = Tabs.Main:AddLeftGroupbox("功能")

FunBox:AddToggle("InkGameAutowin", {
	Text = "自动胜利（全部）",
	Default = false,
})

Toggles.InkGameAutowin:OnChanged(function()
	if Toggles.InkGameAutowin.Value then
		Script.Functions.Alert("自动胜利已开启！", 3)
		Script.Functions.HandleAutowin()
	else
		Script.Functions.Alert("自动胜利已关闭！", 3)
	end
end)

FunBox:AddToggle("FlingAuraToggle", {
	Text = "甩飞光环",
	Default = false,
})

FunBox:AddToggle("AntiFlingToggle", {
	Text = "防甩飞",
	Default = false,
})

Toggles.AntiFlingToggle:OnChanged(function(call)
	if call then
		Script.Temp.PauseAntiFling = nil
		Script.Functions.Alert("防甩飞已开启", 3)
		Script.Temp.AntiFlingActive = true
		Script.Temp.AntiFlingLoop = task.spawn(function()
			local lastSafeCFrame = nil
			while Script.Temp.AntiFlingActive and not Library.Unloaded do
				if Script.Temp.PauseAntiFling then return end
				local character = lplr.Character
				local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso"))
				if root then
					local gs = Script.GameState
					local isActiveGame = gs and gs ~= "" and States[gs] ~= nil
					for _, part in pairs(character:GetDescendants()) do
						if part:IsA("BodyMover") or part:IsA("BodyVelocity") or part:IsA("BodyGyro") or part:IsA("BodyThrust") or part:IsA("BodyAngularVelocity") then
							part:Destroy()
						end
					end
					local maxVel = 100
					local vel = root.Velocity
					if vel.Magnitude > maxVel then
						root.Velocity = Vector3.new(
							math.clamp(vel.X, -maxVel, maxVel),
							math.clamp(vel.Y, -maxVel, maxVel),
							math.clamp(vel.Z, -maxVel, maxVel)
						)
					end
					if not lastSafeCFrame or (root.Position - lastSafeCFrame.Position).Magnitude < 20 then
						lastSafeCFrame = root.CFrame
					elseif isActiveGame and (root.Position - lastSafeCFrame.Position).Magnitude > 50 then
						root.CFrame = lastSafeCFrame
						root.Velocity = Vector3.zero
					end
				end
				task.wait(0.05)
			end
		end)
	else
		Script.Functions.Alert("防甩飞已关闭", 3)
		Script.Temp.AntiFlingActive = false
		if Script.Temp.AntiFlingLoop then
			task.cancel(Script.Temp.AntiFlingLoop)
		end
	end
end)

FunBox:AddToggle("KillauraInkGame", {
	Text = "杀戮光环",
	Default = false,
})

Toggles.KillauraInkGame:OnChanged(function(call)
	if call then
		local fork = Script.Functions.GetFork()
		if not fork then
			Script.Functions.Alert("未找到武器！", 3)
			Toggles.KillauraInkGame:SetValue(false)
			return
		end
		task.spawn(function()
			repeat
				task.wait(0.5)
				Script.Functions.FireForkRemote()
			until not Toggles.KillauraInkGame.Value or Library.Unloaded
		end)
	end
end)

-- 甩飞光环实际逻辑
Toggles.FlingAuraToggle:OnChanged(function(enabled)
	local function setNoclip(state)
		if Toggles.Noclip.Value ~= state then
			Toggles.Noclip:SetValue(state)
		end
	end
	local function stopFlingAura()
		Script.Temp.FlingAuraActive = false
		setNoclip(false)
		if Script.Temp.FlingAuraDeathConn then
			Script.Temp.FlingAuraDeathConn:Disconnect()
			Script.Temp.FlingAuraDeathConn = nil
		end
	end
	if enabled then
		Script.Functions.Alert("甩飞光环已开启", 3)
		Script.Temp.FlingAuraActive = true
		Script.Functions.HookShittyAntiFlingDetection()
		setNoclip(true)
		local humanoid = lplr.Character and lplr.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			Script.Temp.FlingAuraDeathConn = humanoid.Died:Connect(stopFlingAura)
		end
		task.spawn(function()
			local movel = 0.1
			while Script.Temp.FlingAuraActive and not Library.Unloaded do
				local character = lplr.Character
				local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso"))
				if character and character.Parent and root and root.Parent then
					local originalVel = root.Velocity
					root.Velocity = originalVel * 10000 + Vector3.new(0, 10000, 0)
					RunService.RenderStepped:Wait()
					if character and character.Parent and root and root.Parent then
						root.Velocity = originalVel
					end
					RunService.Stepped:Wait()
					if character and character.Parent and root and root.Parent then
						root.Velocity = originalVel + Vector3.new(0, movel, 0)
						movel = -movel
					end
				end
				RunService.Heartbeat:Wait()
			end
		end)
	else
		Script.Functions.Alert("甩飞光环已关闭", 3)
		Script.Functions.RevertAntiFlingDetection()
		stopFlingAura()
	end
end)

-- ============================================================
-- 红绿灯
-- ============================================================
local RLGLBox = Tabs.Main:AddLeftGroupbox("红绿灯")

RLGLBox:AddToggle("RedLightGodmode", {
	Text = "红绿灯无敌",
	Default = false,
})

local RLGL_OriginalNamecall
Toggles.RedLightGodmode:OnChanged(function(enabled)
	if enabled then
		if not hookmetamethod then
			Script.Functions.Alert("你的执行器不支持此功能 :(")
			Toggles.RedLightGodmode:SetValue(false)
			return
		end
		local TrafficLightImage = lplr.PlayerGui:FindFirstChild("ImpactFrames") and lplr.PlayerGui.ImpactFrames:FindFirstChild("TrafficLightEmpty")
		local RS = game:GetService("ReplicatedStorage")
		local lastRootPartCFrame = nil
		local isGreenLight = true
		if TrafficLightImage and RS:FindFirstChild("Effects") and RS.Effects:FindFirstChild("Images") and RS.Effects.Images:FindFirstChild("TrafficLights") and RS.Effects.Images.TrafficLights:FindFirstChild("GreenLight") then
			isGreenLight = TrafficLightImage.Image == RS.Effects.Images.TrafficLights.GreenLight.Image
		end
		local function updateState()
			local character = lplr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then lastRootPartCFrame = root.CFrame end
		end
		updateState()
		local conn = RS.Remotes.Effects.OnClientEvent:Connect(function(EffectsData)
			if EffectsData.EffectName ~= "TrafficLight" then return end
			isGreenLight = EffectsData.GreenLight == true
			updateState()
		end)
		Script.Temp.RLGL_Connection = conn
		RLGL_OriginalNamecall = RLGL_OriginalNamecall or hookmetamethod(game, "__namecall", function(self, ...)
			local args = {...}
			local method = getnamecallmethod()
			if tostring(self) == "rootCFrame" and method == "FireServer" then
				if Toggles.RedLightGodmode.Value and not isGreenLight and lastRootPartCFrame then
					args[1] = lastRootPartCFrame
					return RLGL_OriginalNamecall(self, unpack(args))
				end
			end
			return RLGL_OriginalNamecall(self, ...)
		end)
		Script.Temp.RLGL_OriginalNamecall = RLGL_OriginalNamecall
		Script.Functions.Alert("红绿灯无敌已开启", 3)
	else
		if Script.Temp.RLGL_Connection then
			pcall(function() Script.Temp.RLGL_Connection:Disconnect() end)
			Script.Temp.RLGL_Connection = nil
		end
		if Script.Temp.RLGL_OriginalNamecall then
			hookmetamethod(game, "__namecall", Script.Temp.RLGL_OriginalNamecall)
			Script.Temp.RLGL_OriginalNamecall = nil
		end
		Script.Functions.Alert("红绿灯无敌已关闭", 3)
	end
end)

RLGLBox:AddButton({
	Text = "完成红绿灯",
	Func = function()
		if not workspace:FindFirstChild("RedLightGreenLight") then
			Script.Functions.Alert("游戏未运行")
			return
		end
		Script.Functions.WinRLGL()
	end,
})

RLGLBox:AddButton({
	Text = "移除受伤状态",
	Func = function()
		if lplr.Character and lplr.Character:FindFirstChild("InjuredWalking") then
			lplr.Character.InjuredWalking:Destroy()
		end
		Script.Functions.BypassRagdoll()
	end,
})

-- ============================================================
-- Dalgona
-- ============================================================
local DalgonaBox = Tabs.Main:AddLeftGroupbox("Dalgona 小游戏")

DalgonaBox:AddButton({
	Text = "完成 Dalgona 游戏",
	Func = function()
		if not Script.Functions.GetDalgonaRemote() then
			Script.Functions.Alert("游戏尚未开始")
			return
		end
		Script.Functions.CompleteDalgonaGame()
		Script.Functions.BypassDalgonaGame()
		Script.Functions.FixCamera()
		Script.Functions.Alert("已完成 Dalgona 游戏！", 2)
		task.spawn(function()
			repeat
				task.wait(1)
				Script.Functions.CheckPlayersVisibility()
			until not Script.Functions.GetDalgonaRemote()
		end)
	end,
})

DalgonaBox:AddToggle("ImmuneDalgonaGame", {
	Text = "Dalgona 免疫",
	Default = false,
})

Toggles.ImmuneDalgonaGame:OnChanged(function(call)
	if call then
		if not hookmetamethod then
			Script.Functions.Alert("你的执行器不支持此功能 :(", 5)
			Toggles.ImmuneDalgonaGame:SetValue(false)
			return
		end
		local DalgonaRemoteHook
		DalgonaRemoteHook = hookmetamethod(game, "__namecall", function(self, ...)
			local args = {...}
			local method = getnamecallmethod()
			if tostring(self) == "DALGONATEMPREMPTE" and method == "FireServer" then
				if args[1] ~= nil and type(args[1]) == "table" and args[1].CrackAmount ~= nil then
					Script.Functions.Alert("已阻止饼干碎裂", 3)
					return nil
				end
			end
			return DalgonaRemoteHook(self, unpack(args))
		end)
		Script.Temp.DalgonaRemoteHook = DalgonaRemoteHook
		Script.Functions.Alert("你的饼干不会再碎了！", 3)
	else
		if not hookmetamethod then return end
		if not Script.Temp.DalgonaRemoteHook then return end
		hookmetamethod(game, "__namecall", Script.Temp.DalgonaRemoteHook)
	end
end)

-- ============================================================
-- 拔河
-- ============================================================
local TugBox = Tabs.Main:AddLeftGroupbox("拔河")

TugBox:AddToggle("AutoPull", {
	Text = "自动拔河",
	Default = false,
})

TugBox:AddToggle("PerfectPull", {
	Text = "完美拔河",
	Default = true,
})

Toggles.AutoPull:OnChanged(function(call)
	if call then
		task.spawn(function()
			repeat
				Script.Functions.PullRope(Toggles.PerfectPull.Value)
				task.wait()
			until not Toggles.AutoPull.Value or Library.Unloaded
		end)
	end
end)

-- ============================================================
-- Mingle
-- ============================================================
local MingleBox = Tabs.Main:AddLeftGroupbox("Mingle")

MingleBox:AddToggle("AutoMingleQTE", {
	Text = "自动 Mingle",
	Default = false,
})

local RemoteForQTE
Toggles.AutoMingleQTE:OnChanged(function(call)
	Script.Temp.AutoMingleQTEActive = call
	if call then
		Script.Temp.AutoMingleQTEThread = task.spawn(function()
			while Script.Temp.AutoMingleQTEActive and not Library.Unloaded do
				local character = lplr.Character
				if character then
					if not RemoteForQTE then
						for _, obj in pairs(character:GetChildren()) do
							if obj:IsA("RemoteEvent") and obj.Name == "RemoteForQTE" then
								RemoteForQTE = obj
								break
							end
						end
					end
					pcall(function() RemoteForQTE:FireServer() end)
				end
				task.wait(0.5)
			end
		end)
	else
		if Script.Temp.AutoMingleQTEThread then
			task.cancel(Script.Temp.AutoMingleQTEThread)
		end
	end
end)

-- ============================================================
-- 玻璃桥
-- ============================================================
local GlassBox = Tabs.Main:AddLeftGroupbox("玻璃桥")

GlassBox:AddButton({
	Text = "完成玻璃桥游戏",
	Func = function()
		if not workspace:FindFirstChild("GlassBridge") then
			Script.Functions.Alert("游戏未运行")
			return
		end
		Script.Functions.WinGlassBridge()
	end,
})

GlassBox:AddButton({
	Text = "显示玻璃桥（安全格）",
	Func = function()
		if not workspace:FindFirstChild("GlassBridge") then
			Script.Functions.Alert("游戏未运行")
			return
		end
		Script.Functions.RevealGlassBridge()
	end,
})

-- ============================================================
-- 捉迷藏
-- ============================================================
function Script.Functions.GetHider()
	for _, plr in pairs(Players:GetPlayers()) do
		if plr == lplr then continue end
		if not plr.Character then continue end
		if not plr:GetAttribute("IsHider") then continue end
		if plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
			return plr.Character
		end
	end
end

local HideAndSeekBox = Tabs.Main:AddLeftGroupbox("捉迷藏")

HideAndSeekBox:AddButton({
	Text = "传送到躲藏者",
	Func = function()
		if not lplr.Character then return end
		if Script.GameState ~= "HideAndSeek" then
			Script.Functions.Alert("游戏未运行！")
			return
		end
		local hider = Script.Functions.GetHider()
		if not hider then
			Script.Functions.Alert("未找到躲藏者 :(")
			return
		end
		lplr.Character:PivotTo(hider:GetPrimaryPartCFrame())
	end,
})

-- ============================================================
-- 守卫碰撞箱
-- ============================================================
local RebelBox = Tabs.Main:AddLeftGroupbox("守卫")

RebelBox:AddToggle("ExpandGuardHitbox", {
	Text = "扩大守卫碰撞箱",
	Default = false,
})

local processedModels = {}
local TARGET_SIZE = Vector3.new(4, 4, 4)
local DEFAULT_SIZE = Vector3.new(1, 1, 1)

local function isPlayerCharacter(model)
	return Players:FindFirstChild(model.Name) ~= nil
end

local function processModel(model)
	if not model or not model:IsA("Model") then return end
	if isPlayerCharacter(model) then return end
	if processedModels[model] then return end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	if not model:FindFirstChild("_HeadHighlighter") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "_HeadHighlighter"
		highlight.Adornee = model
		highlight.FillColor = Color3.fromRGB(255, 80, 80)
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = model
	end
	processedModels[model] = head
end

local function cleanupGuard()
	for model, head in pairs(processedModels) do
		if head and head.Parent then
			pcall(function()
				head.Size = DEFAULT_SIZE
				head.CanCollide = true
			end)
		end
		local highlight = model:FindFirstChild("_HeadHighlighter")
		if highlight then highlight:Destroy() end
	end
	processedModels = {}
end

Toggles.ExpandGuardHitbox:OnChanged(function(call)
	if call then
		task.spawn(function()
			repeat
				local liveFolder = workspace:FindFirstChild("Live")
				if not Toggles.ExpandGuardHitbox.Value or not liveFolder then return end
				for _, model in ipairs(liveFolder:GetChildren()) do
					processModel(model)
				end
				for model, head in pairs(processedModels) do
					if model and model.Parent and head and head.Parent then
						if head.Size ~= TARGET_SIZE then
							head.Size = TARGET_SIZE
							head.CanCollide = false
						end
					else
						processedModels[model] = nil
					end
				end
				task.wait(3)
			until not Toggles.ExpandGuardHitbox.Value or Library.Unloaded
		end)
	else
		cleanupGuard()
	end
end)

-- ============================================================
-- 玩家 Tab
-- ============================================================
local PlayerBox = Tabs.Main:AddRightGroupbox("玩家")

PlayerBox:AddSlider("SpeedSlider", {
	Text = "移动速度",
	Default = 16,
	Min = 0,
	Max = 300,
	Rounding = 1,
})

PlayerBox:AddToggle("SpeedToggle", {
	Text = "加速",
	Default = false,
})

PlayerBox:AddToggle("Noclip", {
	Text = "穿墙",
	Default = false,
})

PlayerBox:AddToggle("InfiniteJump", {
	Text = "无限跳",
	Default = false,
})

Toggles.Noclip:OnChanged(function(call)
	if call then
		Script.Functions.Alert("穿墙已开启", 3)
		local function NoclipLoop()
			if lplr.Character ~= nil then
				for _, child in pairs(lplr.Character:GetDescendants()) do
					if child:IsA("BasePart") and child.CanCollide == true then
						child.CanCollide = false
					end
				end
			end
		end
		task.spawn(function()
			repeat
				RunService.Heartbeat:Wait()
				NoclipLoop()
			until not Toggles.Noclip.Value or Library.Unloaded
		end)
	else
		Script.Functions.Alert("穿墙已关闭", 3)
		if lplr.Character ~= nil then
			for _, child in pairs(lplr.Character:GetDescendants()) do
				if child:IsA("BasePart") and child.CanCollide == false then
					child.CanCollide = true
				end
			end
		end
	end
end)

Options.SpeedSlider:OnChanged(function()
	if not Toggles.SpeedToggle.Value then return end
	if not lplr.Character or not lplr.Character:FindFirstChild("Humanoid") then return end
	lplr.Character.Humanoid.WalkSpeed = Options.SpeedSlider.Value
end)

Toggles.SpeedToggle:OnChanged(function(call)
	if call then
		Script.Functions.Alert("加速已开启", 3)
		Script.Temp.OldSpeed = lplr.Character and lplr.Character:FindFirstChild("Humanoid") and lplr.Character.Humanoid.WalkSpeed or 16
		task.spawn(function()
			repeat
				task.wait(0.5)
				if not lplr.Character or not lplr.Character:FindFirstChild("Humanoid") then break end
				lplr.Character.Humanoid.WalkSpeed = Options.SpeedSlider.Value
			until not Toggles.SpeedToggle.Value or Library.Unloaded
		end)
	else
		Script.Functions.Alert("加速已关闭", 3)
		if lplr.Character and lplr.Character:FindFirstChild("Humanoid") then
			lplr.Character.Humanoid.WalkSpeed = Script.Temp.OldSpeed or 16
		end
	end
end)

UserInputService.JumpRequest:Connect(function()
	if Toggles.InfiniteJump.Value then
		if not lplr.Character or not lplr.Character:FindFirstChild("Humanoid") then return end
		lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

lplr.CharacterAdded:Connect(function(char)
	if not Toggles.SpeedToggle.Value then return end
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum.WalkSpeed = Options.SpeedSlider.Value
end)

-- ============================================================
-- 安全 Tab
-- ============================================================
local SecurityBox = Tabs.Main:AddRightGroupbox("安全")

SecurityBox:AddToggle("AntiAfk", {
	Text = "防挂机",
	Default = true,
})

Toggles.AntiAfk:OnChanged(function(call)
	if call then
		local VirtualUser = Services.VirtualUser
		Script.Temp.AntiAfkConnection = lplr.Idled:Connect(function()
			VirtualUser:Button2Down(Vector2.new(0, 0), camera.CFrame)
			wait(1)
			VirtualUser:Button2Up(Vector2.new(0, 0), camera.CFrame)
		end)
	else
		if not Script.Temp.AntiAfkConnection then return end
		pcall(function()
			Script.Temp.AntiAfkConnection:Disconnect()
		end)
	end
end)

SecurityBox:AddToggle("StaffDetector", {
	Text = "检测管理员",
	Default = true,
})

Toggles.StaffDetector:OnChanged(function(call)
	if call then
		local STAFF_GROUP_ID = 12398672
		local STAFF_MIN_RANK = 120
		local staffRoles = {[120] = "moderator", [254] = "dev", [255] = "owner"}
		Script.Temp.DetectedStaff = Script.Temp.DetectedStaff or {}
		local function checkPlayerStaff(player)
			local success, rank = pcall(function()
				return player:GetRankInGroup(STAFF_GROUP_ID)
			end)
			if success and rank and rank >= STAFF_MIN_RANK then
				local roleName = staffRoles[rank] or ("rank " .. tostring(rank))
				Script.Functions.Alert("[检测管理员] 发现管理员: " .. player.Name .. " (" .. roleName .. ")", 10)
				Script.Temp.DetectedStaff[player.UserId] = {Name = player.Name, Role = roleName}
				return true
			end
			return false
		end
		Script.Temp.StaffDetectorConnections = Script.Temp.StaffDetectorConnections or {}
		for _, player in pairs(Players:GetPlayers()) do
			if player ~= localPlayer then
				checkPlayerStaff(player)
			end
		end
		Script.Temp.StaffDetectorConnections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
			if player ~= localPlayer then
				task.wait(1)
				checkPlayerStaff(player)
			end
		end)
		Script.Temp.StaffDetectorConnections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
			local staffInfo = Script.Temp.DetectedStaff and Script.Temp.DetectedStaff[player.UserId]
			if staffInfo then
				Script.Functions.Alert("[检测管理员] 管理员离开: " .. staffInfo.Name .. " (" .. staffInfo.Role .. ")", 10)
				Script.Temp.DetectedStaff[player.UserId] = nil
			end
		end)
	else
		if Script.Temp.StaffDetectorConnections then
			for _, conn in pairs(Script.Temp.StaffDetectorConnections) do
				pcall(function() conn:Disconnect() end)
			end
			Script.Temp.StaffDetectorConnections = nil
		end
		Script.Temp.DetectedStaff = nil
		Script.Functions.Alert("[检测管理员] 已关闭。", 3)
	end
end)

-- ============================================================
-- 性能 Tab
-- ============================================================
local PerformanceBox = Tabs.Main:AddRightGroupbox("性能")

PerformanceBox:AddToggle("LowGFX", {
	Text = "低画质",
	Default = false,
})

PerformanceBox:AddToggle("DisableEffects", {
	Text = "禁用特效",
	Default = false,
})

Toggles.DisableEffects:OnChanged(function(call)
	if call then
		local Effects = workspace:WaitForChild("Effects", 15)
		if not Effects then return end
		Effects:ClearAllChildren()
		Script.Temp.DisableEffectsConnection = Effects.ChildAdded:Connect(function(child)
			child:Destroy()
		end)
	else
		if Script.Temp.DisableEffectsConnection then
			pcall(function() Script.Temp.DisableEffectsConnection:Disconnect() end)
			Script.Temp.DisableEffectsConnection = nil
		end
	end
end)

PerformanceBox:AddButton({
	Text = "清除特效缓存",
	Func = function()
		if workspace:FindFirstChild("Effects") then
			workspace.Effects:ClearAllChildren()
		end
	end,
})

-- ============================================================
-- 视觉 Tab
-- ============================================================
local ESPBox = Tabs.Visuals:AddLeftGroupbox("主要透视")

local function addESPEntry(meta)
	ESPBox:AddToggle(meta.metaName, {
		Text = meta.text,
		Default = meta.default,
	})
	ESPBox:AddLabel(meta.text .. " 颜色"):AddColorPicker(meta.color.metaName, {
		Default = meta.color.default,
		Title = meta.text .. " 颜色",
	})

	Toggles[meta.metaName]:OnChanged(function(call)
		if call then
			if meta.func then meta.func() end
		else
			for _, esp in pairs(Script.ESPTable[meta.text]) do
				esp.Destroy()
			end
		end
	end)

	if meta.descendantcheck then
		workspace.DescendantAdded:Connect(function(descendant)
			if not Toggles[meta.metaName].Value then return end
			meta.descendantcheck(descendant)
		end)
	end
end

-- 主要 ESP
addESPEntry({
	metaName = "PlayerESP",
	text = "Player",
	default = false,
	color = {metaName = "PlayerEspColor", default = Color3.fromRGB(255, 255, 255)},
	func = function()
		for _, player in pairs(Players:GetPlayers()) do
			if player == localPlayer then continue end
			Script.Functions.PlayerESP(player)
		end
	end,
})

addESPEntry({
	metaName = "GuardESP",
	text = "Guard",
	default = false,
	color = {metaName = "GuardEspColor", default = Color3.fromRGB(200, 100, 200)},
	func = function()
		local live = workspace:FindFirstChild("Live")
		if not live then return end
		for _, descendant in pairs(live:GetChildren()) do
			if descendant:IsA("Model") and descendant.Parent and descendant.Parent.Name == "Live" and descendant:FindFirstChild("TypeOfGuard") then
				if string.find(descendant.Name, "Guard") then
					Script.Functions.GuardESP(descendant)
				end
			end
		end
	end,
	descendantcheck = function(descendant)
		if descendant:IsA("Model") and descendant.Parent and descendant.Parent.Name == "Live" and descendant:FindFirstChild("TypeOfGuard") then
			if string.find(descendant.Name, "Guard") then
				Script.Functions.GuardESP(descendant)
			end
		end
	end,
})

-- 捉迷藏 ESP
local HideESPBox = Tabs.Visuals:AddLeftGroupbox("捉迷藏透视")

local function addHideESPEntry(meta)
	HideESPBox:AddToggle(meta.metaName, {
		Text = meta.text,
		Default = meta.default,
	})
	HideESPBox:AddLabel(meta.text .. " 颜色"):AddColorPicker(meta.color.metaName, {
		Default = meta.color.default,
		Title = meta.text .. " 颜色",
	})

	Toggles[meta.metaName]:OnChanged(function(call)
		if call then
			if not string.find(Script.GameState, "HideAndSeek") then return end
			if meta.checktype == "player" then
				for _, player in pairs(Players:GetPlayers()) do
					Script.Functions[meta.metaName](player)
				end
			elseif meta.checktype == "key" then
				local m = workspace:FindFirstChild("HideAndSeekMap")
				if m then
					local kf = m:FindFirstChild("KEYS")
					if kf then
						for _, key in pairs(kf:GetChildren()) do
							Script.Functions.KeyESP(key)
						end
					end
				end
			elseif meta.checktype == "door" then
				local m = workspace:FindFirstChild("HideAndSeekMap")
				if m then
					local nfd = m:FindFirstChild("NEWFIXEDDOORS")
					if nfd then
						for _, floor in pairs(nfd:GetChildren()) do
							if floor.Name:match("^Floor") then
								for _, door in pairs(floor:GetChildren()) do
									Script.Functions.DoorESP(door)
								end
							end
						end
					end
				end
			end
		else
			for _, esp in pairs(Script.ESPTable[meta.text]) do
				esp.Destroy()
			end
		end
	end)

	Options[meta.color.metaName]:OnChanged(function(value)
		for _, esp in pairs(Script.ESPTable[meta.text]) do
			esp.SetColor(value)
		end
	end)

	if meta.descendantcheck then
		workspace.DescendantAdded:Connect(function(descendant)
			if not string.find(Script.GameState, "HideAndSeek") then return end
			if not Toggles[meta.metaName].Value then return end
			meta.descendantcheck(descendant)
		end)
	end
end

addHideESPEntry({
	metaName = "HiderESP",
	text = "Hider",
	default = false,
	color = {metaName = "HiderEspColor", default = Color3.fromRGB(0, 255, 0)},
	checktype = "player",
})

addHideESPEntry({
	metaName = "SeekerESP",
	text = "Seeker",
	default = false,
	color = {metaName = "SeekerEspColor", default = Color3.fromRGB(255, 0, 0)},
	checktype = "player",
})

addHideESPEntry({
	metaName = "KeyESP",
	text = "Key",
	default = false,
	color = {metaName = "KeyEspColor", default = Color3.fromRGB(255, 255, 0)},
	checktype = "key",
	descendantcheck = function(descendant)
		local m = workspace:FindFirstChild("HideAndSeekMap")
		if not m then return end
		if descendant:IsA("Model") and descendant.Parent and descendant.Parent.Name == "KEYS" and descendant.Parent.Parent == m then
			Script.Functions.KeyESP(descendant)
		end
	end,
})

addHideESPEntry({
	metaName = "DoorESP",
	text = "Door",
	default = false,
	color = {metaName = "DoorEspColor", default = Color3.fromRGB(0, 128, 255)},
	checktype = "door",
	descendantcheck = function(descendant)
		local m = workspace:FindFirstChild("HideAndSeekMap")
		if not m then return end
		if descendant:IsA("Model") and descendant.Name == "FullDoorAnimated" and descendant.Parent and descendant.Parent.Parent and descendant.Parent.Parent.Name == "NEWFIXEDDOORS" then
			Script.Functions.DoorESP(descendant)
		end
	end,
})

-- ESP 设置
local ESPSettingsBox = Tabs.Visuals:AddRightGroupbox("透视设置")

ESPSettingsBox:AddToggle("ESPHighlight", {
	Text = "启用高亮",
	Default = true,
})

ESPSettingsBox:AddToggle("ESPDistance", {
	Text = "显示距离",
	Default = true,
})

ESPSettingsBox:AddSlider("ESPFillTransparency", {
	Text = "填充透明度",
	Default = 0.75,
	Min = 0,
	Max = 1,
	Rounding = 2,
})

ESPSettingsBox:AddSlider("ESPOutlineTransparency", {
	Text = "边框透明度",
	Default = 0,
	Min = 0,
	Max = 1,
	Rounding = 2,
})

ESPSettingsBox:AddSlider("ESPTextSize", {
	Text = "文字大小",
	Default = 22,
	Min = 16,
	Max = 26,
	Rounding = 0,
})

-- 自身设置
local SelfBox = Tabs.Visuals:AddRightGroupbox("自身")

SelfBox:AddToggle("FOVToggle", {
	Text = "视角 FOV",
	Default = false,
})

SelfBox:AddSlider("FOVSlider", {
	Text = "FOV 值",
	Default = 60,
	Min = 10,
	Max = 120,
	Rounding = 1,
})

Toggles.FOVToggle:OnChanged(function(call)
	if call then
		Script.Temp.OldFOV = camera and camera.FieldOfView or 60
		task.spawn(function()
			repeat
				if camera then camera.FieldOfView = Options.FOVSlider.Value end
				task.wait()
			until not Toggles.FOVToggle.Value or Library.Unloaded
		end)
	end
end)

-- ============================================================
-- 表情 / 杂项
-- ============================================================
local MiscBox = Tabs.Main:AddRightGroupbox("杂项")

function Script.Functions.CleanTable(tab)
	local res = {}
	for i, _ in pairs(tab) do
		table.insert(res, tostring(i))
	end
	return res
end

function Script.Functions.GetEmotesMeta()
	local Animations = ReplicatedStorage:WaitForChild("Animations", 10)
	if not Animations then return end
	local Emotes = Animations:WaitForChild("Emotes", 10)
	if not Emotes then return end
	local res = {}
	for _, v in pairs(Emotes:GetChildren()) do
		if v.ClassName ~= "Animation" then continue end
		if not v.AnimationId then continue end
		res[v.Name] = {anim = v.AnimationId, object = v}
	end
	Script.Temp.EmoteList = res
	return res
end

function Script.Functions.RefreshEmoteList()
	local res = Script.Functions.GetEmotesMeta()
	if not res or not Options.EmotesList then return end
	Options.EmotesList:SetValues(Script.Functions.CleanTable(res))
end

function Script.Functions.HookEmotesFolder()
	Script.Functions.RefreshEmoteList()
	local Animations = ReplicatedStorage:WaitForChild("Animations")
	local Emotes = Animations:WaitForChild("Emotes")
	Emotes.ChildAdded:Connect(Script.Functions.RefreshEmoteList)
	Emotes.ChildRemoved:Connect(Script.Functions.RefreshEmoteList)
end

function Script.Functions.ValidateEmote(emote)
	return Script.Temp.EmoteList ~= nil and Script.Temp.EmoteList[emote]
end

function Script.Functions.PlayEmote(emoteId, emoteObject)
	local character = lplr and lplr.Character
	if not character then
		Script.Functions.Alert("[表情] 未找到角色！", 3)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		Script.Functions.Alert("[表情] 未找到 Humanoid！", 3)
		return
	end
	if Script.Temp.EmoteTrack and typeof(Script.Temp.EmoteTrack) == "Instance" and Script.Temp.EmoteTrack:IsA("AnimationTrack") then
		pcall(function() Script.Temp.EmoteTrack:Stop() end)
		Script.Temp.EmoteTrack = nil
	end
	local animId = emoteObject and emoteObject.AnimationId or emoteId
	if not animId or animId == "" then
		Script.Functions.Alert("[表情] 无效 AnimationId！", 3)
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track
	local success = pcall(function()
		track = humanoid:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		Script.Temp.EmoteTrack = track
	end)
	if not success or not track then
		Script.Functions.Alert("[表情] 播放失败！", 3)
		return
	end
end

MiscBox:AddDropdown("EmotesList", {
	Values = {},
	Default = nil,
	Text = "表情列表",
	Searchable = true,
})

task.spawn(Script.Functions.HookEmotesFolder)

MiscBox:AddButton({
	Text = "播放表情",
	Func = function()
		if Options.EmotesList.Value then
			local emoteId = Script.Functions.ValidateEmote(Options.EmotesList.Value)
			if emoteId and emoteId.anim and emoteId.object then
				Script.Functions.PlayEmote(emoteId.anim, emoteId.object)
			else
				Script.Functions.Alert("错误！选中表情无效")
				Script.Functions.RefreshEmoteList()
			end
		else
			Script.Functions.Alert("未选择表情！", 3)
		end
	end,
})

MiscBox:AddButton({
	Text = "停止表情",
	Func = function()
		if Script.Temp.EmoteTrack and typeof(Script.Temp.EmoteTrack) == "Instance" and Script.Temp.EmoteTrack:IsA("AnimationTrack") then
			pcall(function() Script.Temp.EmoteTrack:Stop() end)
			Script.Temp.EmoteTrack = nil
		end
	end,
})

MiscBox:AddDivider()

MiscBox:AddToggle("AntiRagdoll", {
	Text = "防摔倒 + 免僵直",
	Default = false,
})

MiscBox:AddButton({
	Text = "移除摔倒效果",
	Func = Script.Functions.BypassRagdoll,
})

MiscBox:AddDivider()

MiscBox:AddToggle("SpectateModeToggler", {
	Text = "启用观战模式",
	Default = false,
})

Toggles.SpectateModeToggler:OnChanged(function(call)
	if workspace:FindFirstChild("Values") and workspace.Values:FindFirstChild("CanSpectateIfWonGame") then
		workspace.Values.CanSpectateIfWonGame.Value = call
	end
end)

MiscBox:AddDivider()

MiscBox:AddButton({Text = "修复相机", Func = Script.Functions.FixCamera})
MiscBox:AddButton({Text = "跳过过场动画", Func = Script.Functions.FixCamera})

MiscBox:AddButton({
	Text = "传送到安全位置",
	Func = function()
		if not lplr.Character then
			Script.Functions.Alert("未找到角色")
			return
		end
		Script.Functions.TeleportSafe()
	end,
})

MiscBox:AddButton({Text = "恢复玩家可见性", Func = Script.Functions.CheckPlayersVisibility})

-- 防摔倒循环
Toggles.AntiRagdoll:OnChanged(function(call)
	if call then
		Script.Functions.Alert("防摔倒 + 免僵直已开启", 3)
		Script.Functions.BypassRagdoll()
		task.spawn(function()
			repeat
				task.wait()
				Script.Functions.BypassRagdoll()
			until not Toggles.AntiRagdoll.Value or Library.Unloaded
		end)
	else
		Script.Functions.Alert("防摔倒 + 免僵直已关闭", 3)
	end
end)

-- ============================================================
-- 防甩飞检测 Hook（原脚本功能，保留）
-- ============================================================
function Script.Functions.HookShittyAntiFlingDetection()
	if not lplr.Character then return end
	if not Toggles.FlingAuraToggle.Value then return end
	if Script.Temp.MainScriptHook then
		pcall(function() Script.Temp.MainScriptHook:Disconnect() end)
	end
	local Main = lplr.Character:WaitForChild("Main")
	if Main.Enabled then
		Script.Functions.Alert("已绕过游戏的防甩飞检测 :omegalul:", 1)
	end
	pcall(function()
		Main.Enabled = false
		Main.Disabled = true
	end)
	Script.Temp.MainScriptHook = Main:GetPropertyChangedSignal("Enabled"):Connect(function()
		Main.Enabled = false
		Main.Disabled = true
	end)
end

function Script.Functions.RevertAntiFlingDetection()
	if Script.Temp.MainScriptHook then
		pcall(function() Script.Temp.MainScriptHook:Disconnect() end)
	end
	if not lplr.Character then return end
	local Main = lplr.Character:WaitForChild("Main")
	Main.Enabled = true
	Main.Disabled = false
end

lplr.CharacterAdded:Connect(Script.Functions.HookShittyAntiFlingDetection)
pcall(Script.Functions.HookShittyAntiFlingDetection)

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

-- ============================================================
-- 玩家连接初始化
-- ============================================================
for _, player in pairs(Players:GetPlayers()) do
	if player == localPlayer then continue end
	Script.Functions.SetupOtherPlayerConnection(player)
end

Players.PlayerAdded:Connect(function(player)
	if player == localPlayer then return end
	Script.Functions.SetupOtherPlayerConnection(player)
end)

-- 角色更新 alive / rootPart
lplr.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	alive = true
	rootPart = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			alive = false
		end)
	end
end)

if lplr.Character then
	alive = true
	rootPart = lplr.Character:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- 卸载
-- ============================================================
Library:OnUnload(function()
	pcall(function() Script.Maid:Clean() end)
	for _, conn in pairs(Script.Connections) do
		pcall(function() conn:Disconnect() end)
	end
	pcall(Script.Functions.RevertAntiFlingDetection)
	Library.Unloaded = true
end)

-- ============================================================
-- 主题 / 配置
-- ============================================================
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("InkGame")
SaveManager:SetFolder("InkGame/settings")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

task.spawn(function() pcall(Script.Functions.OnLoad) end)