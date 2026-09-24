-- Style data is shared by validation and rendering; Instances stay out of remote payloads.
local Notifications = {
	["bar"] = {
		SpringIn = true,
		SpringOut = true,
		DefaultDelay = 0,
		TitledDisplayedDefault = false,
		DefaultDuration = 3,
		DefaultPosition = "Lower",
		HasImageSupport = false,
		Template = "BarNotification",
		Height = 72
	},
	["modern"] = {
		SpringIn = true,
		SpringOut = false,
		DefaultDelay = 0,
		TitledDisplayedDefault = true,
		DefaultDuration = 10,
		DefaultPosition = "Upper",
		HasImageSupport = true,
		Template = "ModernNotification",
		Height = 116
	},
	["minimal"] = {
		SpringIn = false,
		SpringOut = false,
		DefaultDelay = 0,
		TitledDisplayedDefault = true,
		DefaultDuration = 8,
		DefaultPosition = "Upper",
		HasImageSupport = true,
		Template = "MinimalNotification",
		Height = 106
	}
}

for _, Information in Notifications do
	table.freeze(Information)
end

return table.freeze(Notifications)
