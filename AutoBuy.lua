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

AutoBuy.Version = "2.0.0"  -- Event-driven version
AutoBuy.IsRunning = false
AutoBuy.LastCheckTime = 0
AutoBuy.TotalPurchases = 0
AutoBuy.LastPurchaseTime = 0
AutoBuy.LastMoney = 0
AutoBuy.LastStockCheck = {}
AutoBuy.MoneyConnection = nil
AutoBuy.StockConnections = {}

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
    local seedName = seedInstance.Name
    local stock = 0
    
    -- Try to get stock from UI (more reliable, updates immediately)
    local success = pcall(function()
        local seedUI = AutoBuy.References.LocalPlayer.PlayerGui.Main.Seeds.Frame.ScrollingFrame:FindFirstChild(seedName)
        if seedUI and seedUI:FindFirstChild("Stock") then
            local stockText = seedUI.Stock.Text
            -- Extract number from "x3 in stock" or similar format
            local stockNum = tonumber(stockText:match("%d+"))
            if stockNum then
                stock = stockNum
            end
        end
    end)
    
    -- Fallback to attribute if UI reading fails
    if not success or stock == 0 then
        stock = seedInstance:GetAttribute("Stock") or 0
    end
    
    return {
        Name = seedName,
        Plant = seedInstance:GetAttribute("Plant") or "Unknown",
        Price = seedInstance:GetAttribute("Price") or 0,
        Stock = stock,
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
    
    -- Start continuous buying (non-blocking)
    task.wait(0.05)  -- Minimal delay for system to initialize
    print("💰 [AutoBuy] Starting continuous buying...")
    AutoBuy.BuyUntilDone()
    
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

-- Process one cycle of auto-buying (called by event listeners)
-- Returns: success, boughtAnything (single pass, not loop)
function AutoBuy.ProcessCycle()
    -- Check if system is running
    if not AutoBuy.IsRunning then
        return false, false
    end
    
    -- Check if auto-buy is enabled in settings
    if not AutoBuy.Settings.AutoBuyEnabled then
        return false, false
    end
    
    -- Record check time
    AutoBuy.LastCheckTime = tick()
    
    -- Get all seeds
    local seedList = AutoBuy.GetAllSeeds()
    local boughtAnything = false
    
    -- Check each seed (single pass, try to buy 1 of each)
    for _, seedName in ipairs(seedList) do
        -- Stop if no longer running
        if not AutoBuy.IsRunning or not AutoBuy.Settings.AutoBuyEnabled then
            break
        end
        
        -- Check if we should auto-buy this seed
        if AutoBuy.ShouldBuySeed(seedName) then
            local seedInstance = AutoBuy.References.Seeds:FindFirstChild(seedName)
            
            if seedInstance then
                -- Re-fetch fresh info each time (stock/money might have changed)
                local seedInfo = AutoBuy.GetSeedInfo(seedInstance)
                local currentMoney = AutoBuy.GetMoney()
                
                -- Check if we can buy it (has money AND stock > 0)
                if currentMoney >= seedInfo.Price and seedInfo.Stock > 0 then
                    local success = AutoBuy.PurchaseSeed(seedName)
                    
                    if success then
                        boughtAnything = true
                        
                        -- CRITICAL: Wait for server to process before buying next seed
                        task.wait(0.1)
                        
                        -- Update last money after purchase
                        AutoBuy.LastMoney = AutoBuy.GetMoney()
                        
                        -- 🧠 Brain: Update UI immediately after purchase
                        if AutoBuy.Brain then
                            AutoBuy.Brain.UpdateMoney()
                            AutoBuy.Brain.UpdateSeedInfo()
                        end
                    end
                end
            end
        end
    end
    
    return true, boughtAnything
end

-- Continuous buying loop (non-blocking, async)
function AutoBuy.BuyUntilDone()
    task.spawn(function()
        local totalPurchases = 0
        
        while AutoBuy.IsRunning and AutoBuy.Settings.AutoBuyEnabled do
            local success, boughtAnything = AutoBuy.ProcessCycle()
            
            if boughtAnything then
                totalPurchases = totalPurchases + 1
                task.wait(0.1)  -- Delay between purchases (prevent rate limit)
            else
                -- Nothing bought, stop loop
                break
            end
        end
        
        if totalPurchases > 0 then
            print("✅ [AutoBuy] Bought " .. FormatNumber(totalPurchases) .. " seeds")
        end
    end)
end

-- Setup event listeners (event-driven approach - no constant polling!)
function AutoBuy.SetupEventListeners()
    print("🔧 [AutoBuy] Setting up event listeners...")
    
    -- Disconnect old connections if any
    if AutoBuy.MoneyConnection then
        AutoBuy.MoneyConnection:Disconnect()
    end
    
    for _, conn in pairs(AutoBuy.StockConnections) do
        conn:Disconnect()
    end
    AutoBuy.StockConnections = {}
    
    -- Listen for money changes
    local moneyValue = AutoBuy.References.LocalPlayer.leaderstats.Money
    AutoBuy.LastMoney = moneyValue.Value
    
    AutoBuy.MoneyConnection = moneyValue:GetPropertyChangedSignal("Value"):Connect(function()
        local newMoney = moneyValue.Value
        
        -- Only trigger if money increased and system is enabled
        if newMoney > AutoBuy.LastMoney and AutoBuy.Settings.AutoBuyEnabled and AutoBuy.IsRunning then
            print("[AutoBuy] Money increased: $" .. FormatNumber(AutoBuy.LastMoney) .. " → $" .. FormatNumber(newMoney))
            AutoBuy.LastMoney = newMoney
            
            -- Try to buy seeds (continuous until done)
            AutoBuy.BuyUntilDone()
        else
            AutoBuy.LastMoney = newMoney
        end
    end)
    
    -- Listen for stock changes on all seeds
    for _, seedInstance in ipairs(AutoBuy.References.Seeds:GetChildren()) do
        local seedInfo = AutoBuy.GetSeedInfo(seedInstance)
        
        if not seedInfo.Hidden then
            -- Initialize last stock
            AutoBuy.LastStockCheck[seedInfo.Name] = seedInfo.Stock
            
            -- Listen for stock attribute changes
            local conn = seedInstance:GetAttributeChangedSignal("Stock"):Connect(function()
                local newStock = seedInstance:GetAttribute("Stock") or 0
                local oldStock = AutoBuy.LastStockCheck[seedInfo.Name] or 0
                
                -- Only trigger if stock increased and system is enabled
                if newStock > oldStock and AutoBuy.Settings.AutoBuyEnabled and AutoBuy.IsRunning then
                    print("[AutoBuy] Stock increased for " .. seedInfo.Name .. ": " .. FormatNumber(oldStock) .. " → " .. FormatNumber(newStock))
                    AutoBuy.LastStockCheck[seedInfo.Name] = newStock
                    
                    -- Try to buy seeds (continuous until done)
                    AutoBuy.BuyUntilDone()
                else
                    AutoBuy.LastStockCheck[seedInfo.Name] = newStock
                end
            end)
            
            table.insert(AutoBuy.StockConnections, conn)
        end
    end
    
    print("✅ [AutoBuy] Event listeners setup complete!")
    print("  - Monitoring money changes")
    print("  - Monitoring stock changes for", #AutoBuy.StockConnections, "seeds")
end

-- Main initialization (called by Main script)
function AutoBuy.RunLoop()
    print("🔄 [AutoBuy] Starting event-driven system...")
    
    -- Setup event listeners instead of polling
    AutoBuy.SetupEventListeners()
    
    -- Optional: Periodic status check (every 60 seconds, not for buying!)
    task.spawn(function()
        while true do
            task.wait(60)  -- Check every minute
            
            if AutoBuy.IsRunning then
                print("[AutoBuy] Status Report:")
                print("  - Total Purchases:", AutoBuy.TotalPurchases)
                print("  - System:", AutoBuy.Settings.AutoBuyEnabled and "ENABLED" or "DISABLED")
                print("  - Current Money: $" .. FormatNumber(AutoBuy.GetMoney()))
            end
        end
    end)
    
    print("✅ [AutoBuy] Event-driven system started!")
    print("💡 System will auto-buy when money/stock changes!")
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
    Auto Buy Gear Functions
    ========================================
--]]

