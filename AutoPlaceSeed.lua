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
    
    -- Optimized: Selected seeds as a set for O(1) lookup
    SelectedSeedsSet = {},
    
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

-- Rebuild selected seeds set for O(1) lookup
function AutoPlaceSeed.RebuildSeedsSet()
    AutoPlaceSeed.SelectedSeedsSet = {}
    
    if not AutoPlaceSeed.Settings then
        return
    end
    
    local selectedSeeds = AutoPlaceSeed.Settings.SelectedSeedsToPlace
    if selectedSeeds and type(selectedSeeds) == "table" then
        for _, seedName in ipairs(selectedSeeds) do
            if seedName and type(seedName) == "string" then
                AutoPlaceSeed.SelectedSeedsSet[seedName] = true
            end
        end
    end
end

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

-- Extract clean seed name (remove quantity prefix like "[x4]")
-- "[x4] Cactus Seed" -> "Cactus Seed"
-- "[12 kg] Cactus Seed" -> "Cactus Seed"
local function ExtractCleanName(displayName)
    -- Remove quantity prefix: [x4], [1.2 kg], [Gold], etc.
    local cleanName = displayName:match("%]%s*(.+)$")
    if cleanName then
        return cleanName
    end
    return displayName  -- No prefix, return as-is
end

-- Check if should place this seed (can pass seed name or Tool)
function AutoPlaceSeed.ShouldPlaceSeed(seedInput)
    local displayName
    
    -- Get display name
    if type(seedInput) == "userdata" and seedInput:IsA("Tool") then
        displayName = seedInput.Name
    else
        displayName = seedInput
    end
    
    -- Extract clean name (remove [x4] prefix, etc.)
    local cleanName = ExtractCleanName(displayName)
    
    -- If no seeds selected, place all seeds
    if not next(AutoPlaceSeed.SelectedSeedsSet) then
        return true
    end
    
    -- OPTIMIZED: O(1) set lookup using clean seed name
    -- Match against exact seed name (e.g., "Cactus Seed")
    return AutoPlaceSeed.SelectedSeedsSet[cleanName] == true
end

-- Get seed info from backpack Tool
function AutoPlaceSeed.GetSeedInfo(seedTool)
    local success, info = pcall(function()
        local displayName = seedTool.Name
        local id = seedTool:GetAttribute("ID")
        
        if not id then
            return nil
        end
        
        local itemName = seedTool:GetAttribute("ItemName")
        local seedName = seedTool:GetAttribute("Seed")
        local plantName = seedTool:GetAttribute("Plant")
        
        local finalName = itemName or seedName or ExtractCleanName(displayName)
        
        return {
            Name = finalName,
            Plant = plantName,
            DisplayName = displayName,
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
    
    if not AutoPlaceSeed.IsRunning or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled then
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Get seed info
    local seedInfo = AutoPlaceSeed.GetSeedInfo(seedTool)
    if not seedInfo then
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Check if should place this seed
    if not AutoPlaceSeed.ShouldPlaceSeed(seedTool) then
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Find available spots (uses cache)
    local spots = AutoPlaceSeed.FindAvailableSpots()
    if #spots == 0 then
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Pick first available spot and verify row isn't full
    local selectedSpot = nil
    for _, spot in ipairs(spots) do
        -- Double-check row count before placing
        local plotNum = AutoPlaceSeed.GetOwnedPlot()
        if plotNum then
            local plot = workspace.Plots:FindFirstChild(plotNum)
            if plot then
                local rows = plot:FindFirstChild("Rows")
                if rows then
                    local row = rows:FindFirstChild(spot.RowName)
                    if row then
                        local grass = row:FindFirstChild("Grass")
                        if grass and AutoPlaceSeed.CanPlaceInRow(spot.RowName, grass) then
                            selectedSpot = spot
                            break
                        end
                    end
                end
            end
        end
    end
    
    if not selectedSpot then
        AutoPlaceSeed.IsProcessing = false
        return false
    end
    
    -- Move seed to character (equip) if not already equipped
    local character = AutoPlaceSeed.References.LocalPlayer.Character
    if seedTool.Parent ~= character then
        local success = pcall(function()
            local backpack = AutoPlaceSeed.References.Backpack
            
            if not character or not seedTool:IsA("Tool") then
                return
            end
            
            -- Unequip any currently equipped tools
            for _, tool in ipairs(character:GetChildren()) do
                if tool:IsA("Tool") and tool ~= seedTool then
                    tool.Parent = backpack
                end
            end
            
            -- Equip the seed tool
            seedTool.Parent = character
        end)
        
        if not success then
            AutoPlaceSeed.IsProcessing = false
            return false
        end
        
        task.wait(0.1)
    end
    
    -- Place seed
    local placed = AutoPlaceSeed.PlaceSeed(seedInfo, selectedSpot)
    
    if placed then
        task.wait(0.15)
    end
    
    AutoPlaceSeed.IsProcessing = false
    return placed
end

-- Process all seeds in backpack and character
function AutoPlaceSeed.ProcessAllSeeds()
    if not AutoPlaceSeed.IsRunning or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled then
        return 0
    end
    
    local placed = 0
    
    -- Check backpack
    for _, item in ipairs(AutoPlaceSeed.References.Backpack:GetChildren()) do
        if item:IsA("Tool") then
            local itemName = item.Name
            if #itemName >= 5 and string.sub(itemName, -5) == " Seed" then
                if AutoPlaceSeed.ShouldPlaceSeed(item) then
                    if AutoPlaceSeed.ProcessSeed(item) then
                        placed = placed + 1
                    end
                end
            end
        end
    end
    
    -- Check character (seeds might be equipped)
    local character = AutoPlaceSeed.References.LocalPlayer.Character
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") then
                local itemName = item.Name
                if #itemName >= 5 and string.sub(itemName, -5) == " Seed" then
                    if AutoPlaceSeed.ShouldPlaceSeed(item) then
                        if AutoPlaceSeed.ProcessSeed(item) then
                            placed = placed + 1
                        end
                    end
                end
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

-- Setup event listeners for character tool changes
function AutoPlaceSeed.SetupEventListeners()
    -- Disconnect old connections
    if AutoPlaceSeed.BackpackConnection then
        AutoPlaceSeed.BackpackConnection:Disconnect()
        AutoPlaceSeed.BackpackConnection = nil
    end
    
    -- Monitor Character for tool changes (seeds stay in character with new name)
    local character = AutoPlaceSeed.References.LocalPlayer.Character
    if character then
        AutoPlaceSeed.BackpackConnection = character.ChildAdded:Connect(function(item)
            -- OPTIMIZED: Check name first (fastest check)
            local itemName = item.Name
            if #itemName < 5 or string.sub(itemName, -5) ~= " Seed" then
                return
            end
            
            -- Then check type and state
            if not item:IsA("Tool") or not AutoPlaceSeed.Settings.AutoPlaceSeedsEnabled or not AutoPlaceSeed.IsRunning then
                return
            end
            
            -- Check if this seed is selected
            if not AutoPlaceSeed.ShouldPlaceSeed(item) then
                return
            end
            
            task.spawn(function()
                task.wait(0.1)  -- Wait for tool to fully load
                if item.Parent == character then  -- Still in character
                    AutoPlaceSeed.ProcessSeed(item)
                end
            end)
        end)
    end
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
    
    -- OPTIMIZED: Build seeds set for fast lookups
    AutoPlaceSeed.RebuildSeedsSet()
    
    -- Initial scan
    task.spawn(function()
        AutoPlaceSeed.FindAvailableSpots(true)
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
        AutoPlaceSeed.ProcessAllSeeds()
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

