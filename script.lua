local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager") or nil
local LocalPlayer = Players.LocalPlayer

-- الإعدادات والقيم
local Config = {
	Reach = false,
	AI = false,
	AILock = false,

	ReachSize = 10,
	AIDodgeDist = 28
}

-- متابعة لمس الشاشة الحقيقي من اللعبة نفسها
local activeScreenTouches = {}
local lastRealTouchPos = nil
local lastRealTouchTime = 0

UserInputService.TouchStarted:Connect(function(touch)
	activeScreenTouches[touch] = touch.Position
	lastRealTouchPos = touch.Position
	lastRealTouchTime = os.clock()
end)

UserInputService.TouchMoved:Connect(function(touch)
	if activeScreenTouches[touch] then
		activeScreenTouches[touch] = touch.Position
		lastRealTouchPos = touch.Position
		lastRealTouchTime = os.clock()
	end
end)

UserInputService.TouchEnded:Connect(function(touch)
	activeScreenTouches[touch] = nil
	lastRealTouchPos = touch.Position
	lastRealTouchTime = os.clock()
end)

-- إرسال نبضة قفز طبيعية مع فاصل زمني واقعي
local function sendNativeJumpInput()
	if VirtualInputManager then
		pcall(function()
			if typeof(VirtualInputManager.SendTouchInput) == "function" then
				local jumpBtnPos = Vector2.new(620, 470)
				VirtualInputManager:SendTouchInput(2, Enum.UserInputState.Begin, jumpBtnPos, 0)
				task.delay(0.08, function()
					pcall(function()
						VirtualInputManager:SendTouchInput(2, Enum.UserInputState.End, jumpBtnPos, 0)
					end)
				end)
			else
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
				task.delay(0.08, function()
					pcall(function()
						VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
					end)
				end)
			end
		end)
	end
end

-- تحكم بشاشة الجوال (عصا اللمس اليسرى + سحب النظر باللمس اليمنى)
local touchStickActive = false
local lastStickPos = Vector2.new(135, 515)
local lastLookTouchPos = Vector2.new(520, 260)
local lookTouchActive = false

local function releaseTouchControls()
	if touchStickActive and VirtualInputManager and typeof(VirtualInputManager.SendTouchInput) == "function" then
		pcall(function()
			VirtualInputManager:SendTouchInput(1, Enum.UserInputState.End, lastStickPos, 0)
		end)
	end
	if lookTouchActive and VirtualInputManager and typeof(VirtualInputManager.SendTouchInput) == "function" then
		pcall(function()
			VirtualInputManager:SendTouchInput(3, Enum.UserInputState.End, lastLookTouchPos, 0)
		end)
	end
	touchStickActive = false
	lookTouchActive = false
end

local function driveMobileScreenTouch(myHrp, moveDir, focusWorldPos)
	if not myHrp or not moveDir or moveDir.Magnitude < 0.05 then
		releaseTouchControls()
		return
	end

	local cam = workspace.CurrentCamera
	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local forward = Vector3.new(0, 0, -1)
	local right = Vector3.new(1, 0, 0)
	if cam then
		local cfLook = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		local cfRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
		if cfLook.Magnitude > 0.01 then forward = cfLook.Unit end
		if cfRight.Magnitude > 0.01 then right = cfRight.Unit end
	end

	local fDot = math.clamp(flatDir:Dot(forward), -1, 1)
	local rDot = math.clamp(flatDir:Dot(right), -1, 1)

	if VirtualInputManager and typeof(VirtualInputManager.SendTouchInput) == "function" then
		local centerStick = Vector2.new(135, 515)
		local nextStickPos = centerStick + Vector2.new(rDot * 42, -fDot * 42)
		local state = touchStickActive and Enum.UserInputState.Change or Enum.UserInputState.Begin
		pcall(function()
			VirtualInputManager:SendTouchInput(1, state, nextStickPos, 0)
		end)
		touchStickActive = true
		lastStickPos = nextStickPos

		if cam and focusWorldPos then
			local toFocus = Vector3.new(focusWorldPos.X - myHrp.Position.X, 0, focusWorldPos.Z - myHrp.Position.Z)
			if toFocus.Magnitude > 0.5 then
				local desiredYaw = math.atan2(-toFocus.Unit.X, -toFocus.Unit.Z)
				local _, currentYaw, _ = cam.CFrame:ToEulerAnglesYXZ()
				local diffYaw = math.atan2(math.sin(desiredYaw - currentYaw), math.cos(desiredYaw - currentYaw))
				if math.abs(diffYaw) > 0.08 then
					local baseLook = Vector2.new(540, 260)
					local dragDelta = Vector2.new(math.clamp(-diffYaw * 85, -48, 48), 0)
					local nextLookPos = baseLook + dragDelta
					local lState = lookTouchActive and Enum.UserInputState.Change or Enum.UserInputState.Begin
					pcall(function()
						VirtualInputManager:SendTouchInput(3, lState, nextLookPos, 0)
					end)
					lookTouchActive = true
					lastLookTouchPos = nextLookPos
				end
			end
		end
	end
end

-- التحكم بزر Shift Lock المرتبط بزر Smart AI واستخدامه عند الحاجة فقط
local shiftLockState = false

local function findShiftLockGuiButton()
	local containers = {LocalPlayer:FindFirstChild("PlayerGui")}
	pcall(function()
		if game:GetService("CoreGui") then
			table.insert(containers, game:GetService("CoreGui"))
		end
	end)

	for _, root in ipairs(containers) do
		if root then
			for _, obj in ipairs(root:GetDescendants()) do
				if obj:IsA("GuiButton") and obj.Visible then
					local n = string.lower(obj.Name)
					if string.find(n, "shift") or string.find(n, "mouselock") or string.find(n, "lock") then
						if not string.find(n, "lockai") then
							return obj
						end
					end
					if obj:IsA("ImageButton") then
						local img = string.lower(tostring(obj.Image))
						if string.find(img, "shift") or string.find(img, "lock") or string.find(img, "aim") or string.find(img, "reticle") then
							return obj
						end
					end
				end
			end
		end
	end
	return nil
end

local function setShiftLockEnabled(enableLock)
	local desired = (Config.AI == true) and (enableLock == true)
	if shiftLockState == desired then return end

	local btn = findShiftLockGuiButton()
	local pressedGui = false

	if btn then
		pcall(function()
			if typeof(getconnections) == "function" then
				for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
					conn:Fire()
					pressedGui = true
				end
				for _, conn in ipairs(getconnections(btn.Activated)) do
					conn:Fire()
					pressedGui = true
				end
			end
		end)
	end

	if not pressedGui and VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
			task.delay(0.06, function()
				pcall(function()
					VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
				end)
			end)
		end)
	end

	shiftLockState = desired
