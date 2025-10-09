--[[
    ========================================
    🌱 AutoPlaceSeed Module - Plant Vs Brainrot
    ========================================
    
    Purpose: Automatically place seeds to available plot spots
    Architecture: Event-driven with row limit tracking
    
    Author: AI Assistant
    Version: 1.0.0
]]

local AutoPlaceSeed = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalPlacements = 0,
    IsProcessing = false,
    
    -- Cached Spots
    CachedSpots = {},
    SpotsCacheValid = false,
    
    -- Row Tracking (5 seeds per row max)
    RowSeedCounts = {},
    MaxSeedsPerRow = 5,
    
    -- Event Connections
    BackpackConnection = nil,
    PlotAttributeConnections = {},
    
    -- Dependencies (Set by Main.lua)
    Services = nil,
    References = nil,
    Settings = nil,
    Brain = nil
}

--[[
    ========================================
    Initialization
    ========================================
--]]

function AutoPlaceSeed.Init(services, references, settings, brain)
    AutoPlaceSeed.Services = services
    AutoPlaceSeed.References = references
    AutoPlaceSeed.Settings = settings
    AutoPlaceSeed.Brain = brain
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Format numbers with K/M/B suffix
local function FormatNumber(num)
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

-- Get player's owned plot number
function AutoPlaceSeed.GetOwnedPlot()
    local plotNum = AutoPlaceSeed.References.LocalPlayer:GetAttribute("Plot")
    if plotNum then
        return tostring(plotNum)
    end
    return nil
end

-- Count seeds in a specific row
function AutoPlaceSeed.CountSeedsInRow(rowName, grass)
    local count = 0
    if grass then
        for _, child in ipairs(grass:GetChildren()) do
            -- Count Models that are NOT Floor (these are placed items)
            if child:IsA("Model") and child.Name ~= "Floor" then
                count = count + 1
            end
        end
    end
    return count
end

-- Check if row has space for more seeds (< 5)
function AutoPlaceSeed.CanPlaceInRow(rowName, grass)
    local count = AutoPlaceSeed.CountSeedsInRow(rowName, grass)
    return count < AutoPlaceSeed.MaxSeedsPerRow
end

-- Invalidate spots cache
function AutoPlaceSeed.InvalidateCache()
    AutoPlaceSeed.SpotsCacheValid = false
    AutoPlaceSeed.RowSeedCounts = {}
end

-- Find all available spots in player's plot (with caching and row limits)
function AutoPlaceSeed.FindAvailableSpots(forceRescan)
    -- Return cached spots if valid
    if AutoPlaceSeed.SpotsCacheValid and not forceRescan then
        return AutoPlaceSeed.CachedSpots
    end
    
    local spots = {}
    local plotNum = AutoPlaceSeed.GetOwnedPlot()
    
    if not plotNum then
        return spots
    end
    
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        -- Sort rows by name
        local rowsList = rows:GetChildren()
        table.sort(rowsList, function(a, b)
            return tonumber(a.Name) < tonumber(b.Name)
        end)
        
        for _, row in ipairs(rowsList) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                -- Check if row has space (< 5 seeds)
                if AutoPlaceSeed.CanPlaceInRow(row.Name, grass) then
                    for _, spot in ipairs(grass:GetChildren()) do
                        local canPlace = spot:GetAttribute("CanPlace")
                        if canPlace == true then
                            table.insert(spots, {
                                Floor = spot,
                                CFrame = spot.CFrame,
                                PivotOffset = spot.PivotOffset,
                                RowName = row.Name,
                                SpotName = spot.Name
                            })
                        end
                    end
                end
                
                -- Update row count cache
                AutoPlaceSeed.RowSeedCounts[row.Name] = AutoPlaceSeed.CountSeedsInRow(row.Name, grass)
            end
        end
    end)
    
    -- Cache the results
    AutoPlaceSeed.CachedSpots = spots
    AutoPlaceSeed.SpotsCacheValid = true
    
    return spots
end

-- Extract seed name (remove " Seed" suffix if present)
local function ExtractSeedName(fullName)
    -- Pattern: "Cactus Seed" -> "Cactus"
    local seedName = fullName:match("(.+)%s+Seed$")
    if seedName then
        return seedName
    end
    return fullName  -- Return as-is if no " Seed" suffix
end

