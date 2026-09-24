local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Signal = require(ReplicatedStorage.Packages.Signal)

local System = ReplicatedStorage:WaitForChild("NotificationSystem")
local Styles = require(System.Notifications)
local Validation = require(System.Validation)
local Types = require(ReplicatedStorage.Types)

local NotificationClient = Knit.CreateController({
	Name = "NotificationClient"
})

local EntranceTime = 0.45
local ExitTime = 0.24
local Gap = 10

local function PlayTween(Entry, Target, Info, Properties)
	local Tween = TweenService:Create(Target, Info, Properties)
	table.insert(Entry.Tweens, Tween)
	Tween:Play()
end

function NotificationClient:GetState()
	-- Return a snapshot, never the live entry tables; showcase assertions cannot mutate timers.
	local State = {Pending = 0, Visible = 0, Total = self.Count, Entries = {}}
	for Id, Entry in self.Entries do
		local IsPending = Entry.State == "Queued"
		State.Pending += if IsPending then 1 else 0
		State.Visible += if IsPending then 0 else 1
		State.Entries[Id] = {
			State = Entry.State,
			Position = Entry.Payload.Position,
			Remaining = Entry.Remaining,
			Hovered = Entry.Hovered
		}
	end
	return State
end

function NotificationClient:_Finish(Entry, Reason)
	if self.Entries[Entry.Id] ~= Entry then
		return
	end

	self.Entries[Entry.Id] = nil
	self.Count -= 1
	for _, Connection in Entry.Connections do
		Connection:Disconnect()
	end
	for _, Tween in Entry.Tweens do
		Tween:Cancel()
	end
	if Entry.Slot then
		Entry.Slot:Destroy()
	end
	self.Closed:Fire(Entry.Id, Reason)
end