end

-- =========================================================
-- فحص الفريق (Team Check) لمنع استهداف أو مضايقة أعضاء الفريق
-- =========================================================
local function isTeammate(plr)
	if not plr or plr == LocalPlayer then
		return true
	end

	if LocalPlayer.Team ~= nil and plr.Team ~= nil then
		if LocalPlayer.Team == plr.Team then
			return true
		end
	end

	if LocalPlayer.TeamColor ~= nil and plr.TeamColor ~= nil then
		if LocalPlayer.TeamColor == plr.TeamColor and not LocalPlayer.Neutral and not plr.Neutral then
			return true
		end
	end

	local myChar = LocalPlayer.Character
	local tChar = plr.Character
	if myChar and tChar then
		for _, attr in ipairs({"Team", "Squad", "Faction", "Group"}) do
			local a1 = myChar:GetAttribute(attr) or LocalPlayer:GetAttribute(attr)
			local a2 = tChar:GetAttribute(attr) or plr:GetAttribute(attr)
			if a1 ~= nil and a2 ~= nil and a1 == a2 then
				return true
			end
		end
	end

	return false
end

-- فحص امتلاك القنبلة وإرجاع أداة القنبلة أو مجسمها إن وجد
local function findBombObject(char)
	if not char then return nil end

	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Tool") then
			local n = string.lower(obj.Name)
			if string.find(n, "bomb") or string.find(n, "tnt") or string.find(n, "time") or string.find(n, "boom") then
				return obj
			end
		end
	end

	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Model") or obj:IsA("BasePart") then
			local n = string.lower(obj.Name)
			if string.find(n, "bomb") or string.find(n, "tnt") or string.find(n, "time") then
				return obj
			end
		end
	end

	local plr = Players:GetPlayerFromCharacter(char)
	if plr and plr:FindFirstChild("Backpack") then
		for _, obj in ipairs(plr.Backpack:GetChildren()) do
			if obj:IsA("Tool") then
				local n = string.lower(obj.Name)
				if string.find(n, "bomb") or string.find(n, "tnt") or string.find(n, "time") then
					return obj
				end
			end
		end
	end

	return nil
end

local function hasBomb(char)
	return findBombObject(char) ~= nil
end

local function getRemainingBombTime(char)
	local bombObj = findBombObject(char)
	local searchRoots = {bombObj, char, workspace}

	for _, root in ipairs(searchRoots) do
		if root then
			for _, attrName in ipairs({"Time", "Timer", "Countdown", "BombTime", "TimeLeft"}) do
				local val = root:GetAttribute(attrName)
				if type(val) == "number" and val > 0 and val < 120 then
					return val
				end
			end

			for _, desc in ipairs(root:GetDescendants()) do
				if desc:IsA("NumberValue") or desc:IsA("IntValue") then
					local ln = string.lower(desc.Name)
					if string.find(ln, "time") or string.find(ln, "count") or string.find(ln, "bomb") then
						if type(desc.Value) == "number" and desc.Value > 0 and desc.Value < 120 then
							return desc.Value
						end
					end
				elseif desc:IsA("TextLabel") then
					local num = tonumber(string.match(desc.Text, "%d+%.?%d*"))
					if num and num > 0 and num <= 30 then
						return num
					end
				end
			end
		end
	end

	return nil
end

local function getCharacterParts(plr)
	local char = plr and plr.Character
	if not char then return nil, nil, nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil, nil, nil end
	return char, hrp, hum
end

local function getFloorPart(char, hrp)
	if not hrp then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {char}
	if LocalPlayer and LocalPlayer.Character then
		table.insert(filter, LocalPlayer.Character)
	end
	params.FilterDescendantsInstances = filter

	local result = workspace:Raycast(hrp.Position, Vector3.new(0, -35, 0), params)
	if result and result.Instance then
		return result.Instance
	end
	return nil
end

local function isInMatch(char, hrp)
	if not char or not hrp then return false end
	if hasBomb(char) then return true end

	local parentName = string.lower(tostring(char.Parent and char.Parent.Name or ""))
	if string.find(parentName, "lobby") or string.find(parentName, "waiting") or string.find(parentName, "spectat") then
		return false
	end

	local floorPart = getFloorPart(char, hrp)
	if not floorPart then return false end

	local hitName = string.lower(floorPart.Name)
	local hitAncestor = string.lower(tostring(floorPart.Parent and floorPart.Parent.Name or ""))
	if string.find(hitName, "lobby") or string.find(hitAncestor, "lobby") then
		return false
	end

	return true
end

local function isInSameArena(myChar, myHrp, targetChar, targetHrp)
	if not myHrp or not targetHrp then return false end

	local heightDiff = math.abs(targetHrp.Position.Y - myHrp.Position.Y)
	if heightDiff > 16 then
		return false
	end

	local myFloor = getFloorPart(myChar, myHrp)
	local targetFloor = getFloorPart(targetChar, targetHrp)
	if not myFloor or not targetFloor then
		return false
	end

	if myFloor ~= targetFloor then
		local sameParent = myFloor.Parent and (myFloor.Parent == targetFloor.Parent)
		local closeEnough = (myFloor.Position - targetFloor.Position).Magnitude < 18
		if not (sameParent and closeEnough) then
			return false
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar, targetChar}

	local delta = targetHrp.Position - myHrp.Position
	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	local dist = flatDelta.Magnitude
	if dist < 1 then return true end

	local steps = math.clamp(math.floor(dist / 6), 1, 8)
	for i = 1, steps do
		local alpha = i / (steps + 1)
		local samplePos = myHrp.Position + delta * alpha + Vector3.new(0, 2, 0)
		local gHit = workspace:Raycast(samplePos, Vector3.new(0, -18, 0), params)
		if not gHit then
			return false
		end
	end

	return true
end

-- بناء الواجهة بشكل واضح ومضمون الظهور
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("TimebombLegendUI")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TimebombLegendUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = playerGui

local FULL_HEIGHT = 196
local HEADER_HEIGHT = 42

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 276, 0, FULL_HEIGHT)
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.ZIndex = 10
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.6
MainStroke.Color = Color3.fromRGB(95, 110, 255)
MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainStroke.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
Header.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
Header.BorderSizePixel = 0
Header.ZIndex = 11
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 14)
HeaderCorner.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -86, 0, 18)
TitleLabel.Position = UDim2.new(0, 12, 0, 5)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "TIMEBOMB | HYPER JUKES AI"
TitleLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.TextSize = 13
TitleLabel.ZIndex = 12
TitleLabel.Parent = Header

