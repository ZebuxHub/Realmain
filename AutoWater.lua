--[[
    💧 Plant Vs Brainrot - Auto Water Module
    Automatically water seeds with selected bucket
    
    Features:
    - Select water bucket type
    - Auto-equip bucket to character
    - Water all owned seeds
    - Event-driven detection
]]

local AutoWater = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalWatered = 0,
    
    -- Settings
    Settings = {
        AutoWaterEnabled = false,
        SelectedBuckets = {}, -- Array of selected buckets for multi-select
        WateringDelay = 0.05, -- Delay between watering each seed (in seconds)
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Data
    UseItemRemote = nil,
    CurrentBucket = nil,
    
    -- Event Connections
    SeedAddedConnection = nil,
    WateringLoopRunning = false,
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoWater.Init(services, references, brain)
    AutoWater.Services = services
    AutoWater.References = references
    AutoWater.Brain = brain
    
    -- Cache remote
    pcall(function()
        AutoWater.UseItemRemote = AutoWater.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("UseItem", 5)
    end)
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Get list of available water buckets
function AutoWater.GetBucketList()
    return {
        "Water Bucket",
        "Premium Water Bucket"
    }
end

-- Find the bucket tool in backpack or character
function AutoWater.FindBucket(bucketName)
    local player = AutoWater.References.LocalPlayer
    local character = player.Character
    local backpack = player:FindFirstChild("Backpack")
    
    -- Check character first
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and child.Name:find(bucketName, 1, true) then
                return child
            end
        end
    end
    
    -- Check backpack
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") and child.Name:find(bucketName, 1, true) then
                return child
            end
        end
    end
    
    return nil
end

-- Equip bucket to character
function AutoWater.EquipBucket(bucketTool)
    if not bucketTool then return false end
    
    local character = AutoWater.References.LocalPlayer.Character
    if not character then return false end
    
    -- If already equipped, we're good
    if bucketTool.Parent == character then
        AutoWater.CurrentBucket = bucketTool
        return true
    end
    
    -- Try to equip it
    local success = pcall(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(bucketTool)
        end
    end)
    
    task.wait(0.2) -- Wait for equip
    
    -- Verify equipped
    if bucketTool.Parent == character then
        AutoWater.CurrentBucket = bucketTool
        return true
    end
    
    return false
end

-- Get all seeds owned by player
function AutoWater.GetOwnedSeeds()
    local player = AutoWater.References.LocalPlayer
    local username = player.Name
    local seeds = {}
    
    -- Find all seeds in workspace
    local countdowns = workspace:FindFirstChild("ScriptedMap")
    if not countdowns then return seeds end
    
    countdowns = countdowns:FindFirstChild("Countdowns")
    if not countdowns then return seeds end
    
    -- Filter seeds by owner
    for _, seed in ipairs(countdowns:GetChildren()) do
        if seed:IsA("Model") or seed:IsA("Part") then
            local owner = seed:GetAttribute("Owner")
            local cframe = seed:GetAttribute("CFrame")
            
            -- Check if this seed belongs to player and has position
            if owner == username and cframe then
                table.insert(seeds, {
                    Model = seed,
                    Position = cframe.Position,
                    Name = seed.Name
                })
            end
        end
    end
    
    return seeds
end

-- Water a single seed
function AutoWater.WaterSeed(seedData)
    if not AutoWater.UseItemRemote then return false end
    if not AutoWater.CurrentBucket then return false end
    
    local success = pcall(function()
        local args = {
            [1] = {
                ["Toggle"] = true,
                ["Tool"] = AutoWater.CurrentBucket,
                ["Pos"] = seedData.Position
            }
        }
        
        AutoWater.UseItemRemote:FireServer(unpack(args))
        AutoWater.TotalWatered = AutoWater.TotalWatered + 1
    end)
    
    return success
end

-- Water all owned seeds with all selected buckets (single pass)
function AutoWater.WaterAllSeeds()
    if not AutoWater.IsRunning or not AutoWater.Settings.AutoWaterEnabled then
        return 0
    end
    
    -- Check if any buckets are selected
    if not AutoWater.Settings.SelectedBuckets or #AutoWater.Settings.SelectedBuckets == 0 then
        return 0
    end
    
    -- Get all owned seeds
    local seeds = AutoWater.GetOwnedSeeds()
    
    if #seeds == 0 then
        return 0
    end
    
    local totalWatered = 0
    
    -- Try each selected bucket
    for _, bucketName in ipairs(AutoWater.Settings.SelectedBuckets) do
        if not AutoWater.IsRunning then break end
        
        local bucket = AutoWater.FindBucket(bucketName)
        
        if bucket then
            -- Equip bucket if not already equipped
            if AutoWater.CurrentBucket ~= bucket then
                local equipped = AutoWater.EquipBucket(bucket)
                if equipped then
                    -- Water each seed with this bucket
                    for _, seedData in ipairs(seeds) do
                        if not AutoWater.IsRunning then break end
                        
                        if AutoWater.WaterSeed(seedData) then
                            totalWatered = totalWatered + 1
                        end
                        
                        task.wait(AutoWater.Settings.WateringDelay)
                    end
                end
            else
                -- Already equipped, just water
                for _, seedData in ipairs(seeds) do
                    if not AutoWater.IsRunning then break end
                    
                    if AutoWater.WaterSeed(seedData) then
                        totalWatered = totalWatered + 1
                    end
                    
                    task.wait(AutoWater.Settings.WateringDelay)
                end
            end
        end
    end
    
    return totalWatered
end

-- Setup event listener for new seeds (event-driven, no continuous loop)
function AutoWater.SetupEventListeners()
    local countdowns = workspace:FindFirstChild("ScriptedMap")
    if not countdowns then return end
    
    countdowns = countdowns:FindFirstChild("Countdowns")
    if not countdowns then return end
    
    -- Listen for new seeds added (water immediately on detection)
    if not AutoWater.SeedAddedConnection then
        AutoWater.SeedAddedConnection = countdowns.ChildAdded:Connect(function(child)
            if not AutoWater.IsRunning then return end
            
            task.wait(0.2) -- Wait for attributes to replicate
            
            local owner = child:GetAttribute("Owner")
            local username = AutoWater.References.LocalPlayer.Name
            
            -- Check if this seed belongs to us
            if owner == username then
                -- Water immediately
                task.spawn(function()
                    AutoWater.WaterAllSeeds()
                end)
            end
        end)
    end
end

-- Cleanup event listeners
function AutoWater.CleanupEventListeners()
    if AutoWater.SeedAddedConnection then
        AutoWater.SeedAddedConnection:Disconnect()
        AutoWater.SeedAddedConnection = nil
    end
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoWater.Start()
    if AutoWater.IsRunning then return false end
    
    -- Validate remote
    if not AutoWater.UseItemRemote then
        pcall(function()
            AutoWater.UseItemRemote = AutoWater.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("UseItem", 5)
        end)
        
        if not AutoWater.UseItemRemote then
            return false
        end
    end
    
    -- Validate bucket selection
    if not AutoWater.Settings.SelectedBuckets or #AutoWater.Settings.SelectedBuckets == 0 then
        return false
    end
    
    AutoWater.IsRunning = true
    AutoWater.TotalWatered = 0
    
    -- Setup event listeners (event-driven, no continuous loop)
    AutoWater.SetupEventListeners()
    
    -- Water immediately on start
    task.spawn(function()
        AutoWater.WaterAllSeeds()
    end)
    
    return true
end

function AutoWater.Stop()
    if not AutoWater.IsRunning then return false end
    
    AutoWater.IsRunning = false
    AutoWater.CurrentBucket = nil
    
    -- Cleanup event listeners
    AutoWater.CleanupEventListeners()
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoWater.GetStatus()
    return {
        IsRunning = AutoWater.IsRunning,
        TotalWatered = AutoWater.TotalWatered,
        SelectedBucket = AutoWater.Settings.SelectedBucket
    }
end

return AutoWater

