--[[
    🌱 Plant Vs Brainrot - Auto Buy Module
    This module handles all auto-buying logic
    
    The Main script is the Brain 🧠 that controls this module!
--]]

local AutoBuy = {}

--[[
    ========================================
    Module Configuration
    ========================================
--]]

AutoBuy.Version = "1.0.1"
AutoBuy.IsRunning = false
AutoBuy.LastCheckTime = 0
AutoBuy.TotalPurchases = 0
AutoBuy.LastPurchaseTime = 0
AutoBuy.LastMoney = 0
AutoBuy.LastStockCheck = {}

--[[
    ========================================
    Dependencies (Set by Main)
    ========================================
--]]

AutoBuy.Services = {
    Players = nil,
    ReplicatedStorage = nil,
    HttpService = nil
}

AutoBuy.References = {
    LocalPlayer = nil,
    Seeds = nil,
    BuyItemRemote = nil
}

AutoBuy.Settings = nil
AutoBuy.Brain = nil

--[[
    ========================================
    Initialize Module
    ========================================
--]]

function AutoBuy.Init(services, references, settings, brain)
    print("🛒 [AutoBuy] Initializing module...")
    
    -- Store dependencies
    AutoBuy.Services = services
    AutoBuy.References = references
    AutoBuy.Settings = settings
    AutoBuy.Brain = brain
    
    print("✅ [AutoBuy] Module initialized successfully!")
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Get how much money the player has
function AutoBuy.GetMoney()
    local success, result = pcall(function()
        return AutoBuy.References.LocalPlayer.leaderstats.Money.Value
    end)
    
    if success then
        return result
    else
        return 0
    end
end

-- Read all information about a seed
function AutoBuy.GetSeedInfo(seedInstance)
    return {
        Name = seedInstance.Name,
        Plant = seedInstance:GetAttribute("Plant") or "Unknown",
        Price = seedInstance:GetAttribute("Price") or 0,
        Stock = seedInstance:GetAttribute("Stock") or 0,
        Hidden = seedInstance:GetAttribute("Hidden") or false
    }
end

-- Get all non-hidden seeds
function AutoBuy.GetAllSeeds()
    local seedList = {}
    
    for _, seedInstance in ipairs(AutoBuy.References.Seeds:GetChildren()) do
        local seedInfo = AutoBuy.GetSeedInfo(seedInstance)
        
        -- Skip hidden seeds
        if not seedInfo.Hidden then
            table.insert(seedList, seedInfo.Name)
        end
    end
    
    -- Sort alphabetically
    table.sort(seedList)
    
    return seedList
end

-- Check if we should auto-buy this seed
function AutoBuy.ShouldBuySeed(seedName)
    -- If no seeds selected, buy all seeds
    if #AutoBuy.Settings.SelectedSeeds == 0 then
        return true
    end
    
    -- Otherwise, only buy if it's in the selected list
    return table.find(AutoBuy.Settings.SelectedSeeds, seedName) ~= nil
end

-- Check if we can afford to buy a seed
function AutoBuy.CanAffordSeed(seedInfo)
    local money = AutoBuy.GetMoney()
    local hasEnoughMoney = money >= seedInfo.Price
    local hasStock = seedInfo.Stock > 0
    return hasEnoughMoney and hasStock
end

-- Buy a seed!
function AutoBuy.PurchaseSeed(seedName)
    local success, err = pcall(function()
        local args = {
            [1] = seedName,
            [2] = true
        }
        AutoBuy.References.BuyItemRemote:FireServer(unpack(args))
    end)
    
    if success then
        AutoBuy.TotalPurchases = AutoBuy.TotalPurchases + 1
        AutoBuy.LastPurchaseTime = tick()
        print("✅ [AutoBuy] Bought seed:", seedName, "| Total purchases:", AutoBuy.TotalPurchases)
    else
        print("❌ [AutoBuy] Failed to buy seed:", seedName, "-", err)
    end
    
    return success
end

--[[
    ========================================
    Main Auto-Buy Logic
    ========================================
--]]

-- Start the auto-buy system
function AutoBuy.Start()
    if AutoBuy.IsRunning then
        print("⚠️ [AutoBuy] Already running!")
        return false
    end
    
    AutoBuy.IsRunning = true
    AutoBuy.TotalPurchases = 0
    print("🚀 [AutoBuy] System STARTED")
    
    return true
end

-- Stop the auto-buy system
function AutoBuy.Stop()
    if not AutoBuy.IsRunning then
        print("⚠️ [AutoBuy] Already stopped!")
        return false
    end
    
    AutoBuy.IsRunning = false
    print("⏹️ [AutoBuy] System STOPPED | Total purchases:", AutoBuy.TotalPurchases)
    
    return true
end