local SubLabel = Instance.new("TextLabel")
SubLabel.Size = UDim2.new(1, -86, 0, 14)
SubLabel.Position = UDim2.new(0, 12, 0, 24)
SubLabel.BackgroundTransparency = 1
SubLabel.Text = "6 Jukes • Team Check • Touch"
SubLabel.TextColor3 = Color3.fromRGB(135, 145, 185)
SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.Font = Enum.Font.GothamMedium
SubLabel.TextSize = 9
SubLabel.ZIndex = 12
SubLabel.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -66, 0, 7)
MinBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 74)
MinBtn.Text = "-"
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.ZIndex = 12
MinBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 8)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(210, 52, 70)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.ZIndex = 12
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn

local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, -16, 0, FULL_HEIGHT - HEADER_HEIGHT - 10)
Body.Position = UDim2.new(0, 8, 0, HEADER_HEIGHT + 6)
Body.BackgroundTransparency = 1
Body.ZIndex = 11
Body.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = Body

local rowRefs = {}

local function createFeatureRow(keyName, order, title, initialState, valueConfig, onToggle)
	local row = Instance.new("Frame")
	row.Name = keyName .. "Row"
	row.Size = UDim2.new(1, 0, 0, 42)
	row.BackgroundColor3 = Color3.fromRGB(27, 29, 41)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 12
	row.Parent = Body

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Thickness = 1
	rowStroke.Color = Color3.fromRGB(45, 49, 70)
	rowStroke.Parent = row

	local hasStepper = valueConfig ~= nil
	local toggleWidth = hasStepper and 128 or 244

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = keyName .. "Toggle"
	toggleBtn.Size = UDim2.new(0, toggleWidth, 1, -8)
	toggleBtn.Position = UDim2.new(0, 4, 0, 4)
	toggleBtn.BackgroundColor3 = initialState and Color3.fromRGB(28, 155, 95) or Color3.fromRGB(40, 43, 60)
	toggleBtn.Text = title .. (initialState and " : ON" or " : OFF")
	toggleBtn.TextColor3 = Color3.fromRGB(250, 250, 255)
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 11
	toggleBtn.ZIndex = 13
	toggleBtn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = toggleBtn

	local state = initialState
	local function setButtonState(newState)
		state = newState
		toggleBtn.Text = title .. (state and " : ON" or " : OFF")
		toggleBtn.BackgroundColor3 = state and Color3.fromRGB(28, 155, 95) or Color3.fromRGB(40, 43, 60)
		rowStroke.Color = state and Color3.fromRGB(45, 200, 125) or Color3.fromRGB(45, 49, 70)
		onToggle(state)
	end

	toggleBtn.MouseButton1Click:Connect(function()
		setButtonState(not state)
	end)

	rowRefs[keyName] = {
		button = toggleBtn,
		setState = setButtonState
	}

	if hasStepper then
		local minusBtn = Instance.new("TextButton")
		minusBtn.Name = keyName .. "Minus"
		minusBtn.Size = UDim2.new(0, 28, 1, -8)
		minusBtn.Position = UDim2.new(0, 136, 0, 4)
		minusBtn.BackgroundColor3 = Color3.fromRGB(58, 62, 86)
		minusBtn.Text = "-"
		minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		minusBtn.Font = Enum.Font.GothamBlack
		minusBtn.TextSize = 15
		minusBtn.ZIndex = 13
		minusBtn.Parent = row

		local minusCorner = Instance.new("UICorner")
		minusCorner.CornerRadius = UDim.new(0, 8)
		minusCorner.Parent = minusBtn

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = keyName .. "Value"
		valueLabel.Size = UDim2.new(0, 52, 1, -8)
		valueLabel.Position = UDim2.new(0, 166, 0, 4)
		valueLabel.BackgroundColor3 = Color3.fromRGB(19, 21, 30)
		valueLabel.Text = tostring(Config[valueConfig.key])
		valueLabel.TextColor3 = Color3.fromRGB(130, 220, 255)
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextSize = 11
		valueLabel.ZIndex = 13
		valueLabel.Parent = row

		local valCorner = Instance.new("UICorner")
		valCorner.CornerRadius = UDim.new(0, 8)
		valCorner.Parent = valueLabel

		local plusBtn = Instance.new("TextButton")
		plusBtn.Name = keyName .. "Plus"
		plusBtn.Size = UDim2.new(0, 28, 1, -8)
		plusBtn.Position = UDim2.new(0, 220, 0, 4)
		plusBtn.BackgroundColor3 = Color3.fromRGB(78, 92, 235)
		plusBtn.Text = "+"
		plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		plusBtn.Font = Enum.Font.GothamBlack
		plusBtn.TextSize = 15
		plusBtn.ZIndex = 13
		plusBtn.Parent = row

		local plusCorner = Instance.new("UICorner")
		plusCorner.CornerRadius = UDim.new(0, 8)
		plusCorner.Parent = plusBtn

		local function updateValue(delta)
			local nextVal = math.clamp(Config[valueConfig.key] + delta, valueConfig.min, valueConfig.max)
			Config[valueConfig.key] = nextVal
			valueLabel.Text = tostring(nextVal)
		end

		minusBtn.MouseButton1Click:Connect(function()
			updateValue(-valueConfig.step)
		end)

		plusBtn.MouseButton1Click:Connect(function()
			updateValue(valueConfig.step)
		end)
	end
end

-- إعادة ضبط الهيتبوكس إلى الحجم الطبيعي الآمن
local function resetReach()
	for _, plr in ipairs(Players:GetPlayers()) do
		if not isTeammate(plr) and plr.Character then
			local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				pcall(function()
					hrp.Size = Vector3.new(2, 2, 1)
					hrp.Transparency = 1
					hrp.CanCollide = false
				end)
			end
		end
	end
end

-- =========================================================
-- ذكاء اصطناعي متكامل بمراوغات سريعة معقدة + فحص فريق + لمس شاشة
-- =========================================================
local jukePhase = "none"
local jukeTimer = 0
local jukeSign = 1
local arcPhaseClock = 0
local currentMoveDir = Vector3.new(1, 0, 0)
local lockedMoveDir = nil
local jumpCooldown = 0
local stuckTimer = 0
local lastPos = nil
local humanReactionDelay = 0
local humanHesitateTimer = 0
local currentTurnRate = 11.5

local currentTargetPlr = nil
local targetLockTimer = 0
local pathComputeTimer = 0
local cachedWaypoints = {}
local waypointIndex = 2

