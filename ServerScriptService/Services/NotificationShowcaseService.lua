local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Tests = require(ReplicatedStorage.NotificationSystem.Tests)

local NotificationShowcaseService = Knit.CreateService {
	Name = "NotificationShowcaseService",
	Client = {}
}

function NotificationShowcaseService:_Run(Player : Player)
	if self.Running[Player] then
		return
	end
	self.Running[Player] = true
	Player:SetAttribute("NotificationShowcaseServerStatus", "Running")

	local Success, Message = xpcall(function()
		local Service = self.NotificationService
		assert(Service:Notify(nil, {}) == nil, "Disconnected targets must be rejected.")
		assert(not Service:Clear(nil) and not Service:Dismiss(nil, "missing"))
		-- Exhaust a fresh bucket without yielding, then simulate elapsed time to verify refill.
		Service.RequestBuckets[Player] = {Tokens = 6, Updated = os.clock()}
		for _ = 1, 6 do
			assert(Service:_AcceptRequest(Player), "Request burst rejected too early.")
		end
		assert(not Service:_AcceptRequest(Player), "Request flood was not limited.")
		Service.RequestBuckets[Player].Updated -= 1
		assert(Service:_AcceptRequest(Player), "Request budget did not refill.")
		Service.RequestBuckets[Player] = nil

		local function Wait(Seconds)
			task.wait(Seconds)
			assert(Player.Parent == Players, "Player left during showcase.")
		end
		local function Show(Title, Options)
			Options.Title = Title
			Options.Duration = Options.Duration or 2
			Options.PauseOnHover = false
			local Id, Error = Service:Notify(Player, Options)
			assert(Id, Error)
			Wait(Options.Duration + (Options.Delay or 0) + 0.9)
			return Id
		end

		-- The sequence starts after readiness, rather than relying on a character or username.
		Wait(1)
		Show("1 / Minimal", {Style = "minimal", Description = "Text-only notification with a timed progress bar."})
		Show("2 / Modern", {Style = "modern", Description = "Image support, spring entrance, and smooth exit.", Image = 6031075938})
		Show("3 / Bar", {Style = "bar", Description = "Bottom bar: title hidden by default; spring entrance and exit."})
		Show("4 / Minimal image", {Style = "minimal", Image = "rbxassetid://6031075938", Description = "The minimal image layout is now supported.", Position = "Bottom"})
		Show("5 / Optional title", {Style = "modern", DisplayTitle = false, Description = "A title-free card; its description uses the available height.", Position = "Top", ShowProgress = false})
		Show("6 / Delayed", {Style = "bar", DisplayTitle = true, Delay = 1, Description = "This card waited one second before entering."})

		local Persistent = assert(Service:Notify(Player, {
			Title = "7 / Persistent",
			Description = "Duration zero stays visible. The server will dismiss this card.",
			Duration = 0,
			Dismissible = false
		}))
		Wait(2.5)
		assert(Service:Dismiss(Player, Persistent))
		Wait(0.5)

		-- Broadcast uses the same validation and readiness queues as a single-player send.
		local Recipients = assert(Service:SendServerWideNotification({
			Title = "8 / Server broadcast",
			Description = "Every connected player receives this notification.",
			Style = "modern",
			Duration = 2,
			PauseOnHover = false
		}))
		assert(Recipients[Player], "Joining player missing from broadcast.")
		Wait(3)

		for Index = 1, 5 do
			assert(Service:Notify(Player, {
				Title = "9 / Queue " .. Index,
				Description = "Bounded lanes stack cards and advance the remaining FIFO.",
				Style = "minimal",
				Duration = 1.2,
				PauseOnHover = false
			}))
		end
		Wait(11)
		assert(Service:Notify(Player, {Title = "10 / Clear", Description = "Server clear removes active and delayed cards.", Duration = 0}))
		assert(Service:Notify(Player, {Title = "Must never display", Delay = 20}))
		Wait(1.5)
		assert(Service:Clear(Player))
		Wait(0.5)
		assert(Service:Notify(Player, {Duration = -1}) == nil, "Invalid server payload accepted.")
		assert(Service:SendServerWideNotification({Style = "unknown"}) == nil, "Invalid broadcast accepted.")

		Player:SetAttribute("NotificationShowcaseServerStatus", "Passed")
		print("[NotificationTests] Server showcase PASS for " .. Player.Name)
	end, debug.traceback)

	if not Success and Player.Parent == Players then
		Player:SetAttribute("NotificationShowcaseServerStatus", "Failed")
		warn("[NotificationTests] Server showcase FAIL: " .. tostring(Message))
	end
	self.Running[Player] = nil
end

function NotificationShowcaseService:KnitInit()
	self.Running = {}
end

function NotificationShowcaseService:KnitStart()
	self.NotificationService = Knit.GetService("NotificationService")
	local Count = Tests.RunValidation()
	print("[NotificationTests] Validation PASS: " .. Count .. " assertions")

	-- PlayerReady is idempotent per session. Connect first, then cover players already ready.
	self.NotificationService.PlayerReady:Connect(function(Player)
		task.spawn(function()
			self:_Run(Player)
		end)
	end)
	for _, Player in Players:GetPlayers() do
		if self.NotificationService:IsReady(Player) then
			task.spawn(function()
				self:_Run(Player)
			end)
		else
			-- This early notification explicitly exercises delivery before client readiness.
			self.NotificationService:Notify(Player, {
				Title = "Welcome",
				Description = "The automatic notification showcase begins shortly.",
				Duration = 1,
				PauseOnHover = false
			})
		end
	end
end

return NotificationShowcaseService
