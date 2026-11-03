-- Connected Discord-GitHub
-- All systems for the Notification System writen entirely by @ccommu on discord / dev_Commu on roblox.

-- The server routes notification data; this controller owns each player's UI and reading timers.
-- Entries move through Queued -> Entering -> Visible -> Closing before cleanup removes them.
-- Queued entries can be removed immediately because they do not own any UI yet.

-- Cache engine services once so every card uses the same rendering, timing, and ID facilities.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
-- Waiting for Packages and Knit lets replication finish before the controller is registered.
-- Local signals expose lifecycle events without sending UI state back over the network.
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Signal = require(ReplicatedStorage.Packages.Signal)

-- Shared defaults and validation keep local calls consistent with server-delivered payloads.
-- Types documents the caller-facing options; Normalize supplies the complete rendering payload.
local System = ReplicatedStorage:WaitForChild("NotificationSystem")
local Styles = require(System.Notifications)
local Validation = require(System.Validation)
local Types = require(ReplicatedStorage.Types)

-- Register with Knit so other controllers can find this instance and Knit can run its hooks.
local NotificationClient = Knit.CreateController({
	Name = "NotificationClient"
})

-- Transition deadlines use the same durations as the tweens, so lane ownership follows motion.
-- Gap is shared by layout spacing and capacity calculations to account for space between cards.
local EntranceTime = 0.45
local ExitTime = 0.24
local Gap = 10

-- Each entry owns its tweens so dismissal can interrupt an entrance and cleanup can cancel motion.
local function PlayTween(Entry, Target, Info, Properties)
	local Tween = TweenService:Create(Target, Info, Properties)
	table.insert(Entry.Tweens, Tween)
	Tween:Play()
end

function NotificationClient:GetState()
	-- Return a snapshot, never the live entry tables; showcase assertions cannot mutate timers.
	-- Visible counts every entry occupying a lane, including cards still entering or closing.
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
	-- Check table identity as well as the ID: stale cleanup must not remove a newer entry
	-- that happens to reuse the same ID, or decrement Count twice for an already-finished card.
	if self.Entries[Entry.Id] ~= Entry then
		return
	end

	-- Remove registry ownership first, then release entry-owned resources before notifying observers.
	-- Destroying the slot also destroys its card, controls, and animation scale descendants.
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