local function smoothHumanDir(fromDir, toDir, dt, turnSpeed)
	if not toDir or toDir.Magnitude < 0.05 then return fromDir end
	local targetUnit = Vector3.new(toDir.X, 0, toDir.Z).Unit
	if not fromDir or fromDir.Magnitude < 0.05 then return targetUnit end
	local fromUnit = Vector3.new(fromDir.X, 0, fromDir.Z).Unit
	local alpha = math.clamp(dt * (turnSpeed or currentTurnRate or 11.5), 0.10, 0.68)
	local blended = fromUnit:Lerp(targetUnit, alpha)
	if blended.Magnitude < 0.01 then return targetUnit end
	return blended.Unit
end

local function applyAIMove(myHrp, myHum, desiredDir, targetPos, camFocusPos, dt)
	if humanHesitateTimer > 0 then
		releaseTouchControls()
		return
	end

	local blendedDir = smoothHumanDir(currentMoveDir, desiredDir, dt or 0.016, currentTurnRate)
	currentMoveDir = blendedDir
	myHum:MoveTo(targetPos)
	driveMobileScreenTouch(myHrp, blendedDir, shiftLockState and camFocusPos or nil)
end

local function aiSetLockButton(desiredLockState, dirToLock)
	if desiredLockState and dirToLock then
		lockedMoveDir = dirToLock
	elseif not desiredLockState then
		lockedMoveDir = nil
	end

	if Config.AILock == desiredLockState then return end

	local lockRef = rowRefs.lock
	if lockRef and lockRef.button then
		if typeof(getconnections) == "function" then
			pcall(function()
				for _, conn in ipairs(getconnections(lockRef.button.MouseButton1Click)) do
					conn:Fire()
				end
			end)
		end
		if Config.AILock ~= desiredLockState then
			lockRef.setState(desiredLockState)
		end
	else
		Config.AILock = desiredLockState
	end
end

local function rotateFlatVector(vec, degrees)
	local rad = math.rad(degrees)
	local c, s = math.cos(rad), math.sin(rad)
	return Vector3.new(vec.X * c - vec.Z * s, 0, vec.X * s + vec.Z * c).Unit
end

local function probeObstacle(myChar, myHrp, dir, dist)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar}

	local lowOrigin = myHrp.Position - Vector3.new(0, 1.3, 0)
	local highOrigin = myHrp.Position + Vector3.new(0, 2.2, 0)

	local lowHit = workspace:Raycast(lowOrigin, dir * dist, params)
	local highHit = workspace:Raycast(highOrigin, dir * dist, params)

	if lowHit and (not lowHit.Instance.CanCollide or lowHit.Instance.Parent:FindFirstChildWhichIsA("Humanoid")) then
		lowHit = nil
	end
	if highHit and (not highHit.Instance.CanCollide or highHit.Instance.Parent:FindFirstChildWhichIsA("Humanoid")) then
		highHit = nil
	end

	if not lowHit and not highHit then
		return "clear", math.huge
	elseif lowHit and not highHit then
		return "jumpable", lowHit.Distance
	else
		local d = math.min(lowHit and lowHit.Distance or dist, highHit and highHit.Distance or dist)
		return "wall", d
	end
end

local function triggerJumpSkill(myHum, cooldownSec, dirToSnap)
	if not myHum or jumpCooldown > 0 or myHum.FloorMaterial == Enum.Material.Air then
		return false
	end
	if dirToSnap and dirToSnap.Magnitude > 0.05 then
		currentMoveDir = Vector3.new(dirToSnap.X, 0, dirToSnap.Z).Unit
	end
	myHum.Jump = true
	sendNativeJumpInput()
	jumpCooldown = cooldownSec or (0.48 + math.random(8, 20) / 100)
	return true
end

local function isSafeDirection(myChar, myHrp, myHum, dir)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar}

	local myFloor = getFloorPart(myChar, myHrp)

	local st, wallDist = probeObstacle(myChar, myHrp, dir, 8.5)
	if st == "wall" and wallDist < 6.5 then
		return false
	end

	for _, stepDist in ipairs({5, 9.5}) do
		local checkPoint = myHrp.Position + dir * stepDist + Vector3.new(0, 2, 0)
		local floorHit = workspace:Raycast(checkPoint, Vector3.new(0, -18, 0), params)
		if not floorHit then
			local farCheck = myHrp.Position + dir * (stepDist + 4.5) + Vector3.new(0, 3, 0)
			local farFloor = workspace:Raycast(farCheck, Vector3.new(0, -20, 0), params)
			if farFloor and myHum then
				triggerJumpSkill(myHum, 0.52, dir)
				return true
			end
			return false
		end
		if myFloor and floorHit.Instance ~= myFloor and floorHit.Instance.Parent ~= myFloor.Parent then
			local yGap = math.abs(floorHit.Position.Y - myHrp.Position.Y)
			if yGap > 9 then
				return false
			end
		end
	end

	return true
end

local function sanitizeDirection(myChar, myHrp, myHum, desiredDir)
	if isSafeDirection(myChar, myHrp, myHum, desiredDir) then
		local st, d = probeObstacle(myChar, myHrp, desiredDir, 7.5)
		if st == "jumpable" and d < 5.5 then
			triggerJumpSkill(myHum, 0.50, desiredDir)
		end
		return desiredDir
	end

	local searchAngles = {25, -25, 50, -50, 75, -75, 105, -105, 135, -135, 180}
	for _, deg in ipairs(searchAngles) do
		local candidate = rotateFlatVector(desiredDir, deg)
		if isSafeDirection(myChar, myHrp, myHum, candidate) then
			local st, d = probeObstacle(myChar, myHrp, candidate, 7.5)
			if st == "jumpable" and d < 5.5 then
				triggerJumpSkill(myHum, 0.50, candidate)
			end
			return candidate
		end
	end

	return rotateFlatVector(desiredDir, 90 * jukeSign)
end

local function measureOpenSpace(myChar, originPos, dir)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar}

	local leftDir = rotateFlatVector(dir, 55)
	local rightDir = rotateFlatVector(dir, -55)

	local leftHit = workspace:Raycast(originPos, leftDir * 12, params)
	local rightHit = workspace:Raycast(originPos, rightDir * 12, params)

	local leftSpace = (leftHit and leftHit.Instance.CanCollide) and leftHit.Distance or 12
	local rightSpace = (rightHit and rightHit.Instance.CanCollide) and rightHit.Distance or 12

	return leftSpace + rightSpace
end

local function hasCoverBetween(myChar, fromPos, threatPos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar}

	local delta = threatPos - fromPos
	local dist = delta.Magnitude
	if dist < 1 then return false end

	local ray = workspace:Raycast(fromPos + Vector3.new(0, 0.5, 0), delta.Unit * dist, params)
	if ray and ray.Instance and ray.Instance.CanCollide and not ray.Instance.Parent:FindFirstChildWhichIsA("Humanoid") then
		return true
	end
	return false