function NotificationClient:Dismiss(Id : string, Reason : string?)
	local Entry = self.Entries[Id]
	if not Entry or Entry.State == "Closing" then
		return false
	end

	Reason = Reason or "Dismissed"
	if Entry.State == "Queued" then
		self:_Finish(Entry, Reason)
	else
		-- Closing still occupies a lane slot, so the next card cannot overlap its exit animation.
		Entry.State = "Closing"
		Entry.Reason = Reason
		Entry.TransitionAt = os.clock() + ExitTime
		for _, Tween in Entry.Tweens do
			Tween:Cancel()
		end
		table.clear(Entry.Tweens)

		if Styles[Entry.Payload.Style].SpringOut then
			PlayTween(Entry, Entry.Scale, TweenInfo.new(ExitTime, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
		else
			local Direction = if Entry.Payload.Position == "Upper" then -1 else 1
			PlayTween(Entry, Entry.Card, TweenInfo.new(ExitTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(1.6, 0, 0.5, Direction * 12)
			})
		end
	end
	return true
end

function NotificationClient:Clear()
	local Entries = {}
	for _, Entry in self.Entries do
		table.insert(Entries, Entry)
	end
	for _, Entry in Entries do
		self:_Finish(Entry, "Cleared")
	end
	table.clear(self.Queue)
end

function NotificationClient:Notify(notif : Types.Notification, Id : string?)
	local Payload, Message = Validation.Normalize(notif)
	if not Payload then
		return nil, Message
	end
	if self.Count >= Validation.MaxPending then
		return nil, "Notification queue is full."
	end

	Id = Id or ("Local-" .. HttpService:GenerateGUID(false))
	if type(Id) ~= "string" or self.Entries[Id] then
		return nil, "Notification ID must be unique."
	end

	self.Sequence += 1
	local Entry = {
		Id = Id,
		Payload = Payload,
		State = "Queued",
		ReadyAt = os.clock() + Payload.Delay,
		Remaining = Payload.Duration,
		Order = self.Sequence,
		Hovered = false,
		Connections = {},
		Tweens = {}
	}
	self.Entries[Id] = Entry
	self.Count += 1
	table.insert(self.Queue, Entry)
	return Id
end

function NotificationClient:_SetHovered(Entry, Hovered)
	Entry.Hovered = Hovered
end

function NotificationClient:_Show(Entry)
	local Payload = Entry.Payload
	local Information = Styles[Payload.Style]
	local Area = self.Areas[Payload.Position]

	-- UIListLayout owns slots; the nested card owns motion. Separating them prevents
	-- layout recalculation from fighting the entrance and exit tweens.
	local Slot = Instance.new("Frame")
	Slot.Name = Entry.Id
	Slot.BackgroundTransparency = 1
	Slot.Size = UDim2.new(1, 0, 0, Information.Height)
	Slot.LayoutOrder = Entry.Order
	Slot.Parent = Area

	local Card = self.Templates[Information.Template]:Clone()
	Card.Name = "Card"
	Card.Visible = true
	Card.Size = UDim2.fromScale(1, 1)
	Card.Parent = Slot
	Entry.Slot = Slot
	Entry.Card = Card

	for _, Layout in Card:GetChildren() do
		if Layout:IsA("Frame") then
			Layout.Visible = Layout.Name == (if Payload.Image then "ImageLayout" else "NoImageLayout")
		end
	end
	local Layout = Card[if Payload.Image then "ImageLayout" else "NoImageLayout"]
	local Left = if Payload.Image then 76 else 0
	Layout.Title.Text = Payload.Title
	Layout.Title.Visible = Payload.DisplayTitle
	Layout.Description.Text = Payload.Description
	if not Payload.DisplayTitle then
		Layout.Description.Position = UDim2.fromOffset(Left, 0)
		Layout.Description.Size = UDim2.new(1, -Left, 1, 0)
	end
	local Separator = Layout:FindFirstChild("Seperator")
	if Separator then
		Separator.Visible = Payload.DisplayTitle
	end
	if Payload.Image then
		Layout.Image.Image = Payload.Image
	end

	local Close = Instance.new("TextButton")
	Close.Name = "Dismiss"
	Close.AnchorPoint = Vector2.new(1, 0)
	Close.Position = UDim2.new(1, -4, 0, 4)
	Close.Size = UDim2.fromOffset(32, 32)
	Close.BackgroundTransparency = 1
	Close.Text = "×"
	Close.TextColor3 = Color3.new(1, 1, 1)
	Close.TextSize = 24
	Close.Font = Enum.Font.Gotham
	Close.Selectable = true
	Close.Visible = Payload.Dismissible
	Close.ZIndex = 3
	Close.Parent = Card
	table.insert(Entry.Connections, Close.Activated:Connect(function()
		self:Dismiss(Entry.Id)
	end))

	local Progress = Instance.new("Frame")
	Progress.Name = "Progress"
	Progress.BorderSizePixel = 0
	Progress.BackgroundColor3 = Color3.fromRGB(165, 194, 255)
	Progress.AnchorPoint = Vector2.new(0, 1)
	Progress.Position = UDim2.new(0, 14, 1, -5)
	Progress.Size = UDim2.new(1, -28, 0, 2)
	Progress.Visible = Payload.ShowProgress and Payload.Duration > 0
	Progress.Parent = Card
	Entry.Progress = Progress

	-- Mouse and gamepad focus share the same pause path; touch uses the Activated close control.
	table.insert(Entry.Connections, Card.MouseEnter:Connect(function()
		self:_SetHovered(Entry, true)
	end))
	table.insert(Entry.Connections, Card.MouseLeave:Connect(function()
		self:_SetHovered(Entry, false)
	end))
	table.insert(Entry.Connections, Close.SelectionGained:Connect(function()
		self:_SetHovered(Entry, true)
	end))
	table.insert(Entry.Connections, Close.SelectionLost:Connect(function()
		self:_SetHovered(Entry, false)
	end))

	local Scale = Instance.new("UIScale")
	Scale.Name = "AnimationScale"
	Scale.Parent = Card
	Entry.Scale = Scale
	Entry.State = "Entering"
	Entry.TransitionAt = os.clock() + EntranceTime
	if Information.SpringIn then
		Scale.Scale = 0.05
		PlayTween(Entry, Scale, TweenInfo.new(EntranceTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	else
		Card.Position = UDim2.new(1.6, 0, 0.5, 0)
		PlayTween(Entry, Card, TweenInfo.new(EntranceTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5)
		})
	end
	self.Shown:Fire(Entry.Id, table.clone(Payload))
end

function NotificationClient:_Step(Delta)
	local Now = os.clock()
	local Occupied = {Upper = 0, Lower = 0}
	for _, Entry in self.Entries do
		if Entry.State == "Entering" and Now >= Entry.TransitionAt then
			Entry.State = "Visible"
			-- Duration measures reading time, excluding entrance animation and queue delay.
			Entry.Remaining = Entry.Payload.Duration
		elseif Entry.State == "Visible" and Entry.Payload.Duration > 0 then
			if not (Entry.Payload.PauseOnHover and Entry.Hovered) then
				Entry.Remaining = math.max(0, Entry.Remaining - Delta)
			end
			local Fraction = Entry.Remaining / Entry.Payload.Duration
			Entry.Progress.Size = UDim2.new(Fraction, -28 * Fraction, 0, 2)
			if Entry.Remaining <= 0 then
				self:Dismiss(Entry.Id, "Expired")
			end
		elseif Entry.State == "Closing" and Now >= Entry.TransitionAt then
			self:_Finish(Entry, Entry.Reason)
		end
		if self.Entries[Entry.Id] and Entry.State ~= "Queued" then
			Occupied[Entry.Payload.Position] += 1
		end
	end

	local Index = 1
	while Index <= #self.Queue do
		local Entry = self.Queue[Index]
		local Position = Entry.Payload.Position
		local Capacity = math.clamp(math.floor((self.Areas[Position].AbsoluteSize.Y + Gap) / (116 + Gap)), 1, Validation.MaxVisible)
		if not self.Entries[Entry.Id] then
			table.remove(self.Queue, Index)
		elseif Now >= Entry.ReadyAt and Occupied[Position] < Capacity then
			table.remove(self.Queue, Index)
			self:_Show(Entry)
			Occupied[Position] += 1
		else
			-- A delayed card does not block ready cards, and each lane advances independently.
			Index += 1
		end
	end
end

function NotificationClient:KnitInit()
	self.Entries = {}
	self.Queue = {}
	self.Count = 0
	self.Sequence = 0
	self.Shown = Signal.new()
	self.Closed = Signal.new()
	self.Connections = {}
	self.Templates = System:WaitForChild("NotificationStyles")
	self.Service = Knit.GetService("NotificationService")

	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = System:WaitForChild("NotificationGUI"):Clone()
	self.Gui.ResetOnSpawn = false
	self.Gui.Parent = PlayerGui
	self.Areas = {
		Upper = self.Gui.UpperNotificationArea,
		Lower = self.Gui.LowerNotificationArea
	}

	for Position, Area in self.Areas do
		Area.AnchorPoint = Vector2.new(0.5, if Position == "Upper" then 0 else 1)
		Area.Position = if Position == "Upper" then UDim2.new(0.5, 0, 0, 14) else UDim2.new(0.5, 0, 1, -14)
		Area.Size = UDim2.new(1, -24, 0.5, -24)
		Area.Visible = true
		-- Interactable is inherited: a disabled lane suppresses every descendant close button.
		Area.Interactable = true

		local Constraint = Instance.new("UISizeConstraint")
		Constraint.MaxSize = Vector2.new(520, 10000)
		Constraint.Parent = Area

		local Layout = Instance.new("UIListLayout")
		Layout.Padding = UDim.new(0, Gap)
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		Layout.VerticalAlignment = if Position == "Upper" then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
		Layout.Parent = Area
	end

	table.insert(self.Connections, self.Service.AnimateNotification:Connect(function(Payload)
		if type(Payload) == "table" then
			self:Notify(Payload, Payload.Id)
		end
	end))
	table.insert(self.Connections, self.Service.DismissNotification:Connect(function(Id)
		self:Dismiss(Id)
	end))
	table.insert(self.Connections, self.Service.ClearNotifications:Connect(function()
		self:Clear()
	end))
	table.insert(self.Connections, RunService.Heartbeat:Connect(function(Delta)
		self:_Step(Delta)
	end))
end

function NotificationClient:Destroy()
	-- Explicit teardown supports test isolation and future screen/controller replacement.
	self:Clear()
	for _, Connection in self.Connections do
		Connection:Disconnect()
	end
	self.Shown:Destroy()
	self.Closed:Destroy()
	self.Gui:Destroy()
end

function NotificationClient:KnitStart()
	self.Service.Ready:Fire()
	print("[Knit]: Notification Client started.")
end

return NotificationClient
