--[[
    🌱 Plant Vs Brainrot - Platform Module
    This module handles automatic platform unlocking logic
    
    The Main script is the Brain 🧠 that controls this module!
--]]

local Platform = {}

--[[
    ========================================
    Module Configuration
    ========================================
--]]

Platform.Version = "1.0.0"

--[[
    ========================================
    Dependencies (Set by Main)
    ========================================
--]]

Platform.Services = {
    Players = nil,
    ReplicatedStorage = nil,
    Workspace = nil
}

Platform.References = {
    LocalPlayer = nil
}

Platform.Brain = nil

--[[
    ========================================
    Settings & State
    ========================================
--]]

Platform.Settings = {
    AutoUnlockEnabled = false
}

Platform.IsRunning = false
Platform.UnlockedPlatforms = {}  -- Track already unlocked platforms
Platform.MoneyConnection = nil
Platform.RebirthConnection = nil

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Format numbers with suffixes (1K, 1M, 1B, etc.)
local function FormatNumber(num)
    if num >= 1000000000000 then
        return string.format("%.2fT", num / 1000000000000)
    elseif num >= 1000000000 then
        return string.format("%.2fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

--[[
    ========================================
    Core Functions
    ========================================
--]]

-- Get player's current money
function Platform.GetMoney()
    local success, money = pcall(function()
        return Platform.References.LocalPlayer.leaderstats.Money.Value
    end)
    return success and money or 0
end

-- Get player's current rebirth count
function Platform.GetRebirth()
    local success, rebirth = pcall(function()
        return Platform.References.LocalPlayer:GetAttribute("Rebirth")
    end)
    return success and rebirth or 0
end

-- Get player's plot number
function Platform.GetPlayerPlot()
    local success, plotNum = pcall(function()
        return Platform.References.LocalPlayer:GetAttribute("Plot")
    end)
    return success and plotNum or nil
end

-- Get all platforms in player's plot
function Platform.GetAllPlatforms()
    local plotNum = Platform.GetPlayerPlot()
    if not plotNum then
        warn("[Platform] Player has no plot!")
        return {}
    end
    
    local plot = Platform.Services.Workspace.Plots:FindFirstChild(tostring(plotNum))
    if not plot then
        warn("[Platform] Plot not found: " .. plotNum)
        return {}
    end
    
    local brainrots = plot:FindFirstChild("Brainrots")
    if not brainrots then
        warn("[Platform] No Brainrots folder in plot!")
        return {}
    end
    
    local platforms = {}
    
    -- Scan all platform models (with or without PlatformPrice)
    for _, child in ipairs(brainrots:GetChildren()) do
        if child:IsA("Model") and tonumber(child.Name) then
            local platformNum = child.Name
            local platformPrice = child:FindFirstChild("PlatformPrice")
            local priceValue = 0
            
            -- Get price from PlatformPrice if it exists (locked platforms)
            if platformPrice then
                local moneyModel = platformPrice:FindFirstChild("Money")
                
                -- Get price from Money TextLabel (formatted as "$1,000")
                if moneyModel and moneyModel:IsA("TextLabel") then
                    local priceText = moneyModel.Text
                    -- Remove $ and commas, then convert to number
                    local cleanPrice = priceText:gsub("[$,]", "")
                    priceValue = tonumber(cleanPrice) or 0
                end
            end
            
            -- Get rebirth requirement from platform attributes
            local rebirthReq = child:GetAttribute("Rebirth") or 0
            local isEnabled = child:GetAttribute("Enabled") or false
            
            table.insert(platforms, {
                Number = platformNum,
                Model = child,
                Price = priceValue,
                RebirthRequired = rebirthReq,
                Enabled = isEnabled
            })
        end
    end
    
    -- Sort by platform number (lowest first)
    table.sort(platforms, function(a, b)
        return tonumber(a.Number) < tonumber(b.Number)
    end)
    
    return platforms
end

-- Check if platform is unlocked (enabled)
function Platform.IsPlatformUnlocked(platformNum)
    local plotNum = Platform.GetPlayerPlot()
    if not plotNum then return true end  -- Assume unlocked if no plot
    
    local success, enabled = pcall(function()
        local plot = Platform.Services.Workspace.Plots:FindFirstChild(tostring(plotNum))
        local platform = plot.Brainrots:FindFirstChild(tostring(platformNum))
        return platform:GetAttribute("Enabled") or false
    end)
    
    return success and enabled
end

-- Unlock a platform
function Platform.UnlockPlatform(platformNum)
    local success, err = pcall(function()
        local args = { [1] = tostring(platformNum) }
        Platform.Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyPlatform"):FireServer(unpack(args))
    end)
    
    if success then
        print("✅ [Platform] Unlocked platform: " .. platformNum)
        table.insert(Platform.UnlockedPlatforms, platformNum)
        return true
    else
        warn("[Platform] Failed to unlock platform " .. platformNum .. ": " .. tostring(err))
        return false
    end
end

-- Check if previous platform is unlocked (backward check)
function Platform.IsPreviousPlatformUnlocked(currentPlatformNum)
    local plotNum = Platform.GetPlayerPlot()
    if not plotNum then return false end
    
    local previousNum = currentPlatformNum - 1
    
    -- Platform 1 has no previous platform
    if previousNum < 1 then
        return true
    end
    
    -- Check if previous platform exists and is enabled
    local success, enabled = pcall(function()
        local plot = Platform.Services.Workspace.Plots:FindFirstChild(tostring(plotNum))
        local previousPlatform = plot.Brainrots:FindFirstChild(tostring(previousNum))
        return previousPlatform and (previousPlatform:GetAttribute("Enabled") or false)
    end)
    
    return success and enabled
end

-- Try to unlock next available platform
function Platform.TryUnlockNext()
    if not Platform.Settings.AutoUnlockEnabled then return end
    
    local currentMoney = Platform.GetMoney()
    local currentRebirth = Platform.GetRebirth()
    local platforms = Platform.GetAllPlatforms()
    
    -- Find first locked platform that meets requirements
    for _, platform in ipairs(platforms) do
        local isUnlocked = platform.Enabled
        local platformNum = tonumber(platform.Number)
        
        if not isUnlocked then
            -- Check if previous platform is unlocked (backward scan)
            local previousUnlocked = Platform.IsPreviousPlatformUnlocked(platformNum)
            if not previousUnlocked then
                print("[Platform] Platform " .. platform.Number .. " locked - previous platform (#" .. (platformNum - 1) .. ") must be unlocked first")
                break  -- Stop here, must unlock in order
            end
            
            -- Check rebirth requirement
            if currentRebirth < platform.RebirthRequired then
                print("[Platform] Platform " .. platform.Number .. " requires Rebirth " .. platform.RebirthRequired .. " (Current: " .. currentRebirth .. ")")
                print("⏸️ [Platform] Waiting for rebirth to increase...")
                return  -- Stop and wait for rebirth change event
            end
            
            -- Check money requirement
            if currentMoney >= platform.Price then
                print("💰 [Platform] Unlocking platform " .. platform.Number .. " for $" .. FormatNumber(platform.Price))
                
                local success = Platform.UnlockPlatform(platform.Number)
                
                if success then
                    -- Wait for server response
                    task.wait(0.2)
                    
                    -- Check if actually unlocked
                    if Platform.IsPlatformUnlocked(platform.Number) then
                        print("✅ [Platform] Platform " .. platform.Number .. " successfully unlocked!")
                        
                        -- Update money display
                        if Platform.Brain then
                            Platform.Brain.UpdateMoney()
                        end
                        
                        -- Try next platform immediately
                        task.wait(0.1)
                        Platform.TryUnlockNext()
                    else
                        warn("⚠️ [Platform] Platform " .. platform.Number .. " unlock failed!")
                    end
                    
                    return  -- Exit after attempting one unlock
                else
                    warn("❌ [Platform] Failed to fire unlock remote for platform " .. platform.Number)
                    return
                end
            else
                print("[Platform] Not enough money for platform " .. platform.Number .. " (Need: $" .. FormatNumber(platform.Price - currentMoney) .. " more)")
                print("⏸️ [Platform] Waiting for money to increase...")
                return  -- Stop and wait for money change event
            end
        end
    end
end

--[[
    ========================================
    Event System (Efficient & Minimal CPU)
    ========================================
--]]

-- Setup event listeners (only triggers when money/rebirth changes)
function Platform.SetupEventListeners()
    -- Disconnect old listeners
    if Platform.MoneyConnection then
        Platform.MoneyConnection:Disconnect()
    end
    if Platform.RebirthConnection then
        Platform.RebirthConnection:Disconnect()
    end
    
    local player = Platform.References.LocalPlayer
    
    -- Listen for money changes (from leaderstats)
    Platform.MoneyConnection = player.leaderstats.Money.Changed:Connect(function(newMoney)
        if Platform.Settings.AutoUnlockEnabled and Platform.IsRunning then
            print("[Platform] Money changed: $" .. FormatNumber(newMoney))
            Platform.TryUnlockNext()
        end
    end)
    
    -- Listen for rebirth changes (from Attributes)
    Platform.RebirthConnection = player:GetAttributeChangedSignal("Rebirth"):Connect(function()
        if Platform.Settings.AutoUnlockEnabled and Platform.IsRunning then
            local newRebirth = Platform.GetRebirth()
            print("[Platform] Rebirth changed: " .. newRebirth)
            Platform.TryUnlockNext()
        end
    end)
    
    print("✅ [Platform] Event-driven system started!")
    print("💡 System will auto-unlock when money/rebirth changes!")
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
--]]