end

local function computeSmartPath(startPos, goalPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4
	})

	local ok = pcall(function()
		path:ComputeAsync(startPos, goalPos)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end

local function findAscentSpot(myChar, myHrp, targetHrp)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar, targetHrp.Parent}

	local toTarget = targetHrp.Position - myHrp.Position
	local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local baseDir = (flatToTarget.Magnitude > 0.05) and flatToTarget.Unit or Vector3.new(1, 0, 0)

	local bestSpot = nil
	local bestScore = -math.huge

	for angOffset = -90, 90, 30 do
		local probeDir = rotateFlatVector(baseDir, angOffset)
		for _, dist in ipairs({5, 9, 13}) do
			local checkPos = myHrp.Position + probeDir * dist + Vector3.new(0, 9.5, 0)
			local downHit = workspace:Raycast(checkPos, Vector3.new(0, -11, 0), params)
			if downHit and downHit.Instance and downHit.Instance.CanCollide then
				local stepY = downHit.Position.Y - myHrp.Position.Y
				if stepY > 2.2 and stepY <= 11.5 then
					local score = (12 - math.abs(stepY - 5)) * 4 - dist * 1.5
					if score > bestScore then
						bestScore = score
						bestSpot = downHit.Position + Vector3.new(0, 2, 0)
					end
				end
			end
		end
	end

	return bestSpot
end

local function evaluateDirectionScore(myChar, myHrp, dir, threatHrp, crowdPositions)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {myChar}

	local myFloor = getFloorPart(myChar, myHrp)
	local score = 0
	local st, wallDist = probeObstacle(myChar, myHrp, dir, 15)

	if st == "wall" then
		score -= (15 - wallDist) * 7.5
	elseif st == "jumpable" then
		score += 9
	else
		score += 24
	end

	local nextPos = myHrp.Position + dir * 8
	score += measureOpenSpace(myChar, nextPos, dir) * 1.35

	local aheadPoint = myHrp.Position + dir * 8 + Vector3.new(0, 2, 0)
	local floorHit = workspace:Raycast(aheadPoint, Vector3.new(0, -18, 0), params)
	if not floorHit then
		score -= 140
	else
		if myFloor and floorHit.Instance ~= myFloor and floorHit.Instance.Parent ~= myFloor.Parent then
			local gapY = math.abs(floorHit.Position.Y - myHrp.Position.Y)
			if gapY > 9 then
				score -= 160
			else
				score += 8
			end
		else
			score += 12
		end
	end

	if threatHrp then
		local threatVel = threatHrp.AssemblyLinearVelocity
		local predictedThreat = threatHrp.Position + Vector3.new(threatVel.X, 0, threatVel.Z) * 0.35
		score += (nextPos - predictedThreat).Magnitude * 1.75

		if hasCoverBetween(myChar, nextPos, predictedThreat) then
			score += 25
		end
	end

	for _, pos in ipairs(crowdPositions) do
		local dPos = (nextPos - pos).Magnitude
		if dPos < 10 then
			score -= (10 - dPos) * 1.8
		end
	end

	return score
end

local function pickBestPassTarget(myChar, myHrp, directOnly)
	local bestPlr = nil
	local bestHrp = nil
	local bestScore = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if not isTeammate(plr) then
			local tChar, tHrp = getCharacterParts(plr)
			if tChar and tHrp and isInMatch(tChar, tHrp) and not hasBomb(tChar) and isInSameArena(myChar, myHrp, tChar, tHrp) then
				local delta = tHrp.Position - myHrp.Position
				local dist = delta.Magnitude
				local heightDiff = math.abs(delta.Y)
				local speed = Vector3.new(tHrp.AssemblyLinearVelocity.X, 0, tHrp.AssemblyLinearVelocity.Z).Magnitude

				local targetCost = directOnly
					and (dist + heightDiff * 1.2)
					or (dist + speed * 0.45 + heightDiff * 2.0)

				if targetCost < bestScore then
					bestScore = targetCost
					bestPlr = plr
					bestHrp = tHrp
				end
			end
		end
	end

	return bestPlr, bestHrp
end

local function handleVerticalEnemy(myChar, myHrp, myHum, targetHrp, iHaveBomb, urgentMode, dt)
	local heightAbove = targetHrp.Position.Y - myHrp.Position.Y
	if heightAbove <= 3.2 then
		return false
	end

	local toTarget = targetHrp.Position - myHrp.Position
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	local flatDist = flat.Magnitude
	local directDir = (flatDist > 0.05) and flat.Unit or Vector3.new(1, 0, 0)

	local preferDropBait = iHaveBomb and (urgentMode or heightAbove > 7.5 or flatDist < 7)

	if not preferDropBait then
		local ascentSpot = findAscentSpot(myChar, myHrp, targetHrp)
		if ascentSpot then
			local toSpot = ascentSpot - myHrp.Position
			local spotFlat = Vector3.new(toSpot.X, 0, toSpot.Z)
			local climbDir = (spotFlat.Magnitude > 0.05) and spotFlat.Unit or directDir
			local safeClimb = sanitizeDirection(myChar, myHrp, myHum, climbDir)

			currentTurnRate = 12.0
			setShiftLockEnabled(true)
			applyAIMove(myHrp, myHum, safeClimb, ascentSpot, targetHrp.Position, dt)
			triggerJumpSkill(myHum, 0.54, safeClimb)
			return true
		end

		if pathComputeTimer <= 0 or #cachedWaypoints == 0 then
			pathComputeTimer = 0.42
			local wps = computeSmartPath(myHrp.Position, targetHrp.Position)
			if wps and #wps >= 2 then
				cachedWaypoints = wps
				waypointIndex = 2
			end
		end

		if cachedWaypoints[waypointIndex] then
			local wp = cachedWaypoints[waypointIndex]
			local wpFlat = Vector3.new(wp.Position.X - myHrp.Position.X, 0, wp.Position.Z - myHrp.Position.Z)
			if wpFlat.Magnitude < 3.5 then
				waypointIndex += 1
			else
				local stepDir = sanitizeDirection(myChar, myHrp, myHum, wpFlat.Unit)
				currentTurnRate = 12.0
				setShiftLockEnabled(true)
				applyAIMove(myHrp, myHum, stepDir, wp.Position, targetHrp.Position, dt)
				if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > myHrp.Position.Y + 1.5 then
					triggerJumpSkill(myHum, 0.54, stepDir)
				end
				return true
			end
		end

		local safeDirect = sanitizeDirection(myChar, myHrp, myHum, directDir)
		currentTurnRate = 12.0
		setShiftLockEnabled(true)
		applyAIMove(myHrp, myHum, safeDirect, myHrp.Position + safeDirect * 11, targetHrp.Position, dt)
		if flatDist < 15 then
			triggerJumpSkill(myHum, 0.56, safeDirect)
		end
		return true
	else
		local waveAngle = math.sin(arcPhaseClock * 6.4) * 38
		local orbitDir = rotateFlatVector(directDir, (70 * jukeSign) + waveAngle)
		local baitTargetPos = Vector3.new(targetHrp.Position.X, myHrp.Position.Y, targetHrp.Position.Z) + orbitDir * 5
		local safeBaitDir = sanitizeDirection(myChar, myHrp, myHum, (baitTargetPos - myHrp.Position).Unit)

		currentTurnRate = 12.5
		setShiftLockEnabled(false)
		applyAIMove(myHrp, myHum, safeBaitDir, baitTargetPos, nil, dt)
		return true
	end
