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
        local player = AutoRebirth.References.LocalPlayer
        local backpack = player:FindFirstChild("Backpack")
        local character = player.Character
        
        -- Check backpack
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then
                    local itemName = item.Name
                    -- Check if this tool matches any required brainrot (handles prefixes)
                    for requiredName, _ in pairs(requiredNames) do
                        if not owned[requiredName] and itemName:find(requiredName, 1, true) then
                            owned[requiredName] = item
                            break
                        end
                    end
                end
            end
        end
        
        -- Check character
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") then
                    local itemName = item.Name
                    -- Check if this tool matches any required brainrot (handles prefixes)
                    for requiredName, _ in pairs(requiredNames) do
                        if not owned[requiredName] and itemName:find(requiredName, 1, true) then
                            owned[requiredName] = item
                            break
                        end
                    end
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
    
    -- Single backpack+character scan with filtered lookup (O(n))
    local ownedBrainrots = AutoRebirth.GetOwnedBrainrots(requiredNames)
    
    -- Debug: Show what we found
    print("[AutoRebirth] 🔎 Found brainrots:")
    for name, tool in pairs(ownedBrainrots) do
        print("  ✅ " .. name .. " (" .. tool.Name .. ")")
    end
    
    -- Validate all requirements met
    local missing = {}
    for name, _ in pairs(requiredNames) do
        if not ownedBrainrots[name] then
            table.insert(missing, name)
        end
    end
    
    if #missing > 0 then
        print("[AutoRebirth] ❌ Missing brainrots:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false  -- Missing required brainrots
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
        print("[AutoRebirth] ✅ Check loop started")
        
        while AutoRebirth.IsRunning and AutoRebirth.Settings.AutoRebirthEnabled do
            -- Only check on interval
            if tick() - AutoRebirth.LastCheckTime >= AutoRebirth.Settings.CheckInterval then
                AutoRebirth.LastCheckTime = tick()
                AutoRebirth.CurrentRebirth = AutoRebirth.GetCurrentRebirth()
                
                print(string.format("[AutoRebirth] 🔍 Checking requirements for Rebirth %d...", AutoRebirth.CurrentRebirth + 1))
                
                -- Get rebirth info for debugging
                if AutoRebirth.RebirthData then
                    local rebirthInfo = AutoRebirth.RebirthData[AutoRebirth.CurrentRebirth + 1]
                    if rebirthInfo and rebirthInfo.Requirements then
                        local playerMoney = AutoRebirth.GetPlayerMoney()
                        local requiredMoney = rebirthInfo.Requirements.Money or 0
                        print(string.format("[AutoRebirth] 💰 Money: %s / %s", 
                            AutoRebirth.FormatNumber(playerMoney), 
                            AutoRebirth.FormatNumber(requiredMoney)))
                        
                        -- Show required brainrots
                        print("[AutoRebirth] 📋 Required brainrots:")
                        for name, _ in pairs(rebirthInfo.Requirements) do
                            if name ~= "Money" then
                                print("  - " .. name)
                            end
                        end
                    end
                end
                
                -- Fast check (early exit on money or brainrots missing)
                local ready, brainrots = AutoRebirth.CheckRequirements()
                
                if ready and brainrots then
                    print("[AutoRebirth] ✅ All requirements met! Starting rebirth...")
                    if AutoRebirth.DoRebirth(brainrots) then
                        print("[AutoRebirth] 🎉 Rebirth successful!")
                        task.wait(10)  -- Cooldown after rebirth
                    else
                        warn("[AutoRebirth] ❌ Rebirth failed!")
                    end
                else
                    print("[AutoRebirth] ⏳ Requirements not met yet")
                end
            end
            
            task.wait(1)  -- 1 second granularity
        end
        
        print("[AutoRebirth] ⏹️ Check loop stopped")
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

