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

-- Get owned brainrots - Optimized (O(n) single pass)
function AutoRebirth.GetOwnedBrainrots(requiredNames)
    local owned = {}
    
    pcall(function()
        local backpack = AutoRebirth.References.LocalPlayer:FindFirstChild("Backpack")
        if not backpack then return end
        
        -- Only check backpack items (no ReplicatedStorage lookup needed)
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                local itemName = item.Name
                -- Only track if this is a required brainrot
                if requiredNames[itemName] then
                    owned[itemName] = item
                end
            end
        end
    end)
    
    return owned
end

-- Batch favorite brainrots - Optimized
function AutoRebirth.FavoriteBrainrots(brainrotTools)
    if not AutoRebirth.FavoriteRemote then return end
    
    for _, tool in pairs(brainrotTools) do
        local id = tool.Name
        if not AutoRebirth.FavoritedBrainrots[id] then
            pcall(function()
                AutoRebirth.FavoriteRemote:FireServer(id)
            end)
            AutoRebirth.FavoritedBrainrots[id] = true
        end
    end
end

-- Batch remove brainrots - Optimized
function AutoRebirth.RemoveBrainrots(brainrotTools)
    if not AutoRebirth.RemoveItemRemote then return end
    
    for _, tool in pairs(brainrotTools) do
        pcall(function()
            AutoRebirth.RemoveItemRemote:FireServer(tool.Name)
        end)
    end
    
    -- Small delay for server processing
    task.wait(0.3)
end

-- Check requirements - Highly optimized
function AutoRebirth.CheckRequirements()
    if not AutoRebirth.RebirthData then return false end
    
    local currentRebirth = AutoRebirth.GetCurrentRebirth()
    local rebirthInfo = AutoRebirth.RebirthData[currentRebirth + 1]
    
    if not rebirthInfo or not rebirthInfo.Requirements then return false end
    
    local requirements = rebirthInfo.Requirements
    
    -- Fast path: Check money first (cheapest check)
    if AutoRebirth.GetPlayerMoney() < (requirements.Money or 0) then
        return false
    end
    
    -- Build required brainrot names lookup (O(n))
    local requiredNames = {}
    for name, _ in pairs(requirements) do
        if name ~= "Money" then
            requiredNames[name] = true
        end
    end
    
    -- Single backpack scan with filtered lookup (O(n))
    local ownedBrainrots = AutoRebirth.GetOwnedBrainrots(requiredNames)
    
    -- Validate all requirements met
    for name, _ in pairs(requiredNames) do
        if not ownedBrainrots[name] then
            return false  -- Missing a required brainrot
        end
    end
    
    -- Favorite brainrots to protect them (batch operation)
    AutoRebirth.FavoriteBrainrots(ownedBrainrots)
    
    -- All requirements met!
    return true, ownedBrainrots
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

-- Fire rebirth - Optimized
function AutoRebirth.DoRebirth(brainrots)
    if not AutoRebirth.RebirthRemote or not brainrots then return false end
    
    -- Batch remove brainrots
    AutoRebirth.RemoveBrainrots(brainrots)
    
    -- Fire rebirth
    local success = pcall(function()
        AutoRebirth.RebirthRemote:FireServer()
    end)
    
    if success then
        AutoRebirth.FavoritedBrainrots = {}  -- Clear cache
        task.wait(2)  -- Wait for server processing
        AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
    end
    
    return success
end

--[[
    ========================================
    Main Loop
    ========================================
]]

-- Main loop - Highly optimized
function AutoRebirth.CheckLoop()
    task.spawn(function()
        while AutoRebirth.IsRunning and AutoRebirth.Settings.AutoRebirthEnabled do
            -- Only check on interval
            if tick() - AutoRebirth.LastCheckTime >= AutoRebirth.Settings.CheckInterval then
                AutoRebirth.LastCheckTime = tick()
                AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
                
                -- Fast check (early exit on money or brainrots missing)
                local ready, brainrots = AutoRebirth.CheckRequirements()
                
                if ready and brainrots then
                    if AutoRebirth.DoRebirth(brainrots) then
                        task.wait(10)  -- Cooldown after rebirth
                    end
                end
            end
            
            task.wait(1)  -- 1 second granularity
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
    AutoRebirth.CheckLoop()
    
    return true
end

function AutoRebirth.Stop()
    AutoRebirth.IsRunning = false
    return true
end

return AutoRebirth