end

local function chaseAndPassToTarget(myChar, myHrp, myHum, targetHrp, urgentMode, dt)
	if handleVerticalEnemy(myChar, myHrp, myHum, targetHrp, true, urgentMode, dt) then
		return
	end

	local toTarget = targetHrp.Position - myHrp.Position
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	local distFlat = flat.Magnitude
	local directDir = (distFlat > 0.05) and flat.Unit or Vector3.new(1, 0, 0)

	local needPassShiftLock = urgentMode or (distFlat < 11)
	setShiftLockEnabled(needPassShiftLock)

	local obstacleType = probeObstacle(myChar, myHrp, directDir, math.min(distFlat, 18))
	local chosenDir = directDir
	local moveTargetPos = myHrp.Position + directDir * 12

	if not urgentMode and obstacleType == "wall" and distFlat > 8 then
		if pathComputeTimer <= 0 or #cachedWaypoints == 0 then
			pathComputeTimer = 0.42
			local wps = computeSmartPath(myHrp.Position, targetHrp.Position)
			if wps and #wps >= 2 then
				cachedWaypoints = wps
				waypointIndex = 2
			end
		end

		if cachedWaypoints[waypointIndex] then
			local wp = cachedWaypoints[waypointIndex]
			local wpFlat = Vector3.new(wp.Position.X - myHrp.Position.X, 0, wp.Position.Z - myHrp.Position.Z)
			if wpFlat.Magnitude < 3.5 then
				waypointIndex += 1
			else
				chosenDir = sanitizeDirection(myChar, myHrp, myHum, wpFlat.Unit)
				moveTargetPos = myHrp.Position + chosenDir * 10
				if wp.Action == Enum.PathWaypointAction.Jump then
					triggerJumpSkill(myHum, 0.54, chosenDir)
				end
			end
		else
			chosenDir = sanitizeDirection(myChar, myHrp, myHum, directDir)
			moveTargetPos = myHrp.Position + chosenDir * 10
		end
	else
		local tVel = targetHrp.AssemblyLinearVelocity
		local leadFactor = urgentMode and 0.14 or 0.25
		local interceptPoint = targetHrp.Position + Vector3.new(tVel.X, 0, tVel.Z) * leadFactor
		local chaseFlat = Vector3.new(interceptPoint.X - myHrp.Position.X, 0, interceptPoint.Z - myHrp.Position.Z)
		local rawDir = (chaseFlat.Magnitude > 0.05) and chaseFlat.Unit or directDir

		if distFlat > 5 and distFlat < 22 and not urgentMode then
			local weaveDeg = math.sin(arcPhaseClock * 8.2) * 32 * jukeSign
			rawDir = rotateFlatVector(rawDir, weaveDeg)
		end

		chosenDir = sanitizeDirection(myChar, myHrp, myHum, rawDir)
		moveTargetPos = myHrp.Position + chosenDir * 12
	end

	currentTurnRate = urgentMode and 14.5 or 11.5
	local focusPos = needPassShiftLock and targetHrp.Position or nil
	applyAIMove(myHrp, myHum, chosenDir, moveTargetPos, focusPos, dt)

	if toTarget.Y > 2.4 then
		triggerJumpSkill(myHum, 0.54, chosenDir)
	end
end

-- =========================================================
-- 6 أنماط مراوغات سريعة ومتنوعة يصعب توقعها
-- =========================================================
local function buildLegendaryJukeDir(awayDir, bestSafeDir)
	local sideDir = Vector3.new(-awayDir.Z * jukeSign, 0, awayDir.X * jukeSign)
	local smoothWave = math.sin(arcPhaseClock * 9.5) * 0.28

	if jukePhase == "bait" then
		-- تمويه جانبي قصير لخداع العدو قبل الكسر
		return (sideDir * (0.86 + smoothWave) + bestSafeDir * 0.44 + awayDir * 0.14).Unit

	elseif jukePhase == "snap" then
		-- كسر حاد وسريع للزاوية العكسية مع الهروب
		local oppositeSide = Vector3.new(-awayDir.Z * (-jukeSign), 0, awayDir.X * (-jukeSign))
		return (oppositeSide * (0.94 - smoothWave) + awayDir * 0.58 + bestSafeDir * 0.30).Unit

	elseif jukePhase == "orbit" then
		-- مدار هلالي متعرج لتغيير زاوية الهجوم باستمرار
		local crescentAngle = 34 * math.sin(arcPhaseClock * 7.8) * jukeSign
		local curvedSide = rotateFlatVector(sideDir, crescentAngle)
		return (curvedSide * 0.84 + awayDir * 0.56 + bestSafeDir * 0.28).Unit

	elseif jukePhase == "zig_snap" then
		-- متعرج سريع متذبذب يصعب على الخصم تتبع مساره
		local zigPulse = (math.floor(arcPhaseClock * 7.5) % 2 == 0) and 1 or -1
		local zigSide = rotateFlatVector(sideDir, 42 * zigPulse)
		return (zigSide * 0.88 + awayDir * 0.52 + bestSafeDir * 0.25).Unit

	elseif jukePhase == "feint_hook" then
		-- خطاف تمويهي يميل بزاوية ثم يعطف بقوة نحو اتجاه آمن
		local hookAngle = 52 * jukeSign
		local hookVec = rotateFlatVector(awayDir, hookAngle)
		return (hookVec * 0.78 + bestSafeDir * 0.62).Unit

	elseif jukePhase == "dash_flank" then
		-- التفاف جانبي سريع نحو المساحة المفتوحة
		local flankAngle = 64 * jukeSign + math.cos(arcPhaseClock * 8.4) * 16
		local flankVec = rotateFlatVector(awayDir, flankAngle)
		return (flankVec * 0.82 + bestSafeDir * 0.48).Unit

	else
		return (bestSafeDir * 0.65 + awayDir * 0.38 + sideDir * (0.55 + smoothWave)).Unit
	end
