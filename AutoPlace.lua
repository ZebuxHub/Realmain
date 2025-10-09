--[[
    ========================================
    🌱 AutoPlace Module - Plant Vs Brainrot
    ========================================
    
    Purpose: Automatically place plants from backpack to available plots
    Architecture: Event-driven + polling hybrid for efficiency
    
    Author: AI Assistant
    Version: 1.0.0
]]

local AutoPlace = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalPlacements = 0,
    IsProcessing = false,
    
    -- Cached Spots
    CachedSpots = {},
    SpotsCacheValid = false,
    
    -- Row Tracking (5 plant/seed limit per row)
    RowPlantCounts = {},  -- {["1"] = 3, ["2"] = 5, ...}
    MaxPlantsPerRow = 5,
    
    -- Plant Data Cache (avoid repeated ReplicatedStorage reads)
    PlantDataCache = nil,
    PlantNamesList = {},
    
    -- Auto Pick Up State
    TotalPickUps = 0,
    PlantMonitorConnections = {},
    
    -- Event Connections
    BackpackConnection = nil,
    ChildAddedConnections = {},
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

function AutoPlace.Init(services, references, settings, brain)
    AutoPlace.Services = services
    AutoPlace.References = references
    AutoPlace.Settings = settings
    AutoPlace.Brain = brain
    
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

-- Get player's owned plot number
function AutoPlace.GetOwnedPlot()
    local success, plotNum = pcall(function()
        return AutoPlace.References.LocalPlayer:GetAttribute("Plot")
    end)
    
    if success and plotNum then
        return tostring(plotNum)
    end
    
    return nil
end

-- Get all plant names from ReplicatedStorage (cached)
function AutoPlace.GetAllPlants()
    if AutoPlace.PlantDataCache then
        return AutoPlace.PlantDataCache
    end
    
    local plants = {}
    
    pcall(function()
        for _, plant in ipairs(AutoPlace.References.Plants:GetChildren()) do
            table.insert(plants, {
                Name = plant.Name,
                Damage = plant:GetAttribute("Damage") or 0
            })
        end
    end)
    
    table.sort(plants, function(a, b)
        return a.Damage > b.Damage
    end)
    
    AutoPlace.PlantDataCache = plants
    
    -- Build name list for faster lookup
    for _, plant in ipairs(plants) do
        table.insert(AutoPlace.PlantNamesList, plant.Name:lower())
    end
    
    return plants
end

-- Extract plant name from backpack item name (format: "[XX.X kg] PlantName")
local function ExtractPlantName(itemName)
    -- Pattern: "[XX.X kg] Name" -> extract "Name"
    local plantName = itemName:match("%]%s*(.+)$")
    if plantName then
        return plantName:match("^%s*(.-)%s*$") -- Trim whitespace
    end
    return itemName -- Fallback to full name
end

-- Calculate string similarity (0-1, higher = more similar)
local function StringSimilarity(str1, str2)
    str1 = str1:lower()
    str2 = str2:lower()
    
    -- Exact match
    if str1 == str2 then
        return 1.0
    end
    
    -- Length check: If difference > 50%, can't be 80% similar
    local len1, len2 = #str1, #str2
    if math.abs(len1 - len2) > math.max(len1, len2) * 0.5 then
        return 0.0
    end
    
    -- Contains check
    if str1:find(str2, 1, true) or str2:find(str1, 1, true) then
        return 0.9
    end
    
    -- Character comparison with early exit
    local matches = 0
    local minLen = math.min(len1, len2)
    local maxLen = math.max(len1, len2)
    
    for i = 1, minLen do
        if str1:sub(i, i) == str2:sub(i, i) then
            matches = matches + 1
        else
            -- Early exit: Can't reach 80% threshold
            local remaining = minLen - i
            if (matches + remaining) / maxLen < 0.8 then
                return 0.0
            end
        end
    end
    
    return matches / maxLen
end

-- Check if plant name matches any known plant (80% similarity, cached)
function AutoPlace.IsValidPlantName(itemName)
    local extractedName = ExtractPlantName(itemName)
    
    -- Ensure cache is built
    if #AutoPlace.PlantNamesList == 0 then
        AutoPlace.GetAllPlants()
    end
    
    -- Quick lookup against cached names
    for _, plantName in ipairs(AutoPlace.PlantNamesList) do
        if StringSimilarity(extractedName, plantName) >= 0.8 then
            return true
        end
    end
    
    return false
end

-- Get plant info from backpack Tool
function AutoPlace.GetPlantInfo(plantTool)
    local success, info = pcall(function()
        local itemName = plantTool.Name
        local extractedName = ExtractPlantName(itemName)
        
        return {
            Name = extractedName,
            OriginalName = itemName,
            ID = plantTool:GetAttribute("ID"),
            Damage = plantTool:GetAttribute("Damage") or 0
        }
    end)
    
    if success and info.ID then
        return info
    end
    
    return nil
