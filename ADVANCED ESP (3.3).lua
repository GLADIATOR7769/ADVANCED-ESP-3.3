--[[
	ESP Tester - adjustable settings panel
	--------------------------------------
	Put this in a LocalScript under StarterPlayer > StarterPlayerScripts
	of a place you own, then press Play in Studio.

	Tip: to see other players, use Test > Clients and Servers (2+ players),
	or turn on "Include Myself" to test solo.

	Controls:
	  - Drag the title bar to move the panel
	  - "-" collapses the panel, "X" unloads everything
	  - RightShift shows/hides the panel
	  - Click a slider, or type an exact value in its box
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------

-- The 5 outline colors you can pick from in the panel (edit these freely)
local OUTLINE_CHOICES = {
	{ Name = "White", Color = Color3.fromRGB(255, 255, 255) },
	{ Name = "Black", Color = Color3.fromRGB(0, 0, 0) },
	{ Name = "Gold", Color = Color3.fromRGB(255, 184, 11) },
	{ Name = "Prussian Blue", Color = Color3.fromRGB(0, 49, 83) },
	{ Name = "Forest Green", Color = Color3.fromRGB(31, 128, 29) },
	{ Name = "Maroon", Color = Color3.fromRGB(117, 0, 0) },
	
}

-- Where tracer lines start from (the panel button cycles through these)
local TRACER_ORIGINS = { "Bottom", "Center", "Top", "Mouse" }

local DEFAULTS = {
	Enabled = true,
	OutlineChoice = 1, -- index into OUTLINE_CHOICES (1 = White)

	ShowTracers = true,
	TracerOrigin = 1, -- index into TRACER_ORIGINS (1 = Bottom)
	TracerThickness = 2,
	TracerTransparency = 0.2,
	TracerUsePlayerColor = true,
	TracerColor = Color3.fromRGB(255, 255, 255), -- used when "Use Player Color" is OFF

	IncludeSelf = false,
	UseTeamColor = true,
	ThroughWalls = true,
	ShowHighlight = true,
	ShowBoxes = true,
	ShowNames = true,
	ShowDistance = false,

	FillTransparency = 0.4,
	OutlineTransparency = 0.1,
	BoxTransparency = 0.4,
	NameTransparency = 0.5,
	NameTextSize = 15,
	MaxDistance = 1000,

	FriendColor = Color3.fromRGB(0, 0, 255),
	EnemyColor = Color3.fromRGB(255, 0, 0),
}

local settings = {}
for key, value in pairs(DEFAULTS) do
	settings[key] = value
end

local running = true
local connections = {}

local function track(connection)
	table.insert(connections, connection)
	return connection
end

--------------------------------------------------------------------
-- Visuals (highlight, box, name tag) per player
--------------------------------------------------------------------

local holder = Instance.new("Folder")
holder.Name = "ESPTesterHolder"
holder.Parent = workspace

-- Tracers are drawn as thin rotated frames on their own full-screen gui
local tracerGui = Instance.new("ScreenGui")
tracerGui.Name = "ESPTesterTracers"
tracerGui.ResetOnSpawn = false
tracerGui.IgnoreGuiInset = true
tracerGui.DisplayOrder = 50
tracerGui.Parent = PlayerGui

local visuals = {} -- [Player] = { Folder, Tracer, Box, Tag, Label, Highlight, Root }

local function destroyVisuals(player)
	local v = visuals[player]
	if v then
		visuals[player] = nil
		v.Folder:Destroy()
		v.Tracer:Destroy()
	end
end

local function buildVisuals(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local head = character:WaitForChild("Head", 5)

	if not running or not root or not head or player.Character ~= character then
		return
	end

	destroyVisuals(player)

	local folder = Instance.new("Folder")
	folder.Name = player.Name

	local box = Instance.new("BoxHandleAdornment")
	box.Name = "Box"
	box.Adornee = root
	box.Size = character:GetExtentsSize()
	box.ZIndex = 1
	box.Parent = folder

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Adornee = head
	tag.Size = UDim2.fromOffset(200, 50)
	tag.StudsOffset = Vector3.new(0, 1.8, 0)
	tag.Parent = folder

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 40)
	label.Position = UDim2.new(0, 0, 0.5, -20)
	label.Font = Enum.Font.SourceSansBold
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag

	local highlight = Instance.new("Highlight")
	highlight.Name = "Highlight"
	highlight.Adornee = character
	highlight.Parent = folder

	folder.Parent = holder

	local tracer = Instance.new("Frame")
	tracer.Name = player.Name
	tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	tracer.BorderSizePixel = 0
	tracer.Visible = false
	tracer.Parent = tracerGui

	visuals[player] = {
		Folder = folder,
		Tracer = tracer,
		Box = box,
		Tag = tag,
		Label = label,
		Highlight = highlight,
		Root = root,
	}
end

-- With "Team Colors" off, players on your team use Friend color, others use Enemy color.
-- (In a game with no teams everyone shares a team color, so everyone counts as a friend.)
local function getColor(player)
	if settings.UseTeamColor then
		return player.TeamColor.Color
	end
	if player.TeamColor == LocalPlayer.TeamColor then
		return settings.FriendColor
	end
	return settings.EnemyColor
end

-- Positions a frame as a line between two screen points
local function setLine(frame, a, b, thickness)
	local delta = b - a
	frame.Size = UDim2.fromOffset(delta.Magnitude, thickness)
	frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
end

local function getTracerOrigin(camera)
	local size = camera.ViewportSize
	local mode = settings.TracerOrigin
	if mode == 1 then
		return Vector2.new(size.X / 2, size.Y)
	elseif mode == 2 then
		return size / 2
	elseif mode == 3 then
		return Vector2.new(size.X / 2, 0)
	end
	return UserInputService:GetMouseLocation()
end

local function updateTracer(tracer, worldPosition, color, show, camera, origin)
	if not show then
		tracer.Visible = false
		return
	end

	local screenPos = camera:WorldToViewportPoint(worldPosition)
	if screenPos.Z <= 0.05 then -- behind the camera
		tracer.Visible = false
		return
	end

	local target = Vector2.new(
		math.clamp(screenPos.X, -20000, 20000),
		math.clamp(screenPos.Y, -20000, 20000)
	)
	setLine(tracer, origin, target, settings.TracerThickness)
	tracer.BackgroundColor3 = settings.TracerUsePlayerColor and color or settings.TracerColor
	tracer.BackgroundTransparency = settings.TracerTransparency
	tracer.Visible = true
end

local function updateAll()
	local myCharacter = LocalPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local origin = camera and getTracerOrigin(camera)

	for player, v in pairs(visuals) do
		local visible = settings.Enabled and v.Root.Parent ~= nil
		local distance = 0

		if player == LocalPlayer then
			if not settings.IncludeSelf then
				visible = false
			end
		elseif visible and myRoot then
			distance = (v.Root.Position - myRoot.Position).Magnitude
			if distance > settings.MaxDistance then
				visible = false
			end
		end

		local color = getColor(player)

		local highlight = v.Highlight
		highlight.Enabled = visible and settings.ShowHighlight
		highlight.FillColor = color
		highlight.OutlineColor = OUTLINE_CHOICES[settings.OutlineChoice].Color
		highlight.FillTransparency = settings.FillTransparency
		highlight.OutlineTransparency = settings.OutlineTransparency
		highlight.DepthMode = settings.ThroughWalls
			and Enum.HighlightDepthMode.AlwaysOnTop
			or Enum.HighlightDepthMode.Occluded

		local box = v.Box
		box.Visible = visible and settings.ShowBoxes
		box.Color3 = color
		box.Transparency = settings.BoxTransparency
		box.AlwaysOnTop = settings.ThroughWalls

		local tag = v.Tag
		tag.Enabled = visible and settings.ShowNames
		tag.AlwaysOnTop = settings.ThroughWalls

		local label = v.Label
		label.TextColor3 = color
		label.TextSize = settings.NameTextSize
		label.TextTransparency = settings.NameTransparency
		if settings.ShowDistance then
			label.Text = string.format("%s [%d]", player.Name, math.floor(distance))
		else
			label.Text = player.Name
		end

		updateTracer(
			v.Tracer,
			v.Root.Position,
			color,
			camera ~= nil and visible and settings.ShowTracers and player ~= LocalPlayer,
			camera,
			origin
		)
	end
end

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------

local THEME = {
	bg = Color3.fromRGB(28, 28, 34),
	title = Color3.fromRGB(40, 40, 50),
	field = Color3.fromRGB(50, 50, 62),
	text = Color3.fromRGB(235, 235, 240),
	muted = Color3.fromRGB(150, 150, 165),
	accent = Color3.fromRGB(0, 140, 255),
	on = Color3.fromRGB(40, 150, 90),
	off = Color3.fromRGB(75, 75, 90),
	danger = Color3.fromRGB(190, 60, 60),
}

local refreshers = {} -- functions that re-sync the UI with `settings`
local activeDrag = nil -- function(input) while a slider or the title bar is being dragged

local function corner(instance, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

local gui = Instance.new("ScreenGui")
gui.Name = "ESPTesterUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = PlayerGui

local EXPANDED_SIZE = UDim2.fromOffset(300, 480)
local COLLAPSED_SIZE = UDim2.fromOffset(300, 32)

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = EXPANDED_SIZE
main.Position = UDim2.fromOffset(20, 80)
main.BackgroundColor3 = THEME.bg
main.BorderSizePixel = 0
main.Active = true
main.ClipsDescendants = true
main.Parent = gui
corner(main, 8)

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = THEME.title
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = main

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.fromOffset(12, 0)
titleLabel.Size = UDim2.new(1, -80, 1, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextColor3 = THEME.text
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "ADVANCED ESP 3.3"
titleLabel.Parent = titleBar

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Position = UDim2.fromOffset(0, 32)
body.Size = UDim2.new(1, 0, 1, -32)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = body

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Title bar dragging + minimize / unload buttons
titleBar.InputBegan:Connect(function(input)
	if isPointer(input) then
		local dragStart = input.Position
		local startPos = main.Position
		activeDrag = function(i)
			local delta = i.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end
end)

local function makeTitleButton(text, xOffset, color)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, xOffset, 0.5, 0)
	b.Size = UDim2.fromOffset(24, 22)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = THEME.text
	b.Text = text
	b.Parent = titleBar
	corner(b, 5)
	return b
end

local collapseButton = makeTitleButton("-", -36, THEME.off)
local closeButton = makeTitleButton("X", -8, THEME.danger)

local collapsed = false
collapseButton.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	body.Visible = not collapsed
	main.Size = collapsed and COLLAPSED_SIZE or EXPANDED_SIZE
	collapseButton.Text = collapsed and "+" or "-"
end)

-- Shared drag handling for sliders and the title bar
track(UserInputService.InputChanged:Connect(function(input)
	if activeDrag and (
		input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	) then
		activeDrag(input)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if isPointer(input) then
		activeDrag = nil
		body.ScrollingEnabled = true
	end
end))

-- Builders ----------------------------------------------------------

local function addHeader(text)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 22)
	l.LayoutOrder = nextOrder()
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextColor3 = THEME.accent
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = string.upper(text)
	l.Parent = body
	return l
end

local function addButton(text, color, callback)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.LayoutOrder = nextOrder()
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = THEME.text
	b.Text = text
	b.Parent = body
	corner(b, 6)
	if callback then
		b.MouseButton1Click:Connect(callback)
	end
	return b
end

local function addToggle(labelText, key)
	local button = addButton("", THEME.off)

	local function refresh()
		local on = settings[key]
		button.Text = string.format("%s: %s", labelText, on and "ON" or "OFF")
		button.BackgroundColor3 = on and THEME.on or THEME.off
	end

	button.MouseButton1Click:Connect(function()
		settings[key] = not settings[key]
		refresh()
	end)

	refresh()
	table.insert(refreshers, refresh)
end

local function addSlider(labelText, minV, maxV, step, decimals, getValue, setValue)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = nextOrder()
	frame.Parent = body

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, 0, 0, 20)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = THEME.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = frame

	local valueBox = Instance.new("TextBox")
	valueBox.AnchorPoint = Vector2.new(1, 0)
	valueBox.Position = UDim2.new(1, 0, 0, 0)
	valueBox.Size = UDim2.fromOffset(60, 20)
	valueBox.BackgroundColor3 = THEME.field
	valueBox.BorderSizePixel = 0
	valueBox.Font = Enum.Font.GothamMedium
	valueBox.TextSize = 12
	valueBox.TextColor3 = THEME.text
	valueBox.ClearTextOnFocus = false
	valueBox.Parent = frame
	corner(valueBox, 5)

	-- Hit area (taller than the visible bar so it is easy to grab)
	local hit = Instance.new("Frame")
	hit.Position = UDim2.new(0, 7, 0, 24)
	hit.Size = UDim2.new(1, -14, 0, 20)
	hit.BackgroundTransparency = 1
	hit.Active = true
	hit.Parent = frame

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 0, 0.5, 0)
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.BackgroundColor3 = THEME.field
	bar.BorderSizePixel = 0
	bar.Parent = hit
	corner(bar, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = THEME.accent
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 3)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.BackgroundColor3 = THEME.text
	knob.BorderSizePixel = 0
	knob.Parent = hit
	corner(knob, 7)

	local function snap(v)
		v = math.clamp(v, minV, maxV)
		v = math.floor((v - minV) / step + 0.5) * step + minV
		return math.clamp(v, minV, maxV)
	end

	local function render()
		local v = getValue()
		local alpha = (v - minV) / (maxV - minV)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueBox.Text = string.format("%." .. decimals .. "f", v)
	end

	local function apply(v)
		setValue(snap(v))
		render()
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			body.ScrollingEnabled = false

			local function update(position)
				local alpha = math.clamp(
					(position.X - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1
				)
				apply(minV + (maxV - minV) * alpha)
			end

			update(input.Position)
			activeDrag = function(i)
				update(i.Position)
			end
		end
	end)

	valueBox.FocusLost:Connect(function()
		local n = tonumber(valueBox.Text)
		if n then
			apply(n)
		else
			render()
		end
	end)

	render()
	table.insert(refreshers, render)