end

local function pickNextJukePattern(nearestDist)
	local roll = math.random(1, 100)

	if nearestDist < 12 then
		-- ضغط قريب جداً: كسر سريع أو متعرج حاد
		if roll <= 38 then
			jukePhase = "snap"
			jukeTimer = math.random(22, 34) / 100
			currentTurnRate = 15.5
		elseif roll <= 70 then
			jukePhase = "zig_snap"
			jukeTimer = math.random(26, 38) / 100
			currentTurnRate = 15.0
		else
			jukePhase = "feint_hook"
			jukeTimer = math.random(24, 36) / 100
			currentTurnRate = 14.5
		end
	elseif nearestDist < 20 then
		-- مسافة متوسطة: تمويه ثم كسر أو مدار سريع
		if jukePhase == "bait" then
			jukePhase = "snap"
			jukeTimer = math.random(24, 36) / 100
			currentTurnRate = 15.0
		elseif roll <= 32 then
			jukePhase = "bait"
			jukeTimer = math.random(14, 22) / 100
			currentTurnRate = 13.0
		elseif roll <= 62 then
			jukePhase = "dash_flank"
			jukeTimer = math.random(26, 40) / 100
			currentTurnRate = 13.5
		else
			jukePhase = "orbit"
			jukeTimer = math.random(28, 42) / 100
			currentTurnRate = 12.5
		end
	else
		-- مسافة أبعد: مدار متعرج أو التفاف جانبي
		if roll <= 50 then
			jukePhase = "orbit"
			jukeTimer = math.random(28, 44) / 100
			currentTurnRate = 12.0
		elseif roll <= 80 then
			jukePhase = "dash_flank"
			jukeTimer = math.random(26, 38) / 100
			currentTurnRate = 12.5
		else
			jukePhase = "zig_snap"
			jukeTimer = math.random(24, 36) / 100
			currentTurnRate = 13.5
		end
	end
end

local function runSmartAI(myChar, myHrp, myHum, dt)
	if not Config.AI then
		setShiftLockEnabled(false)
		releaseTouchControls()
		return
	end

	if not isInMatch(myChar, myHrp) then
		setShiftLockEnabled(false)
		releaseTouchControls()
		return
	end

	arcPhaseClock += dt
	jukeTimer = math.max(0, jukeTimer - dt)
	jumpCooldown = math.max(0, jumpCooldown - dt)
	targetLockTimer = math.max(0, targetLockTimer - dt)
	pathComputeTimer = math.max(0, pathComputeTimer - dt)
	humanReactionDelay = math.max(0, humanReactionDelay - dt)
	humanHesitateTimer = math.max(0, humanHesitateTimer - dt)

	if lastPos then
		if (myHrp.Position - lastPos).Magnitude < 0.08 and myHum.WalkSpeed > 2 then
			stuckTimer += dt
		else
			stuckTimer = 0
		end
	end
	lastPos = myHrp.Position

	if stuckTimer > 0.30 then
		stuckTimer = 0
		jukeSign = -jukeSign
		jukePhase = "snap"
		jukeTimer = 0.28
		currentTurnRate = 15.5
		cachedWaypoints = {}
		aiSetLockButton(false, nil)
		setShiftLockEnabled(false)
		triggerJumpSkill(myHum, 0.50, rotateFlatVector(currentMoveDir, 50 * jukeSign))
	end

	local iHaveBomb = hasBomb(myChar)

	if iHaveBomb then
		jukePhase = "none"
		currentTurnRate = 11.5
		aiSetLockButton(false, nil)

		local myBombTime = getRemainingBombTime(myChar)
		local urgentPass = (myBombTime ~= nil and myBombTime <= 3.5)

		local lockedChar, lockedHrp = getCharacterParts(currentTargetPlr)
		local needNewTarget = (not currentTargetPlr)
			or isTeammate(currentTargetPlr)
			or (not lockedChar)
			or (not lockedHrp)
			or (not isInMatch(lockedChar, lockedHrp))
			or hasBomb(lockedChar)
			or (not isInSameArena(myChar, myHrp, lockedChar, lockedHrp))
			or (targetLockTimer <= 0)
			or ((lockedHrp.Position - myHrp.Position).Magnitude > 55)

		if urgentPass or needNewTarget then
			currentTargetPlr, lockedHrp = pickBestPassTarget(myChar, myHrp, urgentPass)
			targetLockTimer = urgentPass and 0.4 or 1.4
			cachedWaypoints = {}
		end

		if lockedHrp then
			chaseAndPassToTarget(myChar, myHrp, myHum, lockedHrp, urgentPass, dt)
		else
			setShiftLockEnabled(false)
			local safeRoam = sanitizeDirection(myChar, myHrp, myHum, currentMoveDir)
			applyAIMove(myHrp, myHum, safeRoam, myHrp.Position + safeRoam * 8, nil, dt)
		end
	else
		currentTargetPlr = nil
		cachedWaypoints = {}

		local threatChar, threatHrp = nil, nil
		local nearestDist = math.huge
		local crowdPositions = {}

		for _, plr in ipairs(Players:GetPlayers()) do
			if not isTeammate(plr) then
				local tChar, tHrp = getCharacterParts(plr)
				if tChar and tHrp and isInMatch(tChar, tHrp) and isInSameArena(myChar, myHrp, tChar, tHrp) then
					if hasBomb(tChar) then
						local d = (tHrp.Position - myHrp.Position).Magnitude
						if d < nearestDist then
							nearestDist = d
							threatChar = tChar
							threatHrp = tHrp
						end
					else
						table.insert(crowdPositions, tHrp.Position)
					end
				end
			end
		end

		local bombTimeLeft = threatChar and getRemainingBombTime(threatChar) or nil

		if threatHrp and (threatHrp.Position.Y - myHrp.Position.Y) > 3.5 and nearestDist <= Config.AIDodgeDist then
			handleVerticalEnemy(myChar, myHrp, myHum, threatHrp, false, (bombTimeLeft and bombTimeLeft <= 3.5) or false, dt)
			return
		end

		if threatHrp and ((bombTimeLeft and bombTimeLeft <= 3.5) or nearestDist < 10.5) then
			local awayFlat = Vector3.new(myHrp.Position.X - threatHrp.Position.X, 0, myHrp.Position.Z - threatHrp.Position.Z)
			local awayDir = (awayFlat.Magnitude > 0.05) and awayFlat.Unit or Vector3.new(1, 0, 0)
			local quickFlip = (math.floor(arcPhaseClock * 8) % 2 == 0) and 1 or -1
			local crescentEscape = rotateFlatVector(awayDir, (44 * jukeSign * quickFlip) + math.sin(arcPhaseClock * 9) * 18)
			local safeEscape = sanitizeDirection(myChar, myHrp, myHum, crescentEscape)

			currentTurnRate = 15.5
			aiSetLockButton(true, safeEscape)
			setShiftLockEnabled(true)
			applyAIMove(myHrp, myHum, safeEscape, myHrp.Position + safeEscape * 13, myHrp.Position + safeEscape * 9, dt)

			if nearestDist < 11 and math.random(1, 100) <= 58 then
				triggerJumpSkill(myHum, 0.52, safeEscape)
				jukeSign = -jukeSign
			end
			return
		elseif Config.AILock and ((not threatHrp) or (nearestDist > Config.AIDodgeDist + 6 and (not bombTimeLeft or bombTimeLeft > 5))) then
			aiSetLockButton(false, nil)
		end

		if Config.AILock and lockedMoveDir then
			local safeLocked = sanitizeDirection(myChar, myHrp, myHum, lockedMoveDir)
			currentTurnRate = 14.5
			setShiftLockEnabled(true)
			applyAIMove(myHrp, myHum, safeLocked, myHrp.Position + safeLocked * 12, myHrp.Position + safeLocked * 9, dt)
			return
		end

		local bestDir = currentMoveDir
		local bestDirScore = -math.huge
		for i = 0, 15 do
			local ang = math.rad(i * 22.5)
			local candidateDir = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local s = evaluateDirectionScore(myChar, myHrp, candidateDir, threatHrp, crowdPositions)
			if s > bestDirScore then
				bestDirScore = s
				bestDir = candidateDir
			end
		end

		if threatHrp and nearestDist <= Config.AIDodgeDist then
			local awayFlat = Vector3.new(myHrp.Position.X - threatHrp.Position.X, 0, myHrp.Position.Z - threatHrp.Position.Z)
			local awayDir = (awayFlat.Magnitude > 0.05) and awayFlat.Unit or bestDir

			if jukeTimer <= 0 and humanReactionDelay <= 0 then
				humanReactionDelay = math.random(8, 18) / 100
				if math.random(1, 100) <= 7 then
					humanHesitateTimer = math.random(5, 10) / 100
				end

				if math.random(1, 100) <= 68 then
					jukeSign = -jukeSign
				else
					jukeSign = (math.random(1, 2) == 1) and 1 or -1
				end

				pickNextJukePattern(nearestDist)
			end

			local rawJuke = buildLegendaryJukeDir(awayDir, bestDir)
			local safeJuke = sanitizeDirection(myChar, myHrp, myHum, rawJuke)
			lockedMoveDir = safeJuke

			local needsJukeShiftLock = (jukePhase == "snap" or jukePhase == "zig_snap") or (nearestDist < 13.5)
			setShiftLockEnabled(needsJukeShiftLock)
			applyAIMove(myHrp, myHum, safeJuke, myHrp.Position + safeJuke * 12, needsJukeShiftLock and (myHrp.Position + safeJuke * 9) or nil, dt)

			local threatLook = threatHrp.CFrame.LookVector
			local toMe = (myHrp.Position - threatHrp.Position).Unit
			local approachingMe = threatLook:Dot(toMe) > 0.30

			if nearestDist < 12 and approachingMe and math.random(1, 100) <= 55 then
				jukeSign = -jukeSign
				jukePhase = "snap"
				jukeTimer = 0.26
				currentTurnRate = 15.5
				triggerJumpSkill(myHum, 0.52, rotateFlatVector(safeJuke, 36 * jukeSign))
			end
		else
			jukePhase = "none"
			currentTurnRate = 11.0
			setShiftLockEnabled(false)
			if jukeTimer <= 0 then
				jukeTimer = math.random(35, 60) / 100
				if math.random(1, 100) <= 45 then
					jukeSign = -jukeSign
				end
				local side = Vector3.new(-bestDir.Z * jukeSign, 0, bestDir.X * jukeSign)
				local rawRoam = (bestDir * 0.84 + side * 0.32).Unit
				local safeRoam = sanitizeDirection(myChar, myHrp, myHum, rawRoam)
				lockedMoveDir = safeRoam
				applyAIMove(myHrp, myHum, safeRoam, myHrp.Position + safeRoam * 9, nil, dt)
			else
				local safeCurr = sanitizeDirection(myChar, myHrp, myHum, currentMoveDir)
				lockedMoveDir = safeCurr
				applyAIMove(myHrp, myHum, safeCurr, myHrp.Position + safeCurr * 9, nil, dt)
			end
		end
	end