end

-- Check if plant matches user's filter
function AutoPlace.ShouldPlacePlant(plantInfo)
    if not AutoPlace.Settings.AutoPlaceEnabled then
        return false
    end
    
    local selectedPlants = AutoPlace.Settings.SelectedPlants or {}
    local damageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    
    -- If specific plants selected, check if this plant is in the list
    local hasPlantFilter = #selectedPlants > 0
    local hasDamageFilter = damageFilter > 0
    
    if hasPlantFilter and hasDamageFilter then
        -- Both filters: Plant name must match AND damage >= filter
        local isSelected = table.find(selectedPlants, plantInfo.Name) ~= nil
        local meetsMinDamage = plantInfo.Damage >= damageFilter
        return isSelected and meetsMinDamage
    elseif hasPlantFilter then
        -- Only name filter: Plant must be in selected list
        return table.find(selectedPlants, plantInfo.Name) ~= nil
    elseif hasDamageFilter then
        -- Only damage filter: Plant damage >= filter
        return plantInfo.Damage >= damageFilter
    else
        -- No filter: Place all plants
        return true
    end
end

-- Count plants in a specific row
function AutoPlace.CountPlantsInRow(rowName, grass)
    local count = 0
    if grass then
        for _, child in ipairs(grass:GetChildren()) do
            if child:IsA("Model") and child.Name ~= "Floor" then
                count = count + 1
            end
        end
    end
    return count
end

-- Check if row has space for more plants (< 5)
function AutoPlace.CanPlaceInRow(rowName, grass)
    local count = AutoPlace.CountPlantsInRow(rowName, grass)
    return count < AutoPlace.MaxPlantsPerRow
end

-- Invalidate spots cache (call when CanPlace changes)
function AutoPlace.InvalidateCache()
    AutoPlace.SpotsCacheValid = false
    AutoPlace.RowPlantCounts = {}
end

-- Find all available spots in player's plot (with caching)
function AutoPlace.FindAvailableSpots(forceRescan)
    -- Return cached spots if valid and not forcing rescan
    if AutoPlace.SpotsCacheValid and not forceRescan then
        return AutoPlace.CachedSpots
    end
    
    local spots = {}
    local plotNum = AutoPlace.GetOwnedPlot()
    
    if not plotNum then
        return spots
    end
    
    local success = pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        -- Loop through all rows (sorted by name)
        local rowsList = rows:GetChildren()
        table.sort(rowsList, function(a, b)
            return tonumber(a.Name) < tonumber(b.Name)
        end)
        
        for _, row in ipairs(rowsList) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                -- Check if row has space (< 5 plants)
                if AutoPlace.CanPlaceInRow(row.Name, grass) then
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
                AutoPlace.RowPlantCounts[row.Name] = AutoPlace.CountPlantsInRow(row.Name, grass)
            end
        end
    end)
    
    -- Cache the results
    AutoPlace.CachedSpots = spots
    AutoPlace.SpotsCacheValid = true
    
    return spots
end

-- Move plant tool from backpack to character in workspace
function AutoPlace.MovePlantToCharacter(plantTool)
    local success = pcall(function()
        local character = AutoPlace.References.LocalPlayer.Character
        local backpack = AutoPlace.References.Backpack
        
        if not character or not plantTool:IsA("Tool") then
            return
        end
        
        -- Unequip any currently equipped tools
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                tool.Parent = backpack
            end
        end
        
        -- Equip the plant tool
        plantTool.Parent = character
    end)
    
    return success
end

-- Place plant at specific spot (centered)
function AutoPlace.PlacePlant(plantInfo, spot)
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
        
        AutoPlace.References.PlaceItemRemote:FireServer({
            ["ID"] = plantInfo.ID,
            ["CFrame"] = placementCFrame,
            ["Item"] = plantInfo.Name,
            ["Floor"] = spot.Floor
        })
    end)
    
    if success then
        AutoPlace.TotalPlacements = AutoPlace.TotalPlacements + 1
        
        -- Update row plant count
        if AutoPlace.RowPlantCounts[spot.RowName] then
            AutoPlace.RowPlantCounts[spot.RowName] = AutoPlace.RowPlantCounts[spot.RowName] + 1
        end
    end
    
    return success
end