end

local function addNumberSlider(labelText, key, minV, maxV, step, decimals)
	addSlider(labelText, minV, maxV, step, decimals,
		function() return settings[key] end,
		function(v) settings[key] = v end
	)
end

local function addColorGroup(title, key)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.LayoutOrder = nextOrder()
	header.Parent = body

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -40, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = THEME.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = title
	label.Parent = header

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(1, 0.5)
	swatch.Position = UDim2.new(1, 0, 0.5, 0)
	swatch.Size = UDim2.fromOffset(32, 18)
	swatch.BorderSizePixel = 0
	swatch.Parent = header
	corner(swatch, 4)

	local function updateSwatch()
		swatch.BackgroundColor3 = settings[key]
	end
	updateSwatch()
	table.insert(refreshers, updateSwatch)

	for _, channel in ipairs({ "R", "G", "B" }) do
		addSlider(channel, 0, 255, 1, 0,
			function()
				return math.round(settings[key][channel] * 255)
			end,
			function(v)
				local c = settings[key]
				local r, g, b = math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)
				if channel == "R" then
					r = v
				elseif channel == "G" then
					g = v
				else
					b = v
				end
				settings[key] = Color3.fromRGB(r, g, b)
				updateSwatch()
			end
		)
	end
end

-- A button that cycles through a list of options each click
local function addCycleButton(labelText, key, options)
	local button = addButton("", THEME.off)

	local function refresh()
		button.Text = string.format("%s: %s", labelText, options[settings[key]])
	end

	button.MouseButton1Click:Connect(function()
		settings[key] = settings[key] % #options + 1
		refresh()
	end)

	refresh()
	table.insert(refreshers, refresh)