-- Check if there are changes that warrant buying
function AutoBuy.HasChanges()
    local currentMoney = AutoBuy.GetMoney()
    
    -- Money changed (increased)
    if currentMoney > AutoBuy.LastMoney then
        AutoBuy.LastMoney = currentMoney
        return true, "money increased"
    end
    
    -- Check if stock changed for any seed
    for _, seedInstance in ipairs(AutoBuy.References.Seeds:GetChildren()) do
        local seedInfo = AutoBuy.GetSeedInfo(seedInstance)
        if not seedInfo.Hidden then
            local lastStock = AutoBuy.LastStockCheck[seedInfo.Name] or 0
            if seedInfo.Stock > lastStock then
                AutoBuy.LastStockCheck[seedInfo.Name] = seedInfo.Stock
                return true, "stock increased for " .. seedInfo.Name
            end
        end
    end
    
    return false
end

-- Process one cycle of auto-buying
function AutoBuy.ProcessCycle()
    -- Check if system is running
    if not AutoBuy.IsRunning then
        return false
    end
    
    -- Check if auto-buy is enabled in settings
    if not AutoBuy.Settings.AutoBuyEnabled then
        return false
    end
    
    -- Record check time
    AutoBuy.LastCheckTime = tick()
    
    -- Check if there are changes worth checking
    local hasChanges, reason = AutoBuy.HasChanges()
    if not hasChanges then
        -- No changes, skip this cycle
        return true, 0
    end
    
    -- Log the reason for checking
    print("🔔 [AutoBuy] Checking purchases - Reason:", reason)
    
    -- Get all seeds
    local seedList = AutoBuy.GetAllSeeds()
    local purchasesMade = 0
    
    -- Check each seed
    for _, seedName in ipairs(seedList) do
        -- Check if we should auto-buy this seed
        if AutoBuy.ShouldBuySeed(seedName) then
            local seedInstance = AutoBuy.References.Seeds:FindFirstChild(seedName)
            
            if seedInstance then
                local seedInfo = AutoBuy.GetSeedInfo(seedInstance)
                
                -- Check if we can buy it
                if AutoBuy.CanAffordSeed(seedInfo) then
                    local success = AutoBuy.PurchaseSeed(seedName)
                    
                    if success then
                        purchasesMade = purchasesMade + 1
                        
                        -- Update last money after purchase
                        AutoBuy.LastMoney = AutoBuy.GetMoney()
                        
                        -- 🧠 Brain: Update UI immediately after purchase
                        if AutoBuy.Brain then
                            AutoBuy.Brain.UpdateMoney()
                            AutoBuy.Brain.UpdateSeedInfo()
                        end
                        
                        -- Small delay between purchases
                        task.wait(0.1)
                    end
                end
            end
        end
    end
    
    return true, purchasesMade
end

-- Main loop (called by Main script)
function AutoBuy.RunLoop()
    print("🔄 [AutoBuy] Starting main loop...")
    
    task.spawn(function()
        local lastLogTime = tick()
        
        while true do
            -- Wait for the check interval (dynamic based on settings)
            task.wait(AutoBuy.Settings.CheckInterval or 0.5)
            
            -- Only process if enabled AND running
            if AutoBuy.Settings.AutoBuyEnabled and AutoBuy.IsRunning then
                -- Process one cycle
                local success, purchasesMade = AutoBuy.ProcessCycle()
                
                -- Log if purchases were made
                if purchasesMade and purchasesMade > 0 then
                    print("🛒 [AutoBuy] Bought", purchasesMade, "seeds this cycle")
                end
            end
            
            -- Optional: Status log every 30 seconds if running
            if tick() - lastLogTime > 30 and AutoBuy.IsRunning then
                print("🔄 [AutoBuy] Status - Total purchases:", AutoBuy.TotalPurchases, "| Enabled:", AutoBuy.Settings.AutoBuyEnabled and "YES" or "NO")
                lastLogTime = tick()
            end
        end
    end)
    
    print("✅ [AutoBuy] Main loop started!")
end

--[[
    ========================================
    Status & Stats
    ========================================
--]]

-- Get current status
function AutoBuy.GetStatus()
    return {
        IsRunning = AutoBuy.IsRunning,
        TotalPurchases = AutoBuy.TotalPurchases,
        LastCheckTime = AutoBuy.LastCheckTime,
        LastPurchaseTime = AutoBuy.LastPurchaseTime,
        Version = AutoBuy.Version
    }
end

-- Print status
function AutoBuy.PrintStatus()
    local status = AutoBuy.GetStatus()
    print("===========================================")
    print("🛒 [AutoBuy] Status Report")
    print("===========================================")
    print("  Version:", status.Version)
    print("  Running:", status.IsRunning and "YES" or "NO")
    print("  Total Purchases:", status.TotalPurchases)
    print("  Last Check:", math.floor(tick() - status.LastCheckTime), "seconds ago")
    if status.LastPurchaseTime > 0 then
        print("  Last Purchase:", math.floor(tick() - status.LastPurchaseTime), "seconds ago")
    else
        print("  Last Purchase: Never")
    end
    print("===========================================")
end

--[[
    ========================================
    Return Module
    ========================================
--]]

print("✅ [AutoBuy] Module loaded successfully!")

return AutoBuy

