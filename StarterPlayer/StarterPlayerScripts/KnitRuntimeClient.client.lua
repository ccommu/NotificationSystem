local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

-- Controllers connect in KnitInit; their KnitStart hooks announce readiness afterwards.
Knit.AddControllers(ReplicatedStorage:WaitForChild("Modules"))
Knit.Start():catch(warn)