end

local function addOutlinePicker()
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.LayoutOrder = nextOrder()
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 13
	title.TextColor3 = THEME.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = body

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundTransparency = 1
	row.LayoutOrder = nextOrder()
	row.Parent = body

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local strokes = {}

	local function refresh()
		title.Text = "Outline Color: " .. OUTLINE_CHOICES[settings.OutlineChoice].Name
		for i, stroke in ipairs(strokes) do
			local selected = (i == settings.OutlineChoice)
			stroke.Thickness = selected and 3 or 1
			stroke.Color = selected and THEME.accent or THEME.muted
		end
	end

	for i, choice in ipairs(OUTLINE_CHOICES) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, -5, 1, 0)
		b.LayoutOrder = i
		b.BackgroundColor3 = choice.Color
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = row
		corner(b, 6)

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b
		strokes[i] = stroke

		b.MouseButton1Click:Connect(function()
			settings.OutlineChoice = i
			refresh()
		end)
	end

	refresh()
	table.insert(refreshers, refresh)
end

-- Panel content -------------------------------------------------------

addHeader("General")
addToggle("ESP", "Enabled")
addToggle("Include Myself", "IncludeSelf")
addToggle("Through Walls", "ThroughWalls")
addNumberSlider("Max Distance", "MaxDistance", 50, 5000, 50, 0)