-- Get all gears
function AutoBuy.GetAllGears()
    local gearList = {}
    
    -- Gears are Tools inside the Gears folder
    for _, gearInstance in ipairs(AutoBuy.References.Gears:GetChildren()) do
        if gearInstance:IsA("Tool") then
            table.insert(gearList, gearInstance.Name)
        end
    end
    
    table.sort(gearList)
    return gearList
end

-- Get gear stock from UI
function AutoBuy.GetGearStock(gearName)
    local stock = 0
    
    local success = pcall(function()
        local gearUI = AutoBuy.References.LocalPlayer.PlayerGui.Main.Gears.Frame.ScrollingFrame:FindFirstChild(gearName)
        if gearUI and gearUI:FindFirstChild("Stock") then
            local stockText = gearUI.Stock.Text
            local stockNum = tonumber(stockText:match("%d+"))
            if stockNum then
                stock = stockNum
            end
        end
    end)
    
    return stock
end

-- Get gear price
function AutoBuy.GetGearPrice(gearName)
    local gearInstance = AutoBuy.References.Gears:FindFirstChild(gearName)
    if gearInstance then
        return gearInstance:GetAttribute("Price") or 0
    end
    return 0
end

-- Check if should buy gear
function AutoBuy.ShouldBuyGear(gearName)
    if #AutoBuy.Settings.SelectedGears == 0 then
        return true  -- Buy all gears if none selected
    end
    return table.find(AutoBuy.Settings.SelectedGears, gearName) ~= nil