-- Check if should place this seed (can pass seed name or Tool)
function AutoPlaceSeed.ShouldPlaceSeed(seedInput)
    local selectedSeeds = AutoPlaceSeed.Settings.SelectedSeedsToPlace
    
    -- If no seeds selected, don't place anything
    if not selectedSeeds or #selectedSeeds == 0 then
        print("[AutoPlaceSeed] No seeds selected in settings")
        return false
    end
    
    local seedName
    local plantName
    
    -- If it's a Tool, get attributes
    if type(seedInput) == "userdata" and seedInput:IsA("Tool") then
        seedName = seedInput:GetAttribute("Seed") or seedInput:GetAttribute("ItemName") or seedInput.Name
        plantName = seedInput:GetAttribute("Plant")
        print("[AutoPlaceSeed] Checking Tool - Plant:", plantName, "| Seed:", seedName)
    else
        -- It's a string
        seedName = seedInput
        plantName = ExtractSeedName(seedInput)
        print("[AutoPlaceSeed] Checking String - Name:", seedName, "| Extracted:", plantName)
    end
    
    print("[AutoPlaceSeed] Selected seeds list:", table.concat(selectedSeeds, ", "))
    
    -- Check if seed is in selected list
    -- Try: Plant name (Cactus), Seed name (Cactus Seed), or extracted name
    local matchPlant = table.find(selectedSeeds, plantName) ~= nil
    local matchSeed = table.find(selectedSeeds, seedName) ~= nil
    local matchExtracted = table.find(selectedSeeds, ExtractSeedName(seedName)) ~= nil
    
    print("[AutoPlaceSeed] Match results - Plant:", matchPlant, "| Seed:", matchSeed, "| Extracted:", matchExtracted)
    
    return matchPlant or matchSeed or matchExtracted
end

-- Get seed info from backpack Tool
function AutoPlaceSeed.GetSeedInfo(seedTool)
    local success, info = pcall(function()
        local displayName = seedTool.Name  -- "[x4] Cactus Seed"
        local id = seedTool:GetAttribute("ID")
        
        -- If no ID, seed might not be placeable yet
        if not id then
            return nil
        end
        
        -- Get attributes (use these for placement)
        local itemName = seedTool:GetAttribute("ItemName")  -- "Cactus Seed"
        local seedName = seedTool:GetAttribute("Seed")  -- "Cactus Seed"
        local plantName = seedTool:GetAttribute("Plant")  -- "Cactus"
        
        -- Use ItemName or Seed attribute, fallback to extracting from displayName
        local finalName = itemName or seedName or ExtractSeedName(displayName)
        
        return {
            Name = finalName,  -- "Cactus Seed" (what server expects)
            Plant = plantName,  -- "Cactus" (for display)
            DisplayName = displayName,  -- "[x4] Cactus Seed"
            ID = id
        }
    end)
    
    if success and info then
        return info
    end
    return nil
end

-- Place seed at specific spot (centered)
function AutoPlaceSeed.PlaceSeed(seedInfo, spot)
    local success = pcall(function()
        local position = spot.Floor.CFrame.Position
        local x, y, z = position.X, position.Y, position.Z
        
        -- Get rotation from PivotOffset
        local pivot = spot.PivotOffset
        local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = pivot:GetComponents()
        
        if not pivot or pivot == CFrame.new() then
            r00, r01, r02 = 1, 0, 0
            r10, r11, r12 = 0, 1, 0
            r20, r21, r22 = 0, 0, 1
        end
        
        local placementCFrame = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
        
        AutoPlaceSeed.References.PlaceItemRemote:FireServer({
            ["ID"] = seedInfo.ID,
            ["CFrame"] = placementCFrame,
            ["Item"] = seedInfo.Name,
            ["Floor"] = spot.Floor
        })
    end)
    
    if success then
        AutoPlaceSeed.TotalPlacements = AutoPlaceSeed.TotalPlacements + 1
        
        -- Update row seed count
        if AutoPlaceSeed.RowSeedCounts[spot.RowName] then
            AutoPlaceSeed.RowSeedCounts[spot.RowName] = AutoPlaceSeed.RowSeedCounts[spot.RowName] + 1
        end
    end
    
    return success
end