addHeader("Highlight & Box")
addToggle("Highlight", "ShowHighlight")
addToggle("Boxes", "ShowBoxes")
addNumberSlider("Fill Transparency", "FillTransparency", 0, 1, 0.05, 2)
addNumberSlider("Outline Transparency", "OutlineTransparency", 0, 1, 0.05, 2)
addOutlinePicker()
addNumberSlider("Box Transparency", "BoxTransparency", 0, 1, 0.05, 2)

addHeader("Name Tags")
addToggle("Names", "ShowNames")
addNumberSlider("Text Size", "NameTextSize", 8, 30, 1, 0)
addNumberSlider("Text Transparency", "NameTransparency", 0, 1, 0.05, 2)
addToggle("Distance", "ShowDistance")

addHeader("Tracers")
addToggle("Tracers", "ShowTracers")
addCycleButton("Origin", "TracerOrigin", TRACER_ORIGINS)
addNumberSlider("Thickness", "TracerThickness", 1, 8, 1, 0)
addNumberSlider("Transparency", "TracerTransparency", 0, 1, 0.05, 2)
addToggle("Use Player Color", "TracerUsePlayerColor")
addColorGroup("Tracer color (Player Color OFF)", "TracerColor")

addHeader("Colors")
addToggle("Team Colors", "UseTeamColor")
addColorGroup("Friend color (Team Colors OFF)", "FriendColor")
addColorGroup("Enemy color (Team Colors OFF)", "EnemyColor")