end

-- Buy a gear
function AutoBuy.PurchaseGear(gearName)
    local success, err = pcall(function()
        local args = {
            [1] = gearName,
            [2] = true
        }
        AutoBuy.References.BuyGearRemote:FireServer(unpack(args))
    end)
    
    if success then
        print("✅ [AutoBuy] Bought gear:", gearName)
    else
        print("❌ [AutoBuy] Failed to buy gear:", gearName, "-", err)
    end
    
    return success
end

-- Process gear buying cycle
function AutoBuy.ProcessGearCycle()
    if not AutoBuy.IsRunning or not AutoBuy.Settings.AutoBuyGearEnabled then
        return false, false
    end
    
    local gearList = AutoBuy.GetAllGears()
    local boughtAnything = false
    
    for _, gearName in ipairs(gearList) do
        if not AutoBuy.IsRunning or not AutoBuy.Settings.AutoBuyGearEnabled then
            break
        end
        
        if AutoBuy.ShouldBuyGear(gearName) then
            local currentMoney = AutoBuy.GetMoney()
            local gearPrice = AutoBuy.GetGearPrice(gearName)
            local gearStock = AutoBuy.GetGearStock(gearName)
            
            if currentMoney >= gearPrice and gearStock > 0 then
                local success = AutoBuy.PurchaseGear(gearName)
                
                if success then
                    boughtAnything = true
                    task.wait(0.1)  -- Wait for server
                    
                    AutoBuy.LastMoney = AutoBuy.GetMoney()
                    
                    if AutoBuy.Brain then
                        AutoBuy.Brain.UpdateMoney()
                    end
                end
            end
        end
    end
    
    return true, boughtAnything
end

-- Buy gears until done
function AutoBuy.BuyGearsUntilDone()
    task.spawn(function()
        local totalPurchases = 0
        
        while AutoBuy.IsRunning and AutoBuy.Settings.AutoBuyGearEnabled do
            local success, boughtAnything = AutoBuy.ProcessGearCycle()
            
            if boughtAnything then
                totalPurchases = totalPurchases + 1
                task.wait(0.1)
            else
                break
            end
        end
        
        if totalPurchases > 0 then
            print("✅ [AutoBuy] Bought " .. totalPurchases .. " gears")
        end
    end)
end

--[[
    ========================================
    Return Module
    ========================================
--]]

print("✅ [AutoBuy] Module loaded successfully!")

return AutoBuy

