local Styles = require(script.Parent.Notifications)

local Validation = {}

-- Limits bound remote traffic, delayed work, and the amount of text a card must lay out.
Validation.MaxPending = 32
Validation.MaxVisible = 3
Validation.MaxDuration = 120
Validation.MaxDelay = 60

local Positions = {
	upper = "Upper",
	top = "Upper",
	lower = "Lower",
	bottom = "Lower"
}

local function IsFinite(Value)
	return type(Value) == "number" and Value == Value and math.abs(Value) < math.huge
end

local function IsText(Value, Limit)
	return type(Value) == "string" and #Value <= Limit and utf8.len(Value) ~= nil
end

function Validation.Normalize(notif)
	if type(notif) ~= "table" then
		return nil, "Notification must be a table."
	end

	local Style = notif.Style or "minimal"
	if type(Style) ~= "string" or not Styles[string.lower(Style)] then
		return nil, "Unknown notification style."
	end

	Style = string.lower(Style)
	local Information = Styles[Style]
	local Title = if notif.Title == nil then "Notification" else notif.Title
	local Description = if notif.Description == nil then "" else notif.Description

	if not IsText(Title, 120) or not IsText(Description, 1200) then
		return nil, "Title or description is invalid or too long."
	end

	local Position = notif.Position or Information.DefaultPosition
	if type(Position) ~= "string" or not Positions[string.lower(Position)] then
		return nil, "Position must be Upper, Lower, Top, or Bottom."
	end

	local Duration = if notif.Duration == nil then Information.DefaultDuration else notif.Duration
	local Delay = if notif.Delay == nil then Information.DefaultDelay else notif.Delay
	if not IsFinite(Duration) or Duration < 0 or Duration > Validation.MaxDuration then
		return nil, "Duration must be between 0 and 120; 0 stays until dismissed."
	end
	if not IsFinite(Delay) or Delay < 0 or Delay > Validation.MaxDelay then
		return nil, "Delay must be between 0 and 60."
	end

	for _, Key in {"DisplayTitle", "Dismissible", "PauseOnHover", "ShowProgress"} do
		if notif[Key] ~= nil and type(notif[Key]) ~= "boolean" then
			return nil, Key .. " must be a boolean."
		end
	end

	-- Only asset IDs cross the wire. Unsupported bar images deliberately use the text layout.
	local Image
	if notif.Image ~= nil then
		local Value = notif.Image
		if type(Value) == "number" then
			if not IsFinite(Value) or Value <= 0 or Value % 1 ~= 0 then
				return nil, "Image must be a positive asset ID."
			end
			Value = string.format("%.0f", Value)
		end
		if type(Value) ~= "string" or #Value > 100 then
			return nil, "Image must be an asset ID."
		end
		local AssetId = string.match(Value, "^rbxassetid://(%d+)$") or string.match(Value, "^(%d+)$")
		if not AssetId or not tonumber(AssetId) or tonumber(AssetId) <= 0 then
			return nil, "Image must be an asset ID."
		end
		if Information.HasImageSupport then
			Image = "rbxassetid://" .. AssetId
		end
	end

	-- A fresh allowlisted table prevents caller mutations and removes arbitrary nested data.
	return {
		Title = Title,
		Description = Description,
		Style = Style,
		Position = Positions[string.lower(Position)],
		Duration = Duration,
		Delay = Delay,
		Image = Image,
		DisplayTitle = if notif.DisplayTitle == nil then Information.TitledDisplayedDefault else notif.DisplayTitle,
		Dismissible = notif.Dismissible ~= false,
		PauseOnHover = notif.PauseOnHover ~= false,
		ShowProgress = notif.ShowProgress ~= false
	}
end

return Validation