-- Process single plant tool from backpack
function AutoPlace.ProcessPlant(plantTool)
    -- Wait if already processing (one by one)
    while AutoPlace.IsProcessing do
        task.wait(0.1)
    end
    
    AutoPlace.IsProcessing = true
    
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Validate plant name (80% similarity)
    local isValid = AutoPlace.IsValidPlantName(plantTool.Name)
    if not isValid then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Get plant info
    local plantInfo = AutoPlace.GetPlantInfo(plantTool)
    if not plantInfo then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Check filter
    if not AutoPlace.ShouldPlacePlant(plantInfo) then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Find available spots (uses cache)
    local spots = AutoPlace.FindAvailableSpots()
    if #spots == 0 then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Pick first available spot
    local selectedSpot = spots[1]
    
    -- Equip plant
    if not AutoPlace.MovePlantToCharacter(plantTool) then
        AutoPlace.IsProcessing = false
        return false
    end
    
    task.wait(0.1)  -- Reduced: Just enough for server sync
    
    -- Place plant
    local placed = AutoPlace.PlacePlant(plantInfo, selectedSpot)
    
    if placed then
        task.wait(0.15)  -- Reduced: Faster placement cycle
    end
    
    AutoPlace.IsProcessing = false
    return placed
end

-- Process all plants in backpack
function AutoPlace.ProcessAllPlants()
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        return 0
    end
    
    local placed = 0
    
    for _, item in ipairs(AutoPlace.References.Backpack:GetChildren()) do
        if item:IsA("Tool") then
            local success = AutoPlace.ProcessPlant(item)
            if success then
                placed = placed + 1
                task.wait(0.2) -- Small delay between placements
            end
        end
    end
    
    return placed
end

--[[
    ========================================
    Event System (Event-Driven)
    ========================================
--]]

-- Update cache incrementally when a spot becomes available/unavailable
function AutoPlace.UpdateSpotInCache(spot, isAvailable, rowName)
    if isAvailable then
        table.insert(AutoPlace.CachedSpots, {
            Floor = spot,
            CFrame = spot.CFrame,
            PivotOffset = spot.PivotOffset,
            RowName = rowName,
            SpotName = spot.Name
        })
    else
        for i, cachedSpot in ipairs(AutoPlace.CachedSpots) do
            if cachedSpot.Floor == spot then
                table.remove(AutoPlace.CachedSpots, i)
                break
            end
        end
    end
end

-- Setup Row-Level Model tracking (efficient monitoring)
function AutoPlace.SetupPlotMonitoring()
    -- Disconnect old plot attribute connections
    for _, conn in ipairs(AutoPlace.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlotAttributeConnections = {}
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then
        return
    end
    
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
                            AutoPlace.UpdateSpotInCache(spot, false, row.Name)
                            -- Update row count
                            if AutoPlace.RowPlantCounts[row.Name] then
                                AutoPlace.RowPlantCounts[row.Name] = AutoPlace.RowPlantCounts[row.Name] + 1
                            else
                                AutoPlace.RowPlantCounts[row.Name] = AutoPlace.CountPlantsInRow(row.Name, grass)
                            end
                        end
                    end
                end)
                
                local removedConn = grass.ChildRemoved:Connect(function(child)
                    if child:IsA("Model") then
                        local spot = child.Parent
                        if spot and spot:GetAttribute("CanPlace") == true then
                            AutoPlace.UpdateSpotInCache(spot, true, row.Name)
                            -- Update row count
                            if AutoPlace.RowPlantCounts[row.Name] then
                                AutoPlace.RowPlantCounts[row.Name] = math.max(0, AutoPlace.RowPlantCounts[row.Name] - 1)
                            else
                                AutoPlace.RowPlantCounts[row.Name] = AutoPlace.CountPlantsInRow(row.Name, grass)
                            end
                        end
                    end
                end)
                
                table.insert(AutoPlace.PlotAttributeConnections, addedConn)
                table.insert(AutoPlace.PlotAttributeConnections, removedConn)
            end
        end
    end)
end

function AutoPlace.SetupEventListeners()
    -- Disconnect old connections
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    for _, conn in ipairs(AutoPlace.ChildAddedConnections) do
        conn:Disconnect()
    end
    AutoPlace.ChildAddedConnections = {}
    
    -- Listen for new items added to backpack
    AutoPlace.BackpackConnection = AutoPlace.References.Backpack.ChildAdded:Connect(function(item)
        if not item:IsA("Tool") or not AutoPlace.Settings.AutoPlaceEnabled or not AutoPlace.IsRunning then
            return
        end
        
        if not AutoPlace.IsValidPlantName(item.Name) then
            return
        end
        
        task.spawn(function()
            task.wait(0.05)  -- Minimal delay for item to load
            AutoPlace.ProcessPlant(item)
        end)
    end)
end

--[[
    ========================================
    Main Control
    ========================================
--]]

