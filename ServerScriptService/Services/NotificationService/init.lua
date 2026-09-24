local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Types = require(ReplicatedStorage.Types)
local Validation = require(ReplicatedStorage.NotificationSystem.Validation)

local NotificationService = Knit.CreateService {
	Name = "NotificationService",
	Client = {
		SendNotification = Knit.CreateSignal(),
		AnimateNotification = Knit.CreateSignal(),
		DismissNotification = Knit.CreateSignal(),
		ClearNotifications = Knit.CreateSignal(),
		Ready = Knit.CreateSignal()
	}
}

type Notification = Types.Notification

local function IsPlayer(Player)
	return typeof(Player) == "Instance" and Player:IsA("Player") and Player.Parent == Players
end

function NotificationService:IsReady(Player : Player)
	return self.ReadyPlayers[Player] == true
end

function NotificationService:Notify(Player : Player, notif : Notification)
	if not IsPlayer(Player) then
		return nil, "Player is no longer connected."
	end

	local Payload, Message = Validation.Normalize(notif)
	if not Payload then
		return nil, Message
	end

	Payload.Id = HttpService:GenerateGUID(false)
	if self:IsReady(Player) then
		self.Client.AnimateNotification:Fire(Player, Payload)
	else
		-- Joining clients announce readiness only after connecting their listeners.
		-- This bounded FIFO preserves early server notifications without a timing-based wait.
		local Pending = self.Pending[Player] or {}
		self.Pending[Player] = Pending
		if #Pending >= Validation.MaxPending then
			return nil, "The player's startup notification queue is full."
		end
		table.insert(Pending, Payload)
	end

	return Payload.Id
end

function NotificationService:SendServerWideNotification(notif : Notification)
	local Payload, Message = Validation.Normalize(notif)
	if not Payload then
		return nil, Message
	end

	local Sent = {}
	for _, Player in Players:GetPlayers() do
		local Id = self:Notify(Player, Payload)
		if Id then
			Sent[Player] = Id
		end
	end
	return Sent
end

function NotificationService:Dismiss(Player : Player, Id : string)
	if not IsPlayer(Player) or type(Id) ~= "string" then
		return false
	end

	local Pending = self.Pending[Player]
	if Pending then
		for Index = #Pending, 1, -1 do
			if Pending[Index].Id == Id then
				table.remove(Pending, Index)
				return true
			end
		end
	end

	if self:IsReady(Player) then
		self.Client.DismissNotification:Fire(Player, Id)
	end
	return true
end

function NotificationService:Clear(Player : Player)
	if not IsPlayer(Player) then
		return false
	end

	self.Pending[Player] = nil
	if self:IsReady(Player) then
		self.Client.ClearNotifications:Fire(Player)
	end
	return true
end

function NotificationService:_AcceptRequest(Player : Player)
	-- Client requests can target only their sender. A token bucket permits short bursts
	-- while preventing repeated remote calls from growing queues or broadcasting to others.
	local Now = os.clock()
	local Bucket = self.RequestBuckets[Player] or {Tokens = 6, Updated = Now}
	self.RequestBuckets[Player] = Bucket
	Bucket.Tokens = math.min(6, Bucket.Tokens + (Now - Bucket.Updated) * 2)
	Bucket.Updated = Now
	if Bucket.Tokens < 1 then
		return false
	end
	Bucket.Tokens -= 1
	return true
end

function NotificationService:KnitInit()
	self.Pending = {}
	self.ReadyPlayers = {}
	self.RequestBuckets = {}
	self.PlayerReady = Signal.new()

	self.Client.Ready:Connect(function(Player : Player)
		if not IsPlayer(Player) or self:IsReady(Player) then
			return
		end

		self.ReadyPlayers[Player] = true
		local Pending = self.Pending[Player]
		self.Pending[Player] = nil
		for _, Payload in Pending or {} do
			self.Client.AnimateNotification:Fire(Player, Payload)
		end
		self.PlayerReady:Fire(Player)
	end)

	self.Client.SendNotification:Connect(function(Player : Player, notif : Notification)
		if self:IsReady(Player) and self:_AcceptRequest(Player) then
			self:Notify(Player, notif)
		end
	end)

	Players.PlayerRemoving:Connect(function(Player : Player)
		self.Pending[Player] = nil
		self.ReadyPlayers[Player] = nil
		self.RequestBuckets[Player] = nil
	end)
end

function NotificationService:KnitStart()
	print("[Knit]: Notification Service started.")
end

return NotificationService
