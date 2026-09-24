-- This documentation is also exported as the repository README.
return [====[# NotificationSystem

A complete Knit notification service and controller, exported from Roblox Studio through MCP.

## Layout

- `ServerScriptService/Services/NotificationService/`: server routing, validation, readiness buffering, broadcast, dismissal, and clear.
- `ServerScriptService/Services/NotificationShowcaseService.lua`: automatic server showcase for every joining player.
- `ReplicatedStorage/Modules/NotificationClient.lua`: client rendering, animation, bounded queues, timing, and input.
- `ReplicatedStorage/Modules/NotificationShowcaseClient.lua`: sequential client checks after the server showcase.
- `ReplicatedStorage/NotificationSystem/`: shared styles, validation, tests, and authored GUI definitions.
- `ReplicatedStorage/Packages/`: existing Knit and dependency scripts, exported without modification.
- `StarterPlayer/StarterPlayerScripts/KnitRuntimeClient.client.lua`: client startup.

Folders with `init.lua` represent ModuleScripts with children; other `.lua` files represent ModuleScripts. `.server.lua` and `.client.lua` represent Script and LocalScript instances. This preserves the Studio hierarchy, including dependency modules whose names contain dots.

## Install

Use the included `default.project.json` with Rojo, or recreate the folder/script hierarchy in Studio. The server startup calls `AssetDefinitions.Build()` before Knit starts. It reconstructs the three authored UI templates and ScreenGui when they are absent; existing Studio assets take precedence. Do not start Knit a second time.

This export contains scripts and the notification GUI definitions. It does not include the place's map, character assets, or Studio plugin internals.

## Server API

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local Notifications = Knit.GetService("NotificationService")

local Id, Error = Notifications:Notify(Player, {
	Title = "Saved",
	Description = "Your changes were saved.",
	Style = "modern",
	Image = 6031075938,
	Duration = 5,
	Position = "Upper"
})

Notifications:Dismiss(Player, Id)
Notifications:Clear(Player)

local IdsByPlayer, BroadcastError = Notifications:SendServerWideNotification({
	Title = "Announcement",
	Description = "A new round begins shortly.",
	Style = "bar"
})
```

Call service APIs after Knit initialization. `Notify` returns an ID or `nil, error`; broadcasts return a player-to-ID map. An ID confirms admission to the server delivery/startup queue, not that the client rendered it. Client overload rejects new notifications once its 32-entry limit is reached. Broadcasts target the current server, not other live servers.

## Client API

```lua
local Controller = Knit.GetController("NotificationClient")
local Id, Error = Controller:Notify({
	Title = "Local notice",
	Description = "Rendered without a network round trip.",
	Duration = 3
})

Controller:Dismiss(Id)
Controller:Clear()

Controller.Shown:Connect(function(Id, Payload)
	-- The card has entered a visible lane.
end)

Controller.Closed:Connect(function(Id, Reason)
	-- Reason is Expired, Dismissed, or Cleared.
end)
```

`GetState()` returns a diagnostic snapshot. `Destroy()` tears down the controller's connections, signals, and GUI. The existing `NotificationService.SendNotification` remote remains available for self-only client requests, limited to a six-request burst and two requests per second refill. Clients cannot broadcast or choose another recipient.

## Options

All fields are optional.

| Field | Behavior |
| --- | --- |
| Style | `minimal` (default), `modern`, or `bar`; case insensitive |
| Title | Default `Notification`; maximum 120 UTF-8 bytes |
| Description | Default empty string; maximum 1200 UTF-8 bytes |
| Position | `Upper` / `Lower`; accepts `Top` / `Bottom` aliases |
| Duration | 0–120 seconds; 0 persists until dismissed; defaults: minimal 8, modern 10, bar 3 |
| Delay | 0–60 seconds before becoming eligible for a lane |
| Image | Positive numeric ID, numeric string, or `rbxassetid://` ID; modern/minimal support images, bar falls back to text |
| DisplayTitle | Defaults true for modern/minimal, false for bar |
| Dismissible | Default true; controls the mouse, touch, and gamepad close button |
| PauseOnHover | Default true; mouse hover or close-button gamepad focus pauses the reading timer |
| ShowProgress | Default true; hidden automatically for persistent cards |

Notifications are plain text; RichText is disabled. Long descriptions wrap and truncate within the card. Callers should filter user-authored text before displaying it to other players.

## Lifecycle

The client connects Knit signal listeners before announcing readiness. The server buffers up to 32 early notifications per player. Payloads contain validated primitives; GUI Instances never cross a remote.

Each client admits up to 32 total notifications, including delayed, visible, and closing entries. Upper and lower lanes have independent FIFO admission, with one to three visible slots each according to available height. Delayed entries do not block already-ready entries. Reading time begins after entrance animation; closing cards retain their slot until their exit completes.

One Heartbeat connection drives all timers and queue admission. Completed cards release tweens, UI instances, and per-card connections. Clear also removes delayed entries. Server state is removed when players leave. The ScreenGui uses playable-screen insets and survives character respawn.

## Automatic showcase and verification

Every joining player runs the server demonstration followed by the client assertion sequence. It is intentionally enabled outside Studio too, as requested. No username or character-spawn dependency is used.

The sequence covers all three styles, image and no-image layouts, title visibility, position aliases, delays, persistent notifications, server dismissal, broadcast, FIFO stacking, clear, local notifications, hover pause, overflow rejection, canceled delays, client request round trips, and cleanup.

The suites report to Output and these player attributes:

- `NotificationShowcaseServerStatus`: Running / Passed / Failed.
- `NotificationShowcaseClientStatus`: Running / Passed / Failed (client-local).
- `NotificationShowcaseClientAssertions`: client assertion count.

Verified in Studio: 41 shared validation assertions, the server showcase including request throttling, and 32 client assertions. Additional MCP interaction checks verified a real close-button Activated event, character-respawn survival, visual layout for all three styles, and clean/idempotent GUI reconstruction. Multi-player network testing and physical touch/gamepad devices were not available in this single-client session.

To retire the demonstration later, remove the two showcase modules from their Knit registration folders. Core notification functionality is independent of them.
]====]