addHeader("Actions")
addButton("Reset to Defaults", THEME.accent, function()
	for key, value in pairs(DEFAULTS) do
		settings[key] = value
	end
	for _, refresh in ipairs(refreshers) do
		refresh()
	end
end)

local function unload()
	running = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in pairs(visuals) do
		destroyVisuals(player)
	end
	holder:Destroy()
	tracerGui:Destroy()
	gui:Destroy()
end

addButton("Unload ESP", THEME.danger, unload)
closeButton.MouseButton1Click:Connect(unload)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, 0, 0, 18)
hint.LayoutOrder = nextOrder()
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = THEME.muted
hint.Text = "RightShift: show / hide panel"
hint.Parent = body

track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift then
		gui.Enabled = not gui.Enabled
	end
end))

--------------------------------------------------------------------
-- Start
--------------------------------------------------------------------

local function trackPlayer(player)
	track(player.CharacterAdded:Connect(function(character)
		task.spawn(buildVisuals, player, character)
	end))
	track(player.CharacterRemoving:Connect(function()
		destroyVisuals(player)
	end))

	if player.Character then
		task.spawn(buildVisuals, player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	trackPlayer(player)
end

track(Players.PlayerAdded:Connect(trackPlayer))
track(Players.PlayerRemoving:Connect(destroyVisuals))
track(RunService.RenderStepped:Connect(updateAll))