function AutoPlace.Start()
    if AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = true
    
    -- Initial scan
    task.spawn(function()
        AutoPlace.FindAvailableSpots(true)
    end)
    
    -- Setup event system
    AutoPlace.SetupEventListeners()
    
    -- Setup plot monitoring
    task.spawn(function()
        task.wait(0.3)  -- Reduced: Start monitoring faster
        AutoPlace.SetupPlotMonitoring()
    end)
    
    -- Process existing plants
    task.spawn(function()
        task.wait(0.2)  -- Reduced: Process plants sooner
        AutoPlace.ProcessAllPlants()
    end)
end

function AutoPlace.Stop()
    if not AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = false
    
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    for _, conn in ipairs(AutoPlace.ChildAddedConnections) do
        conn:Disconnect()
    end
    AutoPlace.ChildAddedConnections = {}
    
    for _, conn in ipairs(AutoPlace.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlotAttributeConnections = {}
    
    AutoPlace.CachedSpots = {}
    AutoPlace.SpotsCacheValid = false
    AutoPlace.RowPlantCounts = {}
end

function AutoPlace.GetStatus()
    return {
        IsRunning = AutoPlace.IsRunning,
        AutoPlaceEnabled = AutoPlace.Settings.AutoPlaceEnabled,
        TotalPlacements = AutoPlace.TotalPlacements,
        TotalPickUps = AutoPlace.TotalPickUps,
        SelectedPlants = AutoPlace.Settings.SelectedPlants or {},
        DamageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    }
end

--[[
    ========================================
    Auto Pick Up System (Event-Driven)
    ========================================
--]]

-- Check if plant should be picked up based on damage filter
function AutoPlace.ShouldPickUpPlant(plantModel)
    if not AutoPlace.Settings.AutoPickUpEnabled then
        return false
    end
    
    local pickupFilter = AutoPlace.Settings.PickUpDamageFilter or 0
    if pickupFilter <= 0 then
        return false  -- No filter set
    end
    
    local damage = plantModel:GetAttribute("Damage") or 0
    return damage <= pickupFilter
end

-- Pick up a single plant
function AutoPlace.PickUpPlant(plantModel)
    local id = plantModel:GetAttribute("ID")
    if not id then return false end
    
    local damage = plantModel:GetAttribute("Damage") or 0
    
    local success = pcall(function()
        AutoPlace.References.RemoveItemRemote:FireServer(id)
    end)
    
    if success then
        AutoPlace.TotalPickUps = AutoPlace.TotalPickUps + 1
    end
    
    return success
end

-- Setup event-driven monitoring for planted items
function AutoPlace.SetupPickUpMonitoring()
    -- Disconnect old connections
    for _, conn in ipairs(AutoPlace.PlantMonitorConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlantMonitorConnections = {}
    
    if not AutoPlace.Settings.AutoPickUpEnabled then
        return
    end
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then return end
    
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local plants = plot:FindFirstChild("Plants")
        if not plants then return end
        
        -- Monitor existing plants
        for _, plantModel in ipairs(plants:GetChildren()) do
            if plantModel:IsA("Model") then
                -- Check immediately
                if AutoPlace.ShouldPickUpPlant(plantModel) then
                    task.spawn(function()
                        task.wait(0.1)  -- Small delay to ensure attributes loaded
                        AutoPlace.PickUpPlant(plantModel)
                    end)
                else
                    -- Monitor for Damage attribute changes
                    local conn = plantModel:GetAttributeChangedSignal("Damage"):Connect(function()
                        if AutoPlace.ShouldPickUpPlant(plantModel) then
                            AutoPlace.PickUpPlant(plantModel)
                        end
                    end)
                    table.insert(AutoPlace.PlantMonitorConnections, conn)
                end
            end
        end
        
        -- Monitor NEW plants being added
        local addedConn = plants.ChildAdded:Connect(function(plantModel)
            if not plantModel:IsA("Model") then return end
            
            task.wait(0.1)  -- Wait for attributes to load
            
            -- Check if should pick up immediately
            if AutoPlace.ShouldPickUpPlant(plantModel) then
                AutoPlace.PickUpPlant(plantModel)
            else
                -- Monitor for future damage changes
                local damageConn = plantModel:GetAttributeChangedSignal("Damage"):Connect(function()
                    if AutoPlace.ShouldPickUpPlant(plantModel) then
                        AutoPlace.PickUpPlant(plantModel)
                    end
                end)
                table.insert(AutoPlace.PlantMonitorConnections, damageConn)
            end
        end)
        
        table.insert(AutoPlace.PlantMonitorConnections, addedConn)
    end)
end

-- Start Auto Pick Up
function AutoPlace.StartPickUp()
    AutoPlace.SetupPickUpMonitoring()
end

-- Stop Auto Pick Up
function AutoPlace.StopPickUp()
    for _, conn in ipairs(AutoPlace.PlantMonitorConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlantMonitorConnections = {}
end

return AutoPlace

