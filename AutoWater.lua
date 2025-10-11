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
        SelectedBucket = "Water Bucket", -- Default bucket
        WateringInterval = 3, -- Water every 3 seconds
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

-- Water all owned seeds (single pass)
function AutoWater.WaterAllSeeds()
    if not AutoWater.IsRunning or not AutoWater.Settings.AutoWaterEnabled then
        return
    end
    
    -- Find the bucket
    local bucket = AutoWater.FindBucket(AutoWater.Settings.SelectedBucket)
    
    if not bucket then
        print("[AutoWater] ⚠️ Bucket not found:", AutoWater.Settings.SelectedBucket)
        return
    end
    
    -- Equip bucket if not already equipped
    if AutoWater.CurrentBucket ~= bucket then
        local equipped = AutoWater.EquipBucket(bucket)
        if not equipped then
            warn("[AutoWater] ⚠️ Failed to equip bucket!")
            return
        end
        print("[AutoWater] 💧 Bucket equipped:", bucket.Name)
    end
    
    -- Get all owned seeds
    local seeds = AutoWater.GetOwnedSeeds()
    
    if #seeds == 0 then
        return 0
    end
    
    -- Water each seed
    local wateredCount = 0
    for i, seedData in ipairs(seeds) do
        if not AutoWater.IsRunning then break end
        
        local success = AutoWater.WaterSeed(seedData)
        
        if success then
            wateredCount = wateredCount + 1
        end
        
        task.wait(0.1) -- Small delay between watering
    end
    
    return wateredCount
end

-- Continuous watering loop
function AutoWater.StartWateringLoop()
    if AutoWater.WateringLoopRunning then return end
    
    AutoWater.WateringLoopRunning = true
    
    task.spawn(function()
        print("[AutoWater] 🔄 Continuous watering started")
        
        while AutoWater.IsRunning and AutoWater.Settings.AutoWaterEnabled do
            -- Get all owned seeds
            local seeds = AutoWater.GetOwnedSeeds()
            
            if #seeds > 0 then
                print(string.format("[AutoWater] 💧 Watering %d seeds...", #seeds))
                local wateredCount = AutoWater.WaterAllSeeds()
                
                if wateredCount > 0 then
                    print(string.format("[AutoWater] ✅ Watered %d seeds | Total: %d", wateredCount, AutoWater.TotalWatered))
                end
            end
            
            -- Wait before next watering cycle
            task.wait(AutoWater.Settings.WateringInterval)
        end
        
        AutoWater.WateringLoopRunning = false
        print("[AutoWater] 🔄 Continuous watering stopped")
    end)
end

-- Stop watering loop
function AutoWater.StopWateringLoop()
    AutoWater.WateringLoopRunning = false
end

-- Setup event listener for new seeds
function AutoWater.SetupEventListeners()
    local countdowns = workspace:FindFirstChild("ScriptedMap")
    if not countdowns then return end
    
    countdowns = countdowns:FindFirstChild("Countdowns")
    if not countdowns then return end
    
    -- Listen for new seeds added (immediate water, then loop handles rest)
    if not AutoWater.SeedAddedConnection then
        AutoWater.SeedAddedConnection = countdowns.ChildAdded:Connect(function(child)
            if not AutoWater.IsRunning then return end
            
            task.wait(0.2) -- Wait for attributes to replicate
            
            local owner = child:GetAttribute("Owner")
            local username = AutoWater.References.LocalPlayer.Name
            
            -- Check if this seed belongs to us
            if owner == username then
                print("[AutoWater] 📥 New seed detected:", child.Name)
                -- Immediate water, continuous loop will handle the rest
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
            warn("[AutoWater] ⚠️ Failed to find UseItem remote!")
            return false
        end
    end
    
    -- Validate bucket selection
    if not AutoWater.Settings.SelectedBucket or AutoWater.Settings.SelectedBucket == "" then
        warn("[AutoWater] ⚠️ No bucket selected!")
        return false
    end
    
    AutoWater.IsRunning = true
    AutoWater.TotalWatered = 0
    
    -- Setup event listeners
    AutoWater.SetupEventListeners()
    
    print("[AutoWater] ▶️ Auto Water started with:", AutoWater.Settings.SelectedBucket)
    print(string.format("[AutoWater] 🔄 Will water every %d seconds until seeds grow", AutoWater.Settings.WateringInterval))
    
    -- Start continuous watering loop
    AutoWater.StartWateringLoop()
    
    return true
end

function AutoWater.Stop()
    if not AutoWater.IsRunning then return false end
    
    AutoWater.IsRunning = false
    AutoWater.CurrentBucket = nil
    
    -- Stop watering loop
    AutoWater.StopWateringLoop()
    
    -- Cleanup event listeners
    AutoWater.CleanupEventListeners()
    
    print("[AutoWater] ⏹️ Auto Water stopped")
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

