local Validation = require(script.Parent.Validation)
local Styles = require(script.Parent.Notifications)

local Tests = {}

function Tests.RunValidation()
	local Count = 0
	local function Check(Condition, Message)
		assert(Condition, "[NotificationTests] " .. Message)
		Count += 1
	end

	local Default = Validation.Normalize({})
	Check(Default.Style == "minimal" and Default.Duration == 8, "Default style and duration")
	Check(Default.Position == "Upper" and Default.DisplayTitle, "Default placement and title")

	for Style, Information in Styles do
		local Result = Validation.Normalize({Style = string.upper(Style)})
		Check(Result.Style == Style and Result.Duration == Information.DefaultDuration, "Style defaults: " .. Style)
	end
	for Alias, Expected in {Top = "Upper", Bottom = "Lower", Upper = "Upper", Lower = "Lower"} do
		Check(Validation.Normalize({Position = Alias}).Position == Expected, "Position alias: " .. Alias)
	end

	for _, Invalid in {
		false, "bad", 12,
		{Style = "missing"}, {Position = "Middle"}, {Title = false}, {Description = {}},
		{Title = string.rep("x", 121)}, {Description = string.rep("x", 1201)},
		{Duration = -1}, {Duration = 121}, {Duration = math.huge}, {Duration = 0 / 0},
		{Delay = -1}, {Delay = 61}, {Delay = "later"}, {Delay = math.huge},
		{Image = {}}, {Image = "https://example.com"}, {Image = -1}, {Image = 1.5},
		{DisplayTitle = 1}, {Dismissible = "yes"}, {PauseOnHover = {}}, {ShowProgress = "true"}
	} do
		Check(Validation.Normalize(Invalid) == nil, "Invalid payload rejection")
	end
	Check(Validation.Normalize(nil) == nil, "Missing payload rejection")
	Check(Validation.Normalize({Image = 6031075938}).Image == "rbxassetid://6031075938", "Numeric image")
	Check(Validation.Normalize({Image = "rbxassetid://6031075938"}).Image == "rbxassetid://6031075938", "Image URI")
	Check(Validation.Normalize({Style = "bar", Image = "6031075938"}).Image == nil, "Bar image fallback")
	Check(Validation.Normalize({Duration = 0}).Duration == 0, "Persistent duration")
	Check(Validation.Normalize({DisplayTitle = false}).DisplayTitle == false, "Explicit false")
	local Input = {Title = "Original", Extra = {Unsafe = true}}
	local Copy = Validation.Normalize(Input)
	Input.Title = "Changed"
	Check(Copy.Title == "Original" and Copy.Extra == nil, "Allowlist and defensive copy")
	return Count
end

return Tests