-- Dismiss accepts both queued and rendered IDs; repeated requests cannot restart an exit timer.
function NotificationClient:Dismiss(Id : string, Reason : string?)
	local Entry = self.Entries[Id]
	if not Entry or Entry.State == "Closing" then
		return false
	end

	Reason = Reason or "Dismissed"
	if Entry.State == "Queued" then
		-- No card has been created, so cancellation needs cleanup without an exit animation.
		self:_Finish(Entry, Reason)
	else
		-- Closing still occupies a lane slot, so the next card cannot overlap its exit animation.
		Entry.State = "Closing"
		Entry.Reason = Reason
		Entry.TransitionAt = os.clock() + ExitTime
		-- Stop entrance motion before starting the exit so two tweens do not fight over properties.
		for _, Tween in Entry.Tweens do
			Tween:Cancel()
		end
		table.clear(Entry.Tweens)

		-- Styles choose scale-based or sliding exits. The lane determines the slide's vertical
		-- offset so upper and lower cards move toward their respective screen edges.
		if Styles[Entry.Payload.Style].SpringOut then
			PlayTween(Entry, Entry.Scale, TweenInfo.new(ExitTime, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
		else
			local Direction = if Entry.Payload.Position == "Upper" then -1 else 1
			PlayTween(Entry, Entry.Card, TweenInfo.new(ExitTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(1.6, 0, 0.5, Direction * 12)
			})
		end
	end
	-- True means the dismissal was accepted; a rendered card still needs time to finish closing.
	return true
end

function NotificationClient:Clear()
	-- Snapshot entries before finishing them because _Finish removes keys from the live registry.
	-- Clear bypasses exit animations so visible and delayed work are discarded immediately.
	local Entries = {}
	for _, Entry in self.Entries do
		table.insert(Entries, Entry)
	end
	for _, Entry in Entries do
		self:_Finish(Entry, "Cleared")
	end
	-- Queue references are separate from registry ownership and must also be dropped.
	table.clear(self.Queue)
end

function NotificationClient:Notify(notif : Types.Notification, Id : string?)
	-- Normalize creates an allowlisted copy, fills defaults, and rejects invalid options before
	-- any state changes. Later caller edits therefore cannot change an admitted notification.
	local Payload, Message = Validation.Normalize(notif)
	if not Payload then
		return nil, Message
	end
	-- Count includes all lifecycle states, bounding UI and delayed work together during bursts.
	if self.Count >= Validation.MaxPending then
		return nil, "Notification queue is full."
	end

	-- Preserve server-provided IDs for later remote dismissal. Local GUIDs use a prefix to
	-- distinguish them from server-generated IDs; duplicate active IDs would overwrite ownership.
	Id = Id or ("Local-" .. HttpService:GenerateGUID(false))
	if type(Id) ~= "string" or self.Entries[Id] then
		return nil, "Notification ID must be unique."
	end

	-- ReadyAt controls eligibility, while Remaining is reserved for time spent fully visible.
	-- Sequence supplies a stable LayoutOrder even when delays change the order cards become ready.
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
	-- The registry supports direct lookup and cleanup; the queue preserves admission order.
	-- UI creation waits for a lane slot, so delayed or excess entries do not allocate cards.
	self.Entries[Id] = Entry
	self.Count += 1
	table.insert(self.Queue, Entry)
	return Id
end

-- Input callbacks only record pause state; _Step applies PauseOnHover to the reading timer.
-- Keeping the timer in one place also lets the showcase exercise pause behavior directly.
function NotificationClient:_SetHovered(Entry, Hovered)
	Entry.Hovered = Hovered
end

-- Only admitted entries reach this method: validation has resolved the style and lane names.
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

	-- Clone per entry so text, visibility, and animations never modify the shared style template.
	local Card = self.Templates[Information.Template]:Clone()
	Card.Name = "Card"
	Card.Visible = true
	Card.Size = UDim2.fromScale(1, 1)
	Card.Parent = Slot
	Entry.Slot = Slot
	Entry.Card = Card

	-- Templates can contain both text arrangements. Only the normalized image choice is shown;
	-- unsupported images have already been removed by validation, selecting the text-only layout.
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
		-- Reclaim the title's vertical space while retaining the image column when one is present.
		Layout.Description.Position = UDim2.fromOffset(Left, 0)
		Layout.Description.Size = UDim2.new(1, -Left, 1, 0)
	end
	local Separator = Layout:FindFirstChild("Seperator")
	if Separator then
		-- Some templates omit the divider; those that include it only need it beneath a title.
		Separator.Visible = Payload.DisplayTitle
	end
	if Payload.Image then
		Layout.Image.Image = Payload.Image
	end

	-- A common close control gives every style the same dismissal behavior. Dismissible governs
	-- user access to this control; code can still dismiss persistent or non-dismissible cards.
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
	-- Activated handles mouse, touch, and gamepad activation through the same lifecycle path.
	-- Store card connections on the entry so _Finish can disconnect them when the card goes away.
	table.insert(Entry.Connections, Close.Activated:Connect(function()
		self:Dismiss(Entry.Id)
	end))

	-- The progress bar is driven by Remaining rather than a tween, keeping it in sync with pauses.
	-- Duration zero means persistent, so there is no countdown to display for that entry.
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

	-- Scaling the nested card leaves its reserved layout height unchanged during spring motion.
	-- Entering defers the reading countdown until the entrance deadline is reached in _Step.
	local Scale = Instance.new("UIScale")
	Scale.Name = "AnimationScale"
	Scale.Parent = Card
	Entry.Scale = Scale
	Entry.State = "Entering"
	Entry.TransitionAt = os.clock() + EntranceTime
	if Information.SpringIn then
		-- Back easing overshoots the target scale to give spring-enabled styles their pop-in effect.
		Scale.Scale = 0.05
		PlayTween(Entry, Scale, TweenInfo.new(EntranceTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	else
		-- Start beyond the lane's right edge and slide to the template's centered anchor position.
		Card.Position = UDim2.new(1.6, 0, 0.5, 0)
		PlayTween(Entry, Card, TweenInfo.new(EntranceTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5)
		})
	end
	-- Shown means lane admission, not entrance completion. The payload contains only primitives,
	-- so a shallow copy lets listeners inspect it without changing the entry's rendering options.
	self.Shown:Fire(Entry.Id, table.clone(Payload))
end

function NotificationClient:_Step(Delta)
	-- One Heartbeat advances every entry. Absolute deadlines handle delays and transitions;
	-- frame Delta handles reading time because a paused countdown must not consume elapsed time.
	local Now = os.clock()
	local Occupied = {Upper = 0, Lower = 0}
	-- Resolve exits before admitting queued cards so a slot can be reused on the frame it is freed.
	for _, Entry in self.Entries do
		if Entry.State == "Entering" and Now >= Entry.TransitionAt then
			Entry.State = "Visible"
			-- Duration measures reading time, excluding entrance animation and queue delay.
			Entry.Remaining = Entry.Payload.Duration
		elseif Entry.State == "Visible" and Entry.Payload.Duration > 0 then
			-- Zero-duration entries skip this branch and persist until explicitly dismissed or cleared.
			if not (Entry.Payload.PauseOnHover and Entry.Hovered) then
				Entry.Remaining = math.max(0, Entry.Remaining - Delta)
			end
			-- Scale both width terms by the same fraction to shrink the original width (100% - 28px)
			-- toward zero without leaving a negative pixel offset at the end of the countdown.
			local Fraction = Entry.Remaining / Entry.Payload.Duration
			Entry.Progress.Size = UDim2.new(Fraction, -28 * Fraction, 0, 2)
			if Entry.Remaining <= 0 then
				self:Dismiss(Entry.Id, "Expired")
			end
		elseif Entry.State == "Closing" and Now >= Entry.TransitionAt then
			self:_Finish(Entry, Entry.Reason)
		end
		-- Entering and closing cards still occupy physical space; finished entries no longer do.
		if self.Entries[Entry.Id] and Entry.State ~= "Queued" then
			Occupied[Entry.Payload.Position] += 1
		end
	end

	-- Only advance Index when retaining an entry: table.remove shifts the next item into its place.
	local Index = 1
	while Index <= #self.Queue do
		local Entry = self.Queue[Index]
		local Position = Entry.Payload.Position
		-- Reserve 116px, the tallest current style, plus spacing per slot so mixed styles fit.
		-- Adding one Gap accounts for there being one fewer gap than cards; clamp to 1..MaxVisible.
		local Capacity = math.clamp(math.floor((self.Areas[Position].AbsoluteSize.Y + Gap) / (116 + Gap)), 1, Validation.MaxVisible)
		if not self.Entries[Entry.Id] then
			-- Dismissing queued work removes registry ownership; discard its leftover queue reference.
			table.remove(self.Queue, Index)
		elseif Now >= Entry.ReadyAt and Occupied[Position] < Capacity then
			table.remove(self.Queue, Index)
			self:_Show(Entry)
			-- Reserve immediately so later entries in this same pass cannot overfill the lane.
			Occupied[Position] += 1
		else
			-- A delayed card does not block ready cards, and each lane advances independently.
			Index += 1
		end
	end
end

function NotificationClient:KnitInit()
	-- Build state and listeners during initialization, before KnitStart announces readiness.
	-- Entry connections live on each card; self.Connections owns controller-wide subscriptions.
	self.Entries = {}
	self.Queue = {}
	self.Count = 0
	self.Sequence = 0
	self.Shown = Signal.new()
	self.Closed = Signal.new()
	self.Connections = {}
	self.Templates = System:WaitForChild("NotificationStyles")
	self.Service = Knit.GetService("NotificationService")

	-- Keep templates in replicated storage and render a private clone in this player's PlayerGui.
	-- Disabling respawn reset lets active notifications outlive character replacement.
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = System:WaitForChild("NotificationGUI"):Clone()
	self.Gui.ResetOnSpawn = false
	self.Gui.Parent = PlayerGui
	self.Areas = {
		Upper = self.Gui.UpperNotificationArea,
		Lower = self.Gui.LowerNotificationArea
	}

	-- Each lane uses half the available screen height and grows inward from its nearest edge.
	-- Relative width with pixel margins adapts to narrow screens without filling wide desktops.
	for Position, Area in self.Areas do
		Area.AnchorPoint = Vector2.new(0.5, if Position == "Upper" then 0 else 1)
		Area.Position = if Position == "Upper" then UDim2.new(0.5, 0, 0, 14) else UDim2.new(0.5, 0, 1, -14)
		Area.Size = UDim2.new(1, -24, 0.5, -24)
		Area.Visible = true
		-- Interactable is inherited: a disabled lane suppresses every descendant close button.
		Area.Interactable = true

		-- Cap width for readability while leaving height governed by the responsive lane sizing.
		local Constraint = Instance.new("UISizeConstraint")
		Constraint.MaxSize = Vector2.new(520, 10000)
		Constraint.Parent = Area

		-- UIListLayout stacks reserved slots by arrival sequence, independently of card animation.
		-- Aligning to the lane's outer edge keeps short stacks anchored at the top or bottom.
		local Layout = Instance.new("UIListLayout")
		Layout.Padding = UDim.new(0, Gap)
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		Layout.VerticalAlignment = if Position == "Upper" then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
		Layout.Parent = Area
	end

	-- Server delivery uses the same validation and queue path as local callers. Keep the remote
	-- ID outside Normalize's payload copy so subsequent server dismissals find the correct entry.
	table.insert(self.Connections, self.Service.AnimateNotification:Connect(function(Payload)
		if type(Payload) == "table" then
			self:Notify(Payload, Payload.Id)
		end
	end))
	-- Route server dismiss and clear commands through the public methods to share cleanup rules.
	table.insert(self.Connections, self.Service.DismissNotification:Connect(function(Id)
		self:Dismiss(Id)
	end))
	table.insert(self.Connections, self.Service.ClearNotifications:Connect(function()
		self:Clear()
	end))
	-- A single update connection avoids a separate waiting task or timer for every notification.
	table.insert(self.Connections, RunService.Heartbeat:Connect(function(Delta)
		self:_Step(Delta)
	end))
end

function NotificationClient:Destroy()
	-- Explicit teardown supports test isolation and future screen/controller replacement.
	-- Clear first while lifecycle signals still exist, then stop updates and release shared UI.
	self:Clear()
	for _, Connection in self.Connections do
		Connection:Disconnect()
	end
	self.Shown:Destroy()
	self.Closed:Destroy()
	self.Gui:Destroy()
end

function NotificationClient:KnitStart()
	-- All UI and listeners now exist, so the server can safely flush its buffered join-time messages.
	self.Service.Ready:Fire()
	print("[Knit]: Notification Client started.")
end

-- Return the registered controller so requiring this ModuleScript also exposes its public API.
return NotificationClient
