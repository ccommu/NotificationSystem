local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Validation = require(ReplicatedStorage.NotificationSystem.Validation)

local NotificationShowcaseClient = Knit.CreateController({
	Name = "NotificationShowcaseClient"
})

function NotificationShowcaseClient:_Run()
	local Player = Players.LocalPlayer
	local Controller = Knit.GetController("NotificationClient")
	local Count = 0
	local function Check(Condition, Message)
		assert(Condition, "[NotificationTests] " .. Message)
		Count += 1
	end
	local function Until(Predicate, Timeout, Message)
		local Deadline = os.clock() + Timeout
		repeat
			if Predicate() then
				return
			end
			task.wait(0.03)
		until os.clock() >= Deadline
		error("[NotificationTests] Timed out: " .. Message)
	end
	local function Visible(Id)
		Until(function()
			return Controller:GetState().Entries[Id] and Controller:GetState().Entries[Id].State == "Visible"
		end, 5, "card visible")
		return Controller.Entries[Id]
	end
	local function Gone(Id)
		Until(function()
			return Controller:GetState().Entries[Id] == nil
		end, 5, "card cleanup")
	end

	-- Server and client suites run in succession so their queue and cleanup assertions are isolated.
	Until(function()
		return Player:GetAttribute("NotificationShowcaseServerStatus") == "Passed"
			or Player:GetAttribute("NotificationShowcaseServerStatus") == "Failed"
	end, 100, "server showcase")
	Check(Player:GetAttribute("NotificationShowcaseServerStatus") == "Passed", "Server showcase passed")
	Player:SetAttribute("NotificationShowcaseClientStatus", "Running")
	Controller:Clear()
	Check(Controller.Gui.AbsoluteSize.Y > 150, "GUI uses the playable screen instead of the top bar")
	Check(Controller.Areas.Upper.Interactable and Controller.Areas.Lower.Interactable, "Lane containers allow close-button input")

	local Id = assert(Controller:Notify({
		Title = "11 / Hover pause",
		Description = "Hover or gamepad focus pauses the reading timer.",
		Style = "modern",
		Duration = 1,
		PauseOnHover = true
	}))
	local Entry = Visible(Id)
	Controller:_SetHovered(Entry, true)
	local Before = Entry.Remaining
	task.wait(0.4)
	Check(math.abs(Entry.Remaining - Before) < 0.05, "Hover pauses expiry")
	Controller:_SetHovered(Entry, false)
	Gone(Id)
	Check(Entry.Slot.Parent == nil and #Controller.Queue == 0, "Expiry destroys the card")

	Id = assert(Controller:Notify({Title = "12 / Local notification", Description = "No server round trip is needed.", Delay = 0.6, Duration = 0, Dismissible = false}))
	task.wait(0.2)
	Check(Controller:GetState().Entries[Id].State == "Queued", "Delay respected")
	Entry = Visible(Id)
	Check(not Entry.Card.Dismiss.Visible and not Entry.Progress.Visible, "Persistent and non-dismissible controls")
	task.wait(0.3)
	Check(Controller:GetState().Entries[Id] ~= nil, "Persistent card stays")
	Check(Controller:Dismiss(Id), "Programmatic dismissal")
	Check(not Controller:Dismiss(Id), "Repeated dismissal is harmless")
	Gone(Id)

	-- Concrete template checks cover both image branches and explicit title visibility.
	for _, Style in {"modern", "minimal", "bar"} do
		Id = assert(Controller:Notify({
			Title = "13 / " .. Style .. " layout",
			Description = "Template, image fallback, and title checks.",
			Style = Style,
			Image = "6031075938",
			DisplayTitle = false,
			Duration = 0,
			Position = "Bottom"
		}))
		Entry = Visible(Id)
		local ImageLayout = Entry.Card:FindFirstChild("ImageLayout")
		local Layout = if Style == "bar" then Entry.Card.NoImageLayout else ImageLayout
		Check(Layout.Visible and not Layout.Title.Visible, "Selected layout: " .. Style)
		Check(Style == "bar" or Layout.Image.Image == "rbxassetid://6031075938", "Image path: " .. Style)
		Check(Entry.Slot.Parent == Controller.Areas.Lower, "Lower position alias")
		task.wait(0.5)
		Controller:Dismiss(Id)
		Gone(Id)
	end

	Controller:Clear()
	for Index = 1, Validation.MaxPending do
		assert(Controller:Notify({Title = "Bounded " .. Index, Delay = 30}))
	end
	Check(Controller:Notify({}) == nil, "Queue overflow rejected")
	Check(Controller:GetState().Total == Validation.MaxPending, "Queue remains bounded")
	Controller:Clear()
	Check(Controller:GetState().Total == 0 and #Controller.Queue == 0, "Clear removes delayed work")
	Check(Controller:Notify({Duration = 0 / 0}) == nil, "Client validation")

	local Queued = assert(Controller:Notify({Title = "Canceled delay", Delay = 0.4}))
	Check(Controller:Dismiss(Queued), "Cancel delayed notification")
	task.wait(0.6)
	Check(Controller:GetState().Total == 0, "Canceled delay never resurrects")

	-- Temporarily constrain one lane to a single slot; this proves FIFO independently of screen size.
	local Area = Controller.Areas.Upper
	local OriginalSize = Area.Size
	Area.Size = UDim2.fromOffset(296, 130)
	local First = assert(Controller:Notify({Title = "14 / Queue first", Duration = 0, PauseOnHover = false}))
	local Second = assert(Controller:Notify({Title = "14 / Queue second", Duration = 0, PauseOnHover = false}))
	local Compact = Visible(First)
	Check(Compact.Card.AbsoluteSize.X <= 296, "Card fits a compact phone-width lane")
	Check(Compact.Card.NoImageLayout.Description.AbsoluteSize.X > 100, "Compact text remains readable")
	Check(Controller:GetState().Entries[Second].State == "Queued", "Overflow waits for capacity")
	Controller:Dismiss(First)
	Gone(First)
	Visible(Second)
	Check(Controller:GetState().Visible == 1, "Queue advances after exit")
	Controller:Clear()
	Area.Size = OriginalSize

	Controller.Service.SendNotification:Fire({
		Title = "15 / Client request",
		Description = "The Knit service returns this only to the requesting player.",
		Duration = 0.8,
		PauseOnHover = false
	})
	Until(function()
		for _, Current in Controller.Entries do
			if Current.Payload.Title == "15 / Client request" then
				return true
			end
		end
		return false
	end, 5, "client request round trip")
	Check(true, "Client request round trip")
	Until(function()
		return Controller:GetState().Total == 0
	end, 5, "final cleanup")
	Check(not Controller.Gui.ResetOnSpawn, "GUI survives character respawn")
	Check(#Controller.Queue == 0, "No pending queue residue")

	Player:SetAttribute("NotificationShowcaseClientAssertions", Count)
	Player:SetAttribute("NotificationShowcaseClientStatus", "Passed")
	print("[NotificationTests] Client showcase PASS: " .. Count .. " assertions")
	Controller:Notify({
		Title = "Notification showcase complete",
		Description = "Server routing, styles, timers, queues, and cleanup checks passed.",
		Style = "modern",
		Duration = 5,
		PauseOnHover = false
	})
end

function NotificationShowcaseClient:KnitStart()
	-- Each client owns one sequential test coroutine; failure is visible in Output and attributes.
	task.spawn(function()
		local Success, Message = xpcall(function()
			self:_Run()
		end, debug.traceback)
		if not Success then
			Players.LocalPlayer:SetAttribute("NotificationShowcaseClientStatus", "Failed")
			warn("[NotificationTests] Client showcase FAIL: " .. tostring(Message))
		end
	end)
end

return NotificationShowcaseClient