-- Process single seed from backpack
function AutoPlaceSeed.ProcessSeed(seedTool)
    -- Wait if already processing (one by one)
    while AutoPlaceSeed.IsProcessing do
        task.wait(0.1)
    end
    
    AutoPlaceSeed.IsProcessing = true
    print("[AutoPlaceSeed] Processing seed:", seedTool.Name)
    
    if not AutoPlaceSeed.IsRunning or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled then
        print("[AutoPlaceSeed] Skipped - System not running or disabled")
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Get seed info
    local seedInfo = AutoPlaceSeed.GetSeedInfo(seedTool)
    if not seedInfo then
        print("[AutoPlaceSeed] Skipped - Could not get seed info (no ID?)")
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    print("[AutoPlaceSeed] Seed info - Name:", seedInfo.Name, "Plant:", seedInfo.Plant or "N/A", "ID:", seedInfo.ID)
    
    -- Check if should place this seed (pass the Tool for accurate checking)
    if not AutoPlaceSeed.ShouldPlaceSeed(seedTool) then
        print("[AutoPlaceSeed] Skipped - Not in selected list")
        print("[AutoPlaceSeed] Selected seeds:", table.concat(AutoPlaceSeed.Settings.SelectedSeedsToPlace or {}, ", "))
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Find available spots (uses cache)
    local spots = AutoPlaceSeed.FindAvailableSpots()
    print("[AutoPlaceSeed] Available spots:", #spots)
    if #spots == 0 then
        print("[AutoPlaceSeed] Skipped - No available spots!")
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Pick first available spot
    local selectedSpot = spots[1]
    print("[AutoPlaceSeed] Selected spot - Row:", selectedSpot.RowName, "Spot:", selectedSpot.SpotName)
    
    -- Move seed to character (equip)
    local success = pcall(function()
        local character = AutoPlaceSeed.References.LocalPlayer.Character
        local backpack = AutoPlaceSeed.References.Backpack
        
        if not character or not seedTool:IsA("Tool") then
            return
        end
        
        -- Unequip any currently equipped tools
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                tool.Parent = backpack
            end
        end
        
        -- Equip the seed tool
        seedTool.Parent = character
    end)
    
    if not success then
        print("[AutoPlaceSeed] Failed to equip seed")
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    task.wait(0.1)
    
    -- Place seed
    print("[AutoPlaceSeed] Placing seed...")
    local placed = AutoPlaceSeed.PlaceSeed(seedInfo, selectedSpot)
    
    if placed then
        print("[AutoPlaceSeed] ✅ Seed placed successfully!")
        task.wait(0.15)
    else
        print("[AutoPlaceSeed] ❌ Failed to place seed")
    end
    
    AutoPlaceSeed.IsProcessing = false
    return placed
end

-- Process all seeds in backpack
function AutoPlaceSeed.ProcessAllSeeds()
    if not AutoPlaceSeed.IsRunning or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled then
        print("[AutoPlaceSeed] ProcessAllSeeds skipped - Not running or disabled")
        return 0
    end
    
    local placed = 0
    local backpack = AutoPlaceSeed.References.Backpack
    
    print("[AutoPlaceSeed] Scanning backpack for seeds...")
    local backpackItems = backpack:GetChildren()
    print("[AutoPlaceSeed] Found " .. #backpackItems .. " items in backpack")
    
    for _, item in ipairs(backpackItems) do
        print("[AutoPlaceSeed] Checking item:", item.Name, "| Type:", item.ClassName)
        
        if item:IsA("Tool") then
            print("[AutoPlaceSeed] Item is a Tool, checking if it's a seed...")
            
            -- Check if it's a seed by passing the Tool
            if AutoPlaceSeed.ShouldPlaceSeed(item) then
                print("[AutoPlaceSeed] Item matched! Processing...")
                if AutoPlaceSeed.ProcessSeed(item) then
                    placed = placed + 1
                end
            else
                print("[AutoPlaceSeed] Item didn't match selected seeds")
            end
        end
    end
    
    return placed
end

--[[
    ========================================
    Event System
    ========================================
--]]

-- Update cache incrementally when a spot becomes available/unavailable
function AutoPlaceSeed.UpdateSpotInCache(spot, isAvailable, rowName)
    if isAvailable then
        table.insert(AutoPlaceSeed.CachedSpots, {
            Floor = spot,
            CFrame = spot.CFrame,
            PivotOffset = spot.PivotOffset,
            RowName = rowName,
            SpotName = spot.Name
        })
    else
        for i, cachedSpot in ipairs(AutoPlaceSeed.CachedSpots) do
            if cachedSpot.Floor == spot then
                table.remove(AutoPlaceSeed.CachedSpots, i)
                break
            end
        end
    end
end

-- Setup Row-Level monitoring
function AutoPlaceSeed.SetupPlotMonitoring()
    for _, conn in ipairs(AutoPlaceSeed.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlaceSeed.PlotAttributeConnections = {}
    
    local plotNum = AutoPlaceSeed.GetOwnedPlot()
    if not plotNum then return end
    
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        for _, row in ipairs(rows:GetChildren()) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                local addedConn = grass.ChildAdded:Connect(function(child)
                    if child:IsA("Model") then
                        local spot = child.Parent
                        if spot then
                            AutoPlaceSeed.UpdateSpotInCache(spot, false, row.Name)
                            -- Update row count
                            if AutoPlaceSeed.RowSeedCounts[row.Name] then
                                AutoPlaceSeed.RowSeedCounts[row.Name] = AutoPlaceSeed.RowSeedCounts[row.Name] + 1
                            else
                                AutoPlaceSeed.RowSeedCounts[row.Name] = AutoPlaceSeed.CountSeedsInRow(row.Name, grass)
                            end
                        end
                    end
                end)
                
                local removedConn = grass.ChildRemoved:Connect(function(child)
                    if child:IsA("Model") then
                        local spot = child.Parent
                        if spot and spot:GetAttribute("CanPlace") == true then
                            AutoPlaceSeed.UpdateSpotInCache(spot, true, row.Name)
                            -- Update row count
                            if AutoPlaceSeed.RowSeedCounts[row.Name] then
                                AutoPlaceSeed.RowSeedCounts[row.Name] = math.max(0, AutoPlaceSeed.RowSeedCounts[row.Name] - 1)
                            else
                                AutoPlaceSeed.RowSeedCounts[row.Name] = AutoPlaceSeed.CountSeedsInRow(row.Name, grass)
                            end
                        end
                    end
                end)
                
                table.insert(AutoPlaceSeed.PlotAttributeConnections, addedConn)
                table.insert(AutoPlaceSeed.PlotAttributeConnections, removedConn)
            end
        end
    end)
end

-- Setup backpack event listener for new seeds
function AutoPlaceSeed.SetupEventListeners()
    -- Disconnect old connections
    if AutoPlaceSeed.BackpackConnection then
        AutoPlaceSeed.BackpackConnection:Disconnect()
        AutoPlaceSeed.BackpackConnection = nil
    end
    
    -- Listen for new items added to backpack
    AutoPlaceSeed.BackpackConnection = AutoPlaceSeed.References.Backpack.ChildAdded:Connect(function(item)
        if not item:IsA("Tool") or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled or not AutoPlaceSeed.IsRunning then
            return
        end
        
        -- Check if this is a seed (has "Seed" in name or matches selected seeds)
        local itemName = item.Name
        if not itemName:match("Seed") and not AutoPlaceSeed.ShouldPlaceSeed(itemName) then
            return
        end
        
        task.spawn(function()
            task.wait(0.05)  -- Minimal delay for item to load
            print("[AutoPlaceSeed] New seed detected:", itemName)
            AutoPlaceSeed.ProcessSeed(item)
        end)
    end)
end

--[[
    ========================================
    Main Control
    ========================================
--]]

function AutoPlaceSeed.Start()
    if AutoPlaceSeed.IsRunning then
        return
    end
    
    AutoPlaceSeed.IsRunning = true
    print("[AutoPlaceSeed] Starting seed placement system...")
    
    -- Initial scan
    task.spawn(function()
        local spots = AutoPlaceSeed.FindAvailableSpots(true)
        print("[AutoPlaceSeed] Found " .. #spots .. " available spots")
    end)
    
    -- Setup backpack event listener
    AutoPlaceSeed.SetupEventListeners()
    
    -- Setup plot monitoring
    task.spawn(function()
        task.wait(0.3)
        AutoPlaceSeed.SetupPlotMonitoring()
    end)
    
    -- Process existing seeds
    task.spawn(function()
        task.wait(0.2)
        local placed = AutoPlaceSeed.ProcessAllSeeds()
        print("[AutoPlaceSeed] Processed existing seeds, placed:", placed)
    end)
end

function AutoPlaceSeed.Stop()
    if not AutoPlaceSeed.IsRunning then
        return
    end
    
    AutoPlaceSeed.IsRunning = false
    
    -- Disconnect backpack listener
    if AutoPlaceSeed.BackpackConnection then
        AutoPlaceSeed.BackpackConnection:Disconnect()
        AutoPlaceSeed.BackpackConnection = nil
    end
    
    -- Disconnect plot monitors
    for _, conn in ipairs(AutoPlaceSeed.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlaceSeed.PlotAttributeConnections = {}
    
    AutoPlaceSeed.CachedSpots = {}
    AutoPlaceSeed.SpotsCacheValid = false
    AutoPlaceSeed.RowSeedCounts = {}
end

function AutoPlaceSeed.GetStatus()
    return {
        IsRunning = AutoPlaceSeed.IsRunning,
        AutoPlaceSeedsEnabled = AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled,
        TotalPlacements = AutoPlaceSeed.TotalPlacements,
        AvailableSpots = #AutoPlaceSeed.CachedSpots,
        RowCounts = AutoPlaceSeed.RowSeedCounts
    }
end

return AutoPlaceSeed