function Platform.Start()
    if Platform.IsRunning then
        warn("[Platform] Already running!")
        return
    end
    
    print("🚀 [Platform] Starting Auto Unlock Platform...")
    
    Platform.IsRunning = true
    
    -- Setup event listeners
    Platform.SetupEventListeners()
    
    -- Try to unlock immediately
    if Platform.Settings.AutoUnlockEnabled then
        task.defer(function()
            task.wait(0.1)  -- Small delay to ensure everything is loaded
            Platform.TryUnlockNext()
        end)
    end
    
    print("✅ [Platform] Auto Unlock Platform started!")
end

function Platform.Stop()
    if not Platform.IsRunning then
        warn("[Platform] Not running!")
        return
    end
    
    print("🛑 [Platform] Stopping Auto Unlock Platform...")
    
    Platform.IsRunning = false
    
    -- Disconnect event listeners
    if Platform.MoneyConnection then
        Platform.MoneyConnection:Disconnect()
        Platform.MoneyConnection = nil
    end
    if Platform.RebirthConnection then
        Platform.RebirthConnection:Disconnect()
        Platform.RebirthConnection = nil
    end
    
    print("✅ [Platform] Auto Unlock Platform stopped!")
end

--[[
    ========================================
    Initialize Module
    ========================================
--]]

function Platform.Init(services, references, brain)
    Platform.Services = services
    Platform.References = references
    Platform.Brain = brain
    
    print("✅ [Platform] Module initialized!")
end

--[[
    ========================================
    Return Module
    ========================================
--]]

print("✅ [Platform] Module loaded successfully!")

return Platform

