local Types = {}

export type NotificationStyle = "modern" | "minimal" | "bar"
export type NotificationPositions = "Upper" | "Lower" | "Top" | "Bottom"

-- All fields are optional: shared style defaults fill gaps before a notification is delivered.
export type Notification = {
	Title: string?,
	Description: string?,
	Style: NotificationStyle?,
	Duration: number?, -- Zero is persistent; positive values begin after the entrance animation.
	Delay: number?,
	Image: (string | number)?,
	Position: NotificationPositions?,
	DisplayTitle: boolean?,
	Dismissible: boolean?,
	PauseOnHover: boolean?,
	ShowProgress: boolean?
}

return Types
