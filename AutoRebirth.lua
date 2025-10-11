--[[
    🌱 Plant Vs Brainrot - Auto Rebirth Module
    Automatically rebirth when requirements are met
    
    Features:
    - Reads rebirth data from game
    - Checks money + brainrot ownership requirements
    - Efficient interval-based checking
    - Auto-rebirth when ready
]]

local AutoRebirth = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    CurrentRebirth = 0,
    LastCheckTime = 0,
    
    -- Settings
    Settings = {
        AutoRebirthEnabled = false,
        CheckInterval = 5,  -- Check every 5 seconds (performance optimized)
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Data
    RebirthData = nil,
    RebirthRemote = nil,
    FavoriteRemote = nil,
    RemoveItemRemote = nil,
    FavoritedBrainrots = {}  -- Track which brainrots we've favorited
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoRebirth.Init(services, references, brain)
    AutoRebirth.Services = services
    AutoRebirth.References = references
    AutoRebirth.Brain = brain
    
    -- Cache rebirth data once
    AutoRebirth.LoadRebirthData()
    
    -- Cache remotes
    pcall(function()
        local remotes = services.ReplicatedStorage:WaitForChild("Remotes", 5)
        if remotes then
            AutoRebirth.RebirthRemote = remotes:WaitForChild("Rebirth", 5)
            AutoRebirth.FavoriteRemote = remotes:WaitForChild("FavoriteItem", 5)
            AutoRebirth.RemoveItemRemote = remotes:WaitForChild("RemoveItem", 5)
        end
    end)
    
    return true
end

--[[
    ========================================
    Data Loading
    ========================================
]]

-- Load rebirth requirements from game
function AutoRebirth.LoadRebirthData()
    local success = pcall(function()
        local rebirthModule = AutoRebirth.Services.ReplicatedStorage
            :WaitForChild("Modules", 5)
            :WaitForChild("Library", 5)
            :WaitForChild("Rebirths", 5)
        
        if rebirthModule then
            AutoRebirth.RebirthData = require(rebirthModule)
        end
    end)
    
    return success and AutoRebirth.RebirthData ~= nil
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Get current rebirth level
function AutoRebirth.GetCurrentRebirth()
    local success, rebirth = pcall(function()
        return AutoRebirth.References.LocalPlayer:GetAttribute("Rebirth") or 0
    end)
    return success and rebirth or 0
end

-- Get player's current money
function AutoRebirth.GetPlayerMoney()
    local success, money = pcall(function()
        return AutoRebirth.References.LocalPlayer.leaderstats.Money.Value
    end)
    return success and money or 0
end

-- Get owned brainrots in backpack with their IDs
function AutoRebirth.GetOwnedBrainrots()
    local owned = {}
    
    pcall(function()
        local backpack = AutoRebirth.References.LocalPlayer:FindFirstChild("Backpack")
        if not backpack then return end
        
        local plants = AutoRebirth.Services.ReplicatedStorage:FindFirstChild("Assets")
        if plants then
            plants = plants:FindFirstChild("Plants")
        end
        if not plants then return end
        
        -- Check each plant in backpack
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                -- Check if it's a brainrot (exists in Plants folder)
                local plantModel = plants:FindFirstChild(item.Name)
                if plantModel then
                    -- Store both name and the tool instance (for ID)
                    owned[item.Name] = item
                end
            end
        end
    end)
    
    return owned
end

-- Favorite a brainrot to prevent auto-placement
function AutoRebirth.FavoriteBrainrot(brainrotTool)
    if not AutoRebirth.FavoriteRemote or not brainrotTool then return false end
    
    -- Get the unique ID from the tool (usually the Name or a specific attribute)
    local brainrotId = brainrotTool.Name
    
    -- Check if already favorited
    if AutoRebirth.FavoritedBrainrots[brainrotId] then
        return true
    end
    
    local success = pcall(function()
        AutoRebirth.FavoriteRemote:FireServer(brainrotId)
    end)
    
    if success then
        AutoRebirth.FavoritedBrainrots[brainrotId] = true
    end
    
    return success
end

-- Remove favorited brainrot (before rebirth)
function AutoRebirth.RemoveBrainrot(brainrotTool)
    if not AutoRebirth.RemoveItemRemote or not brainrotTool then return false end
    
    local brainrotId = brainrotTool.Name
    
    local success = pcall(function()
        AutoRebirth.RemoveItemRemote:FireServer(brainrotId)
    end)
    
    if success then
        AutoRebirth.FavoritedBrainrots[brainrotId] = nil
    end
    
    return success
end

-- Check if requirements are met for next rebirth
function AutoRebirth.CheckRequirements()
    if not AutoRebirth.RebirthData then
        return false, "Rebirth data not loaded"
    end
    
    local currentRebirth = AutoRebirth.GetCurrentRebirth()
    local nextRebirth = currentRebirth + 1
    
    -- Get requirements for next rebirth
    local rebirthInfo = AutoRebirth.RebirthData[nextRebirth]
    if not rebirthInfo then
        return false, "Max rebirth reached"
    end
    
    local requirements = rebirthInfo.Requirements
    if not requirements then
        return false, "No requirements found"
    end
    
    -- Check money requirement
    local playerMoney = AutoRebirth.GetPlayerMoney()
    local requiredMoney = requirements.Money or 0
    
    if playerMoney < requiredMoney then
        return false, string.format("Need $%s (have $%s)", 
            AutoRebirth.FormatNumber(requiredMoney), 
            AutoRebirth.FormatNumber(playerMoney))
    end
    
    -- Check brainrot requirements and favorite needed ones
    local ownedBrainrots = AutoRebirth.GetOwnedBrainrots()
    local neededBrainrots = {}
    
    for brainrotName, requiredCount in pairs(requirements) do
        -- Skip Money requirement
        if brainrotName ~= "Money" then
            local brainrotTool = ownedBrainrots[brainrotName]
            
            if not brainrotTool then
                return false, string.format("Missing brainrot: %s", brainrotName), nil
            end
            
            -- Favorite this brainrot to prevent auto-place from using it
            AutoRebirth.FavoriteBrainrot(brainrotTool)
            
            -- Track needed brainrots for removal later
            neededBrainrots[brainrotName] = brainrotTool
        end
    end
    
    -- All requirements met!
    return true, "Requirements met", neededBrainrots
end

-- Format numbers with suffixes
function AutoRebirth.FormatNumber(num)
    if num >= 1000000000 then
        return string.format("%.1fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

-- Fire rebirth remote
function AutoRebirth.DoRebirth(neededBrainrots)
    if not AutoRebirth.RebirthRemote then
        warn("[AutoRebirth] ⚠️ Rebirth remote not found!")
        return false
    end
    
    -- Remove all needed brainrots before rebirth
    if neededBrainrots then
        for brainrotName, brainrotTool in pairs(neededBrainrots) do
            AutoRebirth.RemoveBrainrot(brainrotTool)
        end
        
        -- Small delay to ensure removals process
        task.wait(0.5)
    end
    
    -- Fire rebirth
    local success = pcall(function()
        AutoRebirth.RebirthRemote:FireServer()
    end)
    
    if success then
        -- Clear favorited list (fresh start after rebirth)
        AutoRebirth.FavoritedBrainrots = {}
        
        -- Wait for rebirth to complete
        task.wait(2)
        AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
    end
    
    return success
end

--[[
    ========================================
    Main Loop
    ========================================
]]

function AutoRebirth.CheckLoop()
    task.spawn(function()
        while AutoRebirth.IsRunning and AutoRebirth.Settings.AutoRebirthEnabled do
            local currentTime = tick()
            
            -- Only check on interval (performance optimization)
            if currentTime - AutoRebirth.LastCheckTime >= AutoRebirth.Settings.CheckInterval then
                AutoRebirth.LastCheckTime = currentTime
                
                -- Update current rebirth
                AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
                
                -- Check if ready to rebirth (also favorites needed brainrots)
                local canRebirth, reason, neededBrainrots = AutoRebirth.CheckRequirements()
                
                if canRebirth then
                    -- Fire rebirth (removes favorited brainrots first)
                    local success = AutoRebirth.DoRebirth(neededBrainrots)
                    
                    if success then
                        -- Wait a bit after rebirth before checking again
                        task.wait(10)
                    end
                end
            end
            
            -- Wait before next check (1 second granularity)
            task.wait(1)
        end
    end)
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoRebirth.Start()
    if AutoRebirth.IsRunning then return false end
    
    AutoRebirth.IsRunning = true
    AutoRebirth.LastCheckTime = 0
    AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
    
    -- Reload data in case it changed
    AutoRebirth.LoadRebirthData()
    
    -- Start check loop
    AutoRebirth.CheckLoop()
    
    return true
end

function AutoRebirth.Stop()
    if not AutoRebirth.IsRunning then return false end
    
    AutoRebirth.IsRunning = false
    
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoRebirth.GetStatus()
    local canRebirth, reason = AutoRebirth.CheckRequirements()
    
    return {
        IsRunning = AutoRebirth.IsRunning,
        CurrentRebirth = AutoRebirth.CurrentRebirth,
        CanRebirth = canRebirth,
        Reason = reason,
        NextCheck = AutoRebirth.Settings.CheckInterval - (tick() - AutoRebirth.LastCheckTime)
    }
end

-- Get next rebirth requirements for display
function AutoRebirth.GetNextRequirements()
    if not AutoRebirth.RebirthData then return nil end
    
    local currentRebirth = AutoRebirth.GetCurrentRebirth()
    local nextRebirth = currentRebirth + 1
    local rebirthInfo = AutoRebirth.RebirthData[nextRebirth]
    
    if not rebirthInfo or not rebirthInfo.Requirements then
        return nil
    end
    
    return rebirthInfo.Requirements
end

return AutoRebirth

