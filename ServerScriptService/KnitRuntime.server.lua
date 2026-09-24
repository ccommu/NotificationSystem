local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Restore GUI templates for a script-only installation before services become available.
require(ReplicatedStorage.NotificationSystem.AssetDefinitions).Build()

-- Service children hold configuration, so only top-level service modules are registered.
Knit.AddServices(script.Parent.Services)
Knit.Start():catch(warn)