end

-- أزرار الواجهة والتحكم بالزيادة والنقصان
createFeatureRow("reach", 1, "Bomb Reach", false, {
	key = "ReachSize",
	min = 4,
	max = 20,
	step = 1
}, function(state)
	Config.Reach = state
	if not state then
		resetReach()
	end
end)

createFeatureRow("ai", 2, "Smart AI", false, {
	key = "AIDodgeDist",
	min = 12,
	max = 60,
	step = 4
}, function(state)
	Config.AI = state
	cachedWaypoints = {}
	jukePhase = "none"
	releaseTouchControls()
	local myChar, _, myHum = getCharacterParts(LocalPlayer)
	if not state then
		setShiftLockEnabled(false)
		if myChar and myHum then
			myHum:MoveTo(myChar:GetPivot().Position)
		end
	end
end)

createFeatureRow("lock", 3, "Lock AI", false, nil, function(state)
	if state and not Config.AI then
		Config.AILock = false
		lockedMoveDir = nil
		task.defer(function()
			if rowRefs.lock and rowRefs.lock.setState then
				rowRefs.lock.setState(false)
			end
		end)
		return
	end
	Config.AILock = state
	lockedMoveDir = state and currentMoveDir or nil
end)

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	Body.Visible = not minimized
	MinBtn.Text = minimized and "+" or "-"
	MainFrame.Size = minimized and UDim2.new(0, 276, 0, HEADER_HEIGHT) or UDim2.new(0, 276, 0, FULL_HEIGHT)
end)

CloseBtn.MouseButton1Click:Connect(function()
	Config.Reach = false
	Config.AI = false
	Config.AILock = false
	releaseTouchControls()
	setShiftLockEnabled(false)
	resetReach()
	ScreenGui:Destroy()
end)

RunService.RenderStepped:Connect(function(dt)
	local myChar, myHrp, myHum = getCharacterParts(LocalPlayer)
	if not myChar or not myHrp or not myHum then return end

	if Config.AI then
		runSmartAI(myChar, myHrp, myHum, dt)
	else
		setShiftLockEnabled(false)
		releaseTouchControls()
	end
end)
