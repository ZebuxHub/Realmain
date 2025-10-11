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
    RebirthRemote = nil
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
    
    -- Cache remote
    pcall(function()
        AutoRebirth.RebirthRemote = services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("Rebirth", 5)
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

-- Get owned brainrots (plants in backpack)
function AutoRebirth.GetOwnedBrainrots()
    local owned = {}
    
    pcall(function()
        local backpack = AutoRebirth.References.LocalPlayer:FindFirstChild("Backpack")
        if not backpack then return end
        
        local plants = AutoRebirth.Services.ReplicatedStorage:FindFirstChild("Assets"):FindFirstChild("Plants")
        if not plants then return end
        
        -- Check each plant in backpack
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                -- Check if it's a brainrot (exists in Plants folder)
                local plantModel = plants:FindFirstChild(item.Name)
                if plantModel then
                    owned[item.Name] = true
                end
            end
        end
    end)
    
    return owned
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
    
    -- Check brainrot requirements
    local ownedBrainrots = AutoRebirth.GetOwnedBrainrots()
    
    for brainrotName, requiredCount in pairs(requirements) do
        -- Skip Money requirement
        if brainrotName ~= "Money" then
            if not ownedBrainrots[brainrotName] then
                return false, string.format("Missing brainrot: %s", brainrotName)
            end
        end
    end
    
    -- All requirements met!
    return true, "Requirements met"
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
function AutoRebirth.DoRebirth()
    if not AutoRebirth.RebirthRemote then
        warn("[AutoRebirth] ⚠️ Rebirth remote not found!")
        return false
    end
    
    local success = pcall(function()
        AutoRebirth.RebirthRemote:FireServer()
    end)
    
    if success then
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
                
                -- Check if ready to rebirth
                local canRebirth, reason = AutoRebirth.CheckRequirements()
                
                if canRebirth then
                    -- Fire rebirth!
                    local success = AutoRebirth.DoRebirth()
                    
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

