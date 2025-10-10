--[[
    🌱 Plant Vs Brainrot - Auto Seed Buyer
    Made with Cascade UI
    
    This is the MAIN BRAIN 🧠 that controls everything!
    
    Features:
    - Multi-select seed filter (like egg filter in Zoo)
    - Auto-buy seeds when you have enough money
    - Track seed stock and prices
    - Config save/load/auto-load system
    - Modular AutoBuy system
--]]

print("===========================================")
print("🧠 [BRAIN] Starting Plant Vs Brainrot...")
print("===========================================")
print("⏳ Please wait while we initialize...")

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

--// References
local LocalPlayer = Players.LocalPlayer

print("✅ [BRAIN] Services loaded")

--[[
    ========================================
    Step 1: Load Modules
    ========================================
--]]
print("📦 [BRAIN] Loading AutoBuy module...")
local AutoBuy = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Realmain/refs/heads/main/AutoBuy.lua"))()
print("✅ [BRAIN] AutoBuy module loaded!")

print("📦 [BRAIN] Loading AutoPlace module...")
local AutoPlace = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Realmain/refs/heads/main/AutoPlace.lua"))()
print("✅ [BRAIN] AutoPlace module loaded!")

print("📦 [BRAIN] Loading AutoPlaceSeed module...")
local AutoPlaceSeed = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Realmain/refs/heads/main/AutoPlaceSeed.lua"))()
print("✅ [BRAIN] AutoPlaceSeed module loaded!")

print("📦 [BRAIN] Loading Information module...")
local Information = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Realmain/refs/heads/main/Information.lua"))()
print("✅ [BRAIN] Information module loaded!")

--[[
    ========================================
    Step 2: Load Cascade UI from GitHub
    ========================================
--]]
print("📦 [BRAIN] Loading Cascade UI from GitHub...")
local cascade = loadstring(game:HttpGet("https://github.com/biggaboy212/Cascade/releases/download/v1.0.0/dist.luau"))()
print("✅ [BRAIN] Cascade UI loaded successfully!")

--[[
    ========================================
    Step 3: Wait for Game Assets
    ========================================
--]]
print("⏳ [BRAIN] Waiting for game assets...")
local Seeds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Seeds")
local Plants = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Plants")
local Gears = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gears")
local BuyItemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyItem")
local BuyGearRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyGear")
local PlaceItemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaceItem")
local RemoveItemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoveItem")
print("✅ [BRAIN] Game assets loaded!")

--[[
    ========================================
    Step 3: Setup Config Folders
    ========================================
--]]
local ConfigFolderPath = "Zebux/Plant Vs Brainrot/Config"
local SettingsFolderPath = "Zebux/Plant Vs Brainrot"

-- Create folders
if not isfolder("Zebux") then
    makefolder("Zebux")
end
if not isfolder("Zebux/Plant Vs Brainrot") then
    makefolder("Zebux/Plant Vs Brainrot")
end
if not isfolder(ConfigFolderPath) then
    makefolder(ConfigFolderPath)
end

print("✅ Config folders created at:", ConfigFolderPath)

--[[
    ========================================
    Step 4: Settings Structure
    ========================================
--]]
local Settings = {
    -- Auto Buy
    AutoBuyEnabled = false,
    SelectedSeeds = {},
    -- Auto Buy Gear
    AutoBuyGearEnabled = false,
    SelectedGears = {},
    -- Auto Place Seeds
    AutoPlaceSeedsEnabled = false,
    SelectedSeedsToPlace = {},
    -- Auto Place Plants
    AutoPlaceEnabled = false,
    SelectedPlants = {},
    PlantDamageFilter = 0,
    -- Auto Pick Up
    AutoPickUpEnabled = false,
    PickUpDamageFilter = 0,
    -- Config system
    CurrentConfig = "Default",
    AutoLoadEnabled = false,
    LastLoadedConfig = "Default"
}

--[[
    ========================================
    Step 5: Config Management Functions
    ========================================
--]]

-- Get all config files
local function GetAllConfigs()
    local configs = {}
    
    if isfolder(ConfigFolderPath) then
        local files = listfiles(ConfigFolderPath)
        
        for _, filePath in ipairs(files) do
            local fileName = filePath:match("([^/\\]+)%.json$")
            if fileName then
                table.insert(configs, fileName)
            end
        end
    end
    
    -- Sort alphabetically
    table.sort(configs)
    
    -- Always include Default if not present
    if #configs == 0 or not table.find(configs, "Default") then
        table.insert(configs, 1, "Default")
    end
    
    return configs
end

-- Save config to file
local function SaveConfig(configName)
    local success, err = pcall(function()
        local configData = {
            AutoBuyEnabled = Settings.AutoBuyEnabled,
            SelectedSeeds = Settings.SelectedSeeds,
            AutoBuyGearEnabled = Settings.AutoBuyGearEnabled,
            SelectedGears = Settings.SelectedGears,
            AutoPlaceSeedsEnabled = Settings.AutoPlaceSeedsEnabled,
            SelectedSeedsToPlace = Settings.SelectedSeedsToPlace,
            AutoPlaceEnabled = Settings.AutoPlaceEnabled,
            SelectedPlants = Settings.SelectedPlants,
            PlantDamageFilter = Settings.PlantDamageFilter,
            AutoPickUpEnabled = Settings.AutoPickUpEnabled,
            PickUpDamageFilter = Settings.PickUpDamageFilter
        }
        
        local json = HttpService:JSONEncode(configData)
        local filePath = ConfigFolderPath .. "/" .. configName .. ".json"
        writefile(filePath, json)
        print("✅ Config saved:", configName)
    end)
    
    if not success then
        print("❌ Failed to save config:", err)
    end
    
    return success
end

-- Load config from file
local function LoadConfig(configName)
    local filePath = ConfigFolderPath .. "/" .. configName .. ".json"
    
    if not isfile(filePath) then
        print("⚠️ Config not found:", configName)
        return false
    end
    
    local success, err = pcall(function()
        local json = readfile(filePath)
        local configData = HttpService:JSONDecode(json)
        
        -- Load config data into Settings
        Settings.AutoBuyEnabled = configData.AutoBuyEnabled or false
        Settings.SelectedSeeds = configData.SelectedSeeds or {}
        Settings.AutoBuyGearEnabled = configData.AutoBuyGearEnabled or false
        Settings.SelectedGears = configData.SelectedGears or {}
        Settings.AutoPlaceSeedsEnabled = configData.AutoPlaceSeedsEnabled or false
        Settings.SelectedSeedsToPlace = configData.SelectedSeedsToPlace or {}
        Settings.AutoPlaceEnabled = configData.AutoPlaceEnabled or false
        Settings.SelectedPlants = configData.SelectedPlants or {}
        Settings.PlantDamageFilter = configData.PlantDamageFilter or 0
        Settings.AutoPickUpEnabled = configData.AutoPickUpEnabled or false
        Settings.PickUpDamageFilter = configData.PickUpDamageFilter or 0
        Settings.CurrentConfig = configName
        
        print("✅ Config loaded:", configName)
        print("  - Auto Buy:", Settings.AutoBuyEnabled and "ON" or "OFF")
        print("  - Selected Seeds:", #Settings.SelectedSeeds == 0 and "All" or #Settings.SelectedSeeds)
        
        return true
    end)
    
    if not success then
        print("❌ Failed to load config:", err)
        return false
    end
    
    return success
end

-- Delete config file
local function DeleteConfig(configName)
    if configName == "Default" then
        print("⚠️ Cannot delete Default config")
        return false
    end
    
    local filePath = ConfigFolderPath .. "/" .. configName .. ".json"
    
    if not isfile(filePath) then
        print("⚠️ Config not found:", configName)
        return false
    end
    
    local success, err = pcall(function()
        delfile(filePath)
        print("✅ Config deleted:", configName)
    end)
    
    if not success then
        print("❌ Failed to delete config:", err)
    end
    
    return success
end

-- Save settings (auto-load preference)
local function SaveSettings()
    local success, err = pcall(function()
        local settingsData = {
            AutoLoadEnabled = Settings.AutoLoadEnabled,
            LastLoadedConfig = Settings.LastLoadedConfig
        }
        
        local json = HttpService:JSONEncode(settingsData)
        local filePath = SettingsFolderPath .. "/settings.json"
        writefile(filePath, json)
    end)
    
    return success
end

-- Load settings (auto-load preference)
local function LoadSettings()
    local filePath = SettingsFolderPath .. "/settings.json"
    
    if not isfile(filePath) then
        return false
    end
    
    local success, err = pcall(function()
        local json = readfile(filePath)
        local settingsData = HttpService:JSONDecode(json)
        
        Settings.AutoLoadEnabled = settingsData.AutoLoadEnabled or false
        Settings.LastLoadedConfig = settingsData.LastLoadedConfig or "Default"
        
        print("✅ Settings loaded")
        print("  - Auto Load:", Settings.AutoLoadEnabled and "ON" or "OFF")
        print("  - Last Config:", Settings.LastLoadedConfig)
    end)
    
    return success
end

--[[
    ========================================
    Step 6: Load Initial Settings
    ========================================
--]]
print("📂 Loading settings...")
LoadSettings()

-- Auto-load last config if enabled
if Settings.AutoLoadEnabled and Settings.LastLoadedConfig then
    print("🔄 Auto-loading config:", Settings.LastLoadedConfig)
    LoadConfig(Settings.LastLoadedConfig)
else
    print("⚠️ Auto-load disabled, using default settings")
end

--[[
    ========================================
    Step 7: Helper Functions
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
    Step 8: Initialize AutoBuy Module
    ========================================
--]]

print("[BRAIN] Initializing AutoBuy module...")

-- Prepare services for AutoBuy
local services = {
    Players = Players,
    ReplicatedStorage = ReplicatedStorage,
    HttpService = HttpService
}

-- Prepare references for AutoBuy
local references = {
    LocalPlayer = LocalPlayer,
    Seeds = Seeds,
    Gears = Gears,
    BuyItemRemote = BuyItemRemote,
    BuyGearRemote = BuyGearRemote
}

-- Prepare references for AutoPlace
local autoPlaceReferences = {
    LocalPlayer = LocalPlayer,
    Plants = Plants,
    Backpack = LocalPlayer:WaitForChild("Backpack"),
    PlaceItemRemote = PlaceItemRemote,
    RemoveItemRemote = RemoveItemRemote
}

--[[
    ========================================
    Step 8: Central Brain System 🧠
    ========================================
    This is the main controller that coordinates everything!
--]]

local Brain = {
    -- UI References
    UI = {
        ConfigNameInput = nil,
        ConfigDropdown = nil,
        AutoLoadToggle = nil,
        MoneyLabel = nil,
        SeedStatusLabel = nil,
        SeedPullDown = nil,
        AutoBuyToggle = nil,
        SeedInfoLabels = {},
        SeedPlaceStatusLabel = nil,
        SeedPlacePullDown = nil,
        PlantStatusLabel = nil,
        PlantPullDown = nil,
        PlantDamageFilter = nil,
        PickUpDamageFilter = nil
    },
    
    -- State
    IsRunning = false,
    LastCheckTime = 0,
    
    -- Module References
    AutoBuy = nil,
    AutoPlace = nil,
    
    -- Methods
    UpdateMoney = nil,
    UpdateSeedSelection = nil,
    UpdatePlantSelection = nil,
    RefreshConfigDropdown = nil,
    StartAutoBuy = nil,
    StopAutoBuy = nil,
    StartAutoPlace = nil,
    StopAutoPlace = nil
}

-- Brain Method: Update Money Display
function Brain.UpdateMoney()
    if Brain.UI.MoneyLabel then
        local money = AutoBuy.GetMoney()
        Brain.UI.MoneyLabel.Text = "$" .. FormatNumber(money)
    end
end

-- Brain Method: Update Seed Selection Display
function Brain.UpdateSeedSelection()
    if Brain.UI.SeedStatusLabel then
        if #Settings.SelectedSeeds == 0 then
            Brain.UI.SeedStatusLabel.Text = "All Seeds"
        else
            Brain.UI.SeedStatusLabel.Text = #Settings.SelectedSeeds .. " selected"
        end
    end
end

function Brain.UpdateGearSelection()
    if Brain.UI.GearStatusLabel then
        if #Settings.SelectedGears == 0 then
            Brain.UI.GearStatusLabel.Text = "All Gears"
        else
            Brain.UI.GearStatusLabel.Text = #Settings.SelectedGears .. " selected"
        end
    end
end

-- Brain Method: Update Plant Selection Display
function Brain.UpdatePlantSelection()
    if Brain.UI.PlantStatusLabel then
        local hasNameFilter = #Settings.SelectedPlants > 0
        local hasDamageFilter = Settings.PlantDamageFilter > 0
        
        if not hasNameFilter and not hasDamageFilter then
            Brain.UI.PlantStatusLabel.Text = "All Plants"
        elseif hasNameFilter and hasDamageFilter then
            Brain.UI.PlantStatusLabel.Text = #Settings.SelectedPlants .. " plants, DMG≥" .. FormatNumber(Settings.PlantDamageFilter)
        elseif hasNameFilter then
            Brain.UI.PlantStatusLabel.Text = #Settings.SelectedPlants .. " selected"
        else
            Brain.UI.PlantStatusLabel.Text = "DMG≥" .. FormatNumber(Settings.PlantDamageFilter)
        end
    end
end

-- Brain Method: Refresh Config Dropdown
function Brain.RefreshConfigDropdown()
    if not Brain.UI.ConfigDropdown then return end
    
    local newConfigs = GetAllConfigs()
    
    -- Clear old options
    for i = #Brain.UI.ConfigDropdown.Options, 1, -1 do
        pcall(function()
            Brain.UI.ConfigDropdown:Remove(i)
        end)
    end
    
    -- Add new options
    for _, cfg in ipairs(newConfigs) do
        Brain.UI.ConfigDropdown:Option(cfg)
    end
end

-- Brain Method: Start Auto-Buy System
function Brain.StartAutoBuy()
    Brain.IsRunning = true
    AutoBuy.Start()
    print("🧠 [BRAIN] Auto-buy system STARTED")
end

-- Brain Method: Stop Auto-Buy System
function Brain.StopAutoBuy()
    Brain.IsRunning = false
    AutoBuy.Stop()
    print("🧠 [BRAIN] Auto-buy system STOPPED")
end

-- Brain Method: Start Auto-Place System
function Brain.StartAutoPlace()
    AutoPlace.Start()
    print("🧠 [BRAIN] Auto-place system STARTED")
end

-- Brain Method: Stop Auto-Place System
function Brain.StopAutoPlace()
    AutoPlace.Stop()
    print("🧠 [BRAIN] Auto-place system STOPPED")
end

--- Brain Method: Start Auto-Place Seeds
function Brain.StartAutoPlaceSeeds()
    AutoPlaceSeed.Start()
    print("🧠 [BRAIN] Auto-place seeds system STARTED")
end

--- Brain Method: Stop Auto-Place Seeds
function Brain.StopAutoPlaceSeeds()
    AutoPlaceSeed.Stop()
    print("🧠 [BRAIN] Auto-place seeds system STOPPED")
end

--- Brain Method: Start Auto-Pick Up
function Brain.StartAutoPickUp()
    if not AutoPlace.IsRunning then
        AutoPlace.Start()
    end
    AutoPlace.StartPickUp()
    print("🧠 [BRAIN] Auto-pickup system STARTED")
end

--- Brain Method: Stop Auto-Pick Up
function Brain.StopAutoPickUp()
    AutoPlace.StopPickUp()
    print("🧠 [BRAIN] Auto-pickup system STOPPED")
end

-- Initialize AutoBuy Module with Brain reference
AutoBuy.Init(services, references, Settings, Brain)
Brain.AutoBuy = AutoBuy

-- Initialize AutoPlace Module with Brain reference
AutoPlace.Init(services, autoPlaceReferences, Settings, Brain)
Brain.AutoPlace = AutoPlace

-- Initialize AutoPlaceSeed Module with Brain reference
AutoPlaceSeed.Init(services, autoPlaceReferences, Settings, Brain)
Brain.AutoPlaceSeed = AutoPlaceSeed

-- Initialize Information Module with Brain reference
local infoReferences = {
    LocalPlayer = LocalPlayer,
    Seeds = Seeds,
    Gears = Gears
}
Information.Init(services, infoReferences, Brain, AutoBuy)
Brain.Information = Information

print("✅ [BRAIN] Brain system initialized with modules!")

--[[
    ========================================
    Step 9: Create the UI Window
    ========================================
--]]
print("🎨 Creating UI...")

local app = cascade.New({
    WindowPill = true,
    Theme = cascade.Themes.Dark,
})

local window = app:Window({
    Title = "🌱 Plant Vs Brainrot",
    Subtitle = "Auto Seed Buyer",
    Size = UserInputService.TouchEnabled and UDim2.fromOffset(500, 450) or UDim2.fromOffset(700, 550),
    Draggable = true,
    Resizable = false,  -- Must be false for sharp rendering
    Dropshadow = true,
})

-- Press RightControl to minimize
UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
    if input.KeyCode == Enum.KeyCode.RightControl and not gameProcessedEvent then
        window.Minimized = not window.Minimized
    end
end)

local section = window:Section({
    Title = "Seed Manager"
})

--[[
    ========================================
    Step 10: Auto Buy Tab (Connected to Brain 🧠)
    ========================================
--]]

local mainTab = section:Tab({
    Title = "Auto Buy",
    Icon = cascade.Symbols.leaf,
    Selected = true,
})

do
    local form = mainTab:PageSection({ 
        Title = "Auto Buy Seeds",
        Subtitle = "Automatic seed purchasing"
    }):Form()
    
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Select Seeds",
        Subtitle = "Empty = buy all seeds",
    })
    
    local seedList = AutoBuy.GetAllSeeds()
    
    -- Create status label showing how many selected
    Brain.UI.SeedStatusLabel = row:Right():Label({
        Text = #Settings.SelectedSeeds == 0 and "All Seeds" or #Settings.SelectedSeeds .. " selected"
    })
    
    Brain.UI.SeedPullDown = row:Right():PullDownButton({
        Options = seedList,
        ValueChanged = function(self, value)
            local seedName = self.Options[value]
            
            local index = table.find(Settings.SelectedSeeds, seedName)
            local optionFrame = self.Structures.Options[value]
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if index then
                -- Deselect: remove from list
                table.remove(Settings.SelectedSeeds, index)
                print("Brain: Removed seed:", seedName)
                
                -- Remove highlight
                if optionFrame then
                    optionFrame.BackgroundTransparency = 1
                    if label then
                        label.TextColor3 = self.Theme.Text.Primary[1].Value
                        label.TextTransparency = self.Theme.Text.Primary[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", false)
                end
            else
                -- Select: add to list
                table.insert(Settings.SelectedSeeds, seedName)
                print("Brain: Added seed:", seedName)
                
                -- Add highlight
                if optionFrame then
                    optionFrame.BackgroundTransparency = self.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = self.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = self.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
            end
            
            -- Brain: Update status label
            Brain.UpdateSeedSelection()
            
            print("Brain: Selected seeds:", #Settings.SelectedSeeds == 0 and "All" or table.concat(Settings.SelectedSeeds, ", "))
        end,
    })
    
    -- Apply initial highlights for already selected seeds
    task.spawn(function()
        task.wait(0.1)
        
        for i, seedName in ipairs(seedList) do
            local optionFrame = Brain.UI.SeedPullDown.Structures.Options[i]
            if not optionFrame then
                task.wait(0.05)
                optionFrame = Brain.UI.SeedPullDown.Structures.Options[i]
            end
            
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if optionFrame then
                -- Apply initial highlight if selected
                if table.find(Settings.SelectedSeeds, seedName) then
                    optionFrame.BackgroundTransparency = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
                
                -- Maintain highlight on hover
                optionFrame:GetPropertyChangedSignal("GuiState"):Connect(function()
                    task.defer(function()
                        local isSelected = optionFrame:GetAttribute("IsSelected")
                        if isSelected then
                            optionFrame.BackgroundTransparency = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocused[2].Value
                            if label then
                                label.TextColor3 = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                                label.TextTransparency = Brain.UI.SeedPullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                            end
                        end
                    end)
                end)
            end
        end
    end)
    
    -- Auto Buy Toggle
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Auto Buy",
        Subtitle = "Buy when money & stock available",
    })
    
    Brain.UI.AutoBuyToggle = row:Right():Toggle({
        Value = Settings.AutoBuyEnabled,
        ValueChanged = function(self, value)
            Settings.AutoBuyEnabled = value
            
            if value then
                -- Brain: Start auto-buy
                Brain.StartAutoBuy()
                print("Brain: Auto-buy ENABLED")
                if #Settings.SelectedSeeds == 0 then
                    print("   - Buying: ALL seeds")
                else
                    print("   - Buying:", table.concat(Settings.SelectedSeeds, ", "))
                end
            else
                -- Brain: Stop auto-buy
                Brain.StopAutoBuy()
                print("Brain: Auto-buy DISABLED")
            end
        end,
    })
end

--- Auto Buy Gear Section
do
    local form = mainTab:PageSection({ 
        Title = "Auto Buy Gear",
        Subtitle = "Automatic gear purchasing"
    }):Form()
    
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Select Gears",
        Subtitle = "Empty = buy all gears",
    })
    
    local gearList = AutoBuy.GetAllGears()
    
    -- Create status label showing how many selected
    Brain.UI.GearStatusLabel = row:Right():Label({
        Text = #Settings.SelectedGears == 0 and "All Gears" or #Settings.SelectedGears .. " selected"
    })
    
    Brain.UI.GearPullDown = row:Right():PullDownButton({
        Options = gearList,
        ValueChanged = function(self, value)
            local gearName = self.Options[value]
            
            local index = table.find(Settings.SelectedGears, gearName)
            local optionFrame = self.Structures.Options[value]
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if index then
                -- Deselect: remove from list
                table.remove(Settings.SelectedGears, index)
                print("Brain: Removed gear:", gearName)
                
                -- Remove highlight
                if optionFrame then
                    optionFrame.BackgroundTransparency = 1
                    if label then
                        label.TextColor3 = self.Theme.Text.Primary[1].Value
                        label.TextTransparency = self.Theme.Text.Primary[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", false)
                end
            else
                -- Select: add to list
                table.insert(Settings.SelectedGears, gearName)
                print("Brain: Added gear:", gearName)
                
                -- Add highlight
                if optionFrame then
                    optionFrame.BackgroundTransparency = self.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = self.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = self.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
            end
            
            -- Brain: Update status label
            Brain.UpdateGearSelection()
            
            print("Brain: Selected gears:", #Settings.SelectedGears == 0 and "All" or table.concat(Settings.SelectedGears, ", "))
        end,
    })
    
    -- Apply initial highlights for already selected gears
    task.spawn(function()
        task.wait(0.1)
        
        for i, gearName in ipairs(gearList) do
            local optionFrame = Brain.UI.GearPullDown.Structures.Options[i]
            if not optionFrame then
                task.wait(0.05)
                optionFrame = Brain.UI.GearPullDown.Structures.Options[i]
            end
            
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if optionFrame then
                -- Apply initial highlight if selected
                if table.find(Settings.SelectedGears, gearName) then
                    optionFrame.BackgroundTransparency = Brain.UI.GearPullDown.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = Brain.UI.GearPullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = Brain.UI.GearPullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
            end
        end
    end)
    
    -- Auto Buy Gear Toggle
    local row2 = form:Row()
    
    row2:Left():TitleStack({
        Title = "Auto Buy Gear",
        Subtitle = "Buy when money & stock available",
    })
    
    row2:Right():Toggle({
        Value = Settings.AutoBuyGearEnabled,
        ValueChanged = function(self, value)
            Settings.AutoBuyGearEnabled = value
            
            if value then
                print("Brain: Auto-buy gear ENABLED")
                if #Settings.SelectedGears == 0 then
                    print("   - Buying: ALL gears")
                else
                    print("   - Buying:", table.concat(Settings.SelectedGears, ", "))
                end
                
                -- Start AutoBuy system if not running (needed for IsRunning flag)
                if not AutoBuy.IsRunning then
                    Brain.StartAutoBuy()
                end
                
                -- Start buying gears immediately
                task.wait(0.05)
                AutoBuy.BuyGearsUntilDone()
            else
                print("Brain: Auto-buy gear DISABLED")
            end
        end,
    })
end

--[[
    ========================================
    Step 11: Auto Place Tab
    ========================================
--]]

local autoPlaceTab = section:Tab({
    Title = "Auto Place",
    Icon = cascade.Symbols.square,
})

-- Auto Place Seeds Section
do
    local form = autoPlaceTab:PageSection({ 
        Title = "Auto Place Seeds",
        Subtitle = "Place seeds to available plots"
    }):Form()
    
    -- Seed Selection
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Select Seeds",
        Subtitle = "Choose which seeds to auto place",
    })
    
    local seedData = {}
    for _, seed in ipairs(Seeds:GetChildren()) do
        local seedName = seed.Name
        local price = seed:GetAttribute("Price") or 0
        table.insert(seedData, {
            Name = seedName,
            Price = price
        })
    end
    
    table.sort(seedData, function(a, b)
        return a.Price < b.Price
    end)
    
    local seedOptions = {}
    for _, seed in ipairs(seedData) do
        table.insert(seedOptions, seed.Name .. " ($" .. FormatNumber(seed.Price) .. ")")
    end
    
    -- Create status label for seeds
    Brain.UI.SeedPlaceStatusLabel = row:Right():Label({
        Text = "All Seeds"
    })
    
    Brain.UI.SeedPlacePullDown = row:Right():PullDownButton({
        Options = seedOptions,
        ValueChanged = function(self, value)
            local selectedSeed = seedData[value]
            if not selectedSeed then return end
            
            local seedName = selectedSeed.Name
            local index = table.find(Settings.SelectedSeedsToPlace, seedName)
            local optionFrame = self.Structures.Options[value]
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if index then
                -- Deselect
                table.remove(Settings.SelectedSeedsToPlace, index)
                print("Brain: Removed seed from placement:", seedName)
                
                pcall(function()
                    if optionFrame then
                        optionFrame.BackgroundTransparency = 1
                        if label then
                            label.TextColor3 = self.Theme.Text.Primary[1].Value
                            label.TextTransparency = self.Theme.Text.Primary[2].Value
                        end
                        optionFrame:SetAttribute("IsSelected", false)
                    end
                end)
            else
                -- Select
                table.insert(Settings.SelectedSeedsToPlace, seedName)
                print("Brain: Added seed to placement:", seedName, "| Price:", FormatNumber(selectedSeed.Price))
                
                pcall(function()
                    if optionFrame then
                        optionFrame.BackgroundTransparency = self.Theme.Controls.SelectionFocused[2].Value
                        if label then
                            label.TextColor3 = self.Theme.Controls.SelectionFocusedAccent[1].Value
                            label.TextTransparency = self.Theme.Controls.SelectionFocusedAccent[2].Value
                        end
                        optionFrame:SetAttribute("IsSelected", true)
                    end
                end)
            end
            
            -- OPTIMIZED: Rebuild seeds set for O(1) lookups
            pcall(function()
                if Brain.AutoPlaceSeed and Brain.AutoPlaceSeed.RebuildSeedsSet then
                    Brain.AutoPlaceSeed.RebuildSeedsSet()
                    
                    -- Auto-restart if running (no need to retoggle)
                    if Settings.AutoPlaceSeedsEnabled and Brain.AutoPlaceSeed.IsRunning then
                        Brain.AutoPlaceSeed.Stop()
                        task.wait(0.05)
                        Brain.AutoPlaceSeed.Start()
                    end
                end
            end)
            
            -- Update status label
            if #Settings.SelectedSeedsToPlace == 0 then
                Brain.UI.SeedPlaceStatusLabel.Text = "All Seeds"
            else
                Brain.UI.SeedPlaceStatusLabel.Text = #Settings.SelectedSeedsToPlace .. " selected"
            end
        end,
    })
    
    -- Apply initial highlights
    task.spawn(function()
        task.wait(0.1)
        
        for i, seed in ipairs(seedData) do
            local optionFrame = Brain.UI.SeedPlacePullDown.Structures.Options[i]
            if not optionFrame then
                task.wait(0.05)
                optionFrame = Brain.UI.SeedPlacePullDown.Structures.Options[i]
            end
            
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if optionFrame then
                if table.find(Settings.SelectedSeedsToPlace, seed.Name) then
                    optionFrame.BackgroundTransparency = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
                
                optionFrame:GetPropertyChangedSignal("GuiState"):Connect(function()
                    task.defer(function()
                        local isSelected = optionFrame:GetAttribute("IsSelected")
                        if isSelected then
                            optionFrame.BackgroundTransparency = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocused[2].Value
                            if label then
                                label.TextColor3 = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                                label.TextTransparency = Brain.UI.SeedPlacePullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                            end
                        end
                    end)
                end)
            end
        end
    end)
    
    -- Auto Place Seeds Toggle
    local row2 = form:Row()
    
    row2:Left():TitleStack({
        Title = "Auto Place Seeds",
        Subtitle = "Place selected seeds automatically",
    })
    
    row2:Right():Toggle({
        Value = Settings.AutoPlaceSeedsEnabled,
        ValueChanged = function(self, value)
            Settings.AutoPlaceSeedsEnabled = value
            
            if value then
                print("Brain: Auto-place seeds ENABLED")
                if #Settings.SelectedSeedsToPlace > 0 then
                    print("   - Placing:", table.concat(Settings.SelectedSeedsToPlace, ", "))
                else
                    print("   - No seeds selected!")
                end
                Brain.StartAutoPlaceSeeds()
            else
                print("Brain: Auto-place seeds DISABLED")
                Brain.StopAutoPlaceSeeds()
            end
        end,
    })
end

-- Auto Place Plants Section
do
    local form = autoPlaceTab:PageSection({ 
        Title = "Auto Place Plants",
        Subtitle = "Automatic plant placement"
    }):Form()
    
    -- Plant Selection
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Select Plants",
        Subtitle = "Empty = place all plants",
    })
    
    local plantData = AutoPlace.GetAllPlants()
    local plantOptions = {}
    for _, plant in ipairs(plantData) do
        table.insert(plantOptions, plant.Name .. " (DMG: " .. FormatNumber(plant.Damage) .. ")")
    end
    
    -- Create status label
    Brain.UI.PlantStatusLabel = row:Right():Label({
        Text = "All Plants"
    })
    
    Brain.UI.PlantPullDown = row:Right():PullDownButton({
        Options = plantOptions,
        ValueChanged = function(self, value)
            local selectedPlant = plantData[value]
            if not selectedPlant then return end
            
            local plantName = selectedPlant.Name
            local index = table.find(Settings.SelectedPlants, plantName)
            local optionFrame = self.Structures.Options[value]
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if index then
                -- Deselect
                table.remove(Settings.SelectedPlants, index)
                print("Brain: Removed plant:", plantName)
                
                if optionFrame then
                    optionFrame.BackgroundTransparency = 1
                    if label then
                        label.TextColor3 = self.Theme.Text.Primary[1].Value
                        label.TextTransparency = self.Theme.Text.Primary[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", false)
                end
            else
                -- Select
                table.insert(Settings.SelectedPlants, plantName)
                print("Brain: Added plant:", plantName, "| DMG:", FormatNumber(selectedPlant.Damage))
                
                if optionFrame then
                    optionFrame.BackgroundTransparency = self.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = self.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = self.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
            end
            
            -- OPTIMIZED: Rebuild plants set for O(1) lookups
            pcall(function()
                if Brain.AutoPlace and Brain.AutoPlace.RebuildPlantsSet then
                    Brain.AutoPlace.RebuildPlantsSet()
                    
                    -- Auto-restart if running (no need to retoggle)
                    if Settings.AutoPlaceEnabled and Brain.AutoPlace.IsRunning then
                        Brain.AutoPlace.Stop()
                        task.wait(0.05)
                        Brain.AutoPlace.Start()
                    end
                end
            end)
            
            Brain.UpdatePlantSelection()
        end,
    })
    
    -- Apply initial highlights
    task.spawn(function()
        task.wait(0.1)
        
        for i, plant in ipairs(plantData) do
            local optionFrame = Brain.UI.PlantPullDown.Structures.Options[i]
            if not optionFrame then
                task.wait(0.05)
                optionFrame = Brain.UI.PlantPullDown.Structures.Options[i]
            end
            
            local label = optionFrame and optionFrame:FindFirstChild("Label")
            
            if optionFrame then
                if table.find(Settings.SelectedPlants, plant.Name) then
                    optionFrame.BackgroundTransparency = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocused[2].Value
                    if label then
                        label.TextColor3 = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                        label.TextTransparency = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                    end
                    optionFrame:SetAttribute("IsSelected", true)
                end
                
                optionFrame:GetPropertyChangedSignal("GuiState"):Connect(function()
                    task.defer(function()
                        local isSelected = optionFrame:GetAttribute("IsSelected")
                        if isSelected then
                            optionFrame.BackgroundTransparency = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocused[2].Value
                            if label then
                                label.TextColor3 = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocusedAccent[1].Value
                                label.TextTransparency = Brain.UI.PlantPullDown.Theme.Controls.SelectionFocusedAccent[2].Value
                            end
                        end
                    end)
                end)
            end
        end
    end)
    
    -- Damage Filter
    local row2 = form:Row()
    
    row2:Left():TitleStack({
        Title = "Minimum Damage",
        Subtitle = "Only place plants with damage ≥ this value | o = no filter",
    })
    
    Brain.UI.PlantDamageFilter = row2:Right():Stepper({
        Value = Settings.PlantDamageFilter,
        Minimum = 0,
        Maximum = 1000000,
        Step = 100,
        Fielded = true,
        ValueChanged = function(self, value)
            Settings.PlantDamageFilter = value
            Brain.UpdatePlantSelection()
            print("Brain: Damage filter set to:", FormatNumber(value))
            
            -- Auto-restart if running (no need to retoggle)
            if Settings.AutoPlaceEnabled and Brain.AutoPlace and Brain.AutoPlace.IsRunning then
                print("Brain: Auto-restarting auto-place with new filter...")
                Brain.AutoPlace.Stop()
                task.wait(0.05)
                Brain.AutoPlace.Start()
            end
        end,
    })
    
    -- Auto Place Toggle
    local row3 = form:Row()
    
    row3:Left():TitleStack({
        Title = "Auto Place",
        Subtitle = "Place when added to backpack",
    })
    
    row3:Right():Toggle({
        Value = Settings.AutoPlaceEnabled,
        ValueChanged = function(self, value)
            Settings.AutoPlaceEnabled = value
            
            if value then
                Brain.StartAutoPlace()
                print("Brain: Auto-place ENABLED")
                local filterInfo = {}
                if #Settings.SelectedPlants > 0 then
                    table.insert(filterInfo, #Settings.SelectedPlants .. " plants")
                end
                if Settings.PlantDamageFilter > 0 then
                    table.insert(filterInfo, "DMG≥" .. FormatNumber(Settings.PlantDamageFilter))
                end
                if #filterInfo == 0 then
                    print("   - Placing: ALL plants")
                else
                    print("   - Filter:", table.concat(filterInfo, ", "))
                end
            else
                Brain.StopAutoPlace()
                print("Brain: Auto-place DISABLED")
            end
        end,
    })
end

-- Auto Pick Up Section
do
    local form = autoPlaceTab:PageSection({ 
        Title = "Auto Pick Up Plants",
        Subtitle = "Automatically pick up placed plants"
    }):Form()
    
    -- Pick Up Damage Filter
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Maximum Damage",
        Subtitle = "Pick up plants with damage ≤ this value | 0 = no filter",
    })
    
    Brain.UI.PickUpDamageFilter = row:Right():Stepper({
        Value = Settings.PickUpDamageFilter or 0,
        Minimum = 0,
        Maximum = 1000000,
        Step = 100,
        Fielded = true,
        ValueChanged = function(self, value)
            Settings.PickUpDamageFilter = value
            print("Brain: Pick up damage filter set to:", FormatNumber(value))
            
            -- Auto-restart if running (no need to retoggle)
            if Settings.AutoPickUpEnabled and Brain.AutoPlace and Brain.AutoPlace.IsRunning then
                print("Brain: Auto-restarting pick-up with new filter...")
                Brain.StopAutoPickUp()
                task.wait(0.05)
                Brain.StartAutoPickUp()
            end
        end,
    })
    
    -- Auto Pick Up Toggle
    local row2 = form:Row()
    
    row2:Left():TitleStack({
        Title = "Auto Pick Up",
        Subtitle = "Remove low damage plants automatically",
    })
    
    row2:Right():Toggle({
        Value = Settings.AutoPickUpEnabled,
        ValueChanged = function(self, value)
            Settings.AutoPickUpEnabled = value
            
            if value then
                print("Brain: Auto-pickup ENABLED")
                if Settings.PickUpDamageFilter > 0 then
                    print("   - Picking up: DMG≤" .. FormatNumber(Settings.PickUpDamageFilter))
                else
                    print("   - No filter set (won't pick up any plants)")
                end
                Brain.StartAutoPickUp()
            else
                print("Brain: Auto-pickup DISABLED")
                Brain.StopAutoPickUp()
            end
        end,
    })
end

--[[
    ========================================
    Step 12: Information Tab
    ========================================
--]]

local infoTab = section:Tab({
    Title = "Information",
    Icon = cascade.Symbols.chartBar,
})

-- Setup Information tab using Information module
Information.Setup(infoTab)

--[[
    ========================================
    Step 13: Config Tab (Connected to Brain 🧠)
    ========================================
--]]

local configTab = section:Tab({
    Title = "Config",
    Icon = cascade.Symbols.gearshape,
})

do
    local form = configTab:PageSection({ 
        Title = "Config Management",
        Subtitle = "Save and load settings"
    }):Form()
    
    -- Config Name Input
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Config Name",
            Subtitle = "Name for new config",
        })
        
        Brain.UI.ConfigNameInput = row:Right():TextField({
            Placeholder = "Enter config name...",
            Value = "",
        })
    end
    
    -- Create Button
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Create Config",
            Subtitle = "Save current settings",
        })
        
        row:Right():Button({
            Label = "Create",
            State = "Primary",
            Pushed = function(self)
                local configName = Brain.UI.ConfigNameInput.Value
                
                if configName == "" then
                    print("❌ Please enter a config name")
                    return
                end
                
                -- 🧠 Brain: Save current settings as new config
                local success = SaveConfig(configName)
                
                if success then
                    print("✅ Config created:", configName)
                    
                    -- 🧠 Brain: Refresh config dropdown
                    Brain.RefreshConfigDropdown()
                    
                    -- Select the new config
                    local newConfigs = GetAllConfigs()
                    for i, cfg in ipairs(newConfigs) do
                        if cfg == configName then
                            Brain.UI.ConfigDropdown.Value = i
                            break
                        end
                    end
                    
                    -- Clear input
                    Brain.UI.ConfigNameInput.Value = ""
                end
            end,
        })
    end
    
    -- Config Dropdown
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Select Config",
            Subtitle = "Choose config",
        })
        
        local configs = GetAllConfigs()
        local defaultValue = 1
        
        -- Find current config in list
        for i, cfg in ipairs(configs) do
            if cfg == Settings.CurrentConfig then
                defaultValue = i
                break
            end
        end
        
        Brain.UI.ConfigDropdown = row:Right():PopUpButton({
            Options = configs,
            Value = defaultValue,
            ValueChanged = function(self, value)
                local configName = self.Options[value]
                print("🧠 Brain: Selected config:", configName)
            end,
        })
    end
    
    -- Load Button
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Load Config",
            Subtitle = "Apply selected config",
        })
        
        row:Right():Button({
            Label = "Load",
            State = "Primary",
            Pushed = function(self)
                local selectedIndex = Brain.UI.ConfigDropdown.Value
                local configName = Brain.UI.ConfigDropdown.Options[selectedIndex]
                
                if configName then
                    -- 🧠 Brain: Load config
                    local success = LoadConfig(configName)
                    
                    if success then
                        Settings.LastLoadedConfig = configName
                        SaveSettings()
                        
                        -- 🧠 Brain: Update UI elements
                        Brain.UpdateSeedSelection()
                        
                        print("✅ Config loaded successfully!")
                        print("⚠️ Please restart the script to apply all settings")
                    end
                end
            end,
        })
    end
    
    -- Save Button
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Save Config",
            Subtitle = "Update selected config",
        })
        
        row:Right():Button({
            Label = "Save",
            State = "Secondary",
            Pushed = function(self)
                local selectedIndex = Brain.UI.ConfigDropdown.Value
                local configName = Brain.UI.ConfigDropdown.Options[selectedIndex]
                
                if configName then
                    -- 🧠 Brain: Save config
                    SaveConfig(configName)
                end
            end,
        })
    end
    
    -- Delete Button
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Delete Config",
            Subtitle = "Remove selected config",
        })
        
        row:Right():Button({
            Label = "Delete",
            State = "Destructive",
            Pushed = function(self)
                local selectedIndex = Brain.UI.ConfigDropdown.Value
                local configName = Brain.UI.ConfigDropdown.Options[selectedIndex]
                
                if configName and configName ~= "Default" then
                    local success = DeleteConfig(configName)
                    
                    if success then
                        -- 🧠 Brain: Refresh dropdown
                        Brain.RefreshConfigDropdown()
                        
                        -- Select Default
                        Brain.UI.ConfigDropdown.Value = 1
                    end
                else
                    print("⚠️ Cannot delete Default config")
                end
            end,
        })
    end
    
    -- Auto Load Toggle
    do
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = "Auto Load",
            Subtitle = "Load last config on start",
        })
        
        Brain.UI.AutoLoadToggle = row:Right():Toggle({
            Value = Settings.AutoLoadEnabled,
            ValueChanged = function(self, value)
                Settings.AutoLoadEnabled = value
                SaveSettings()
                
                if value then
                    print("🧠 Brain: Auto-load enabled - Will load:", Settings.LastLoadedConfig, "on next start")
                else
                    print("🧠 Brain: Auto-load disabled")
                end
            end,
        })
    end
end


--[[
    ========================================
    Step 12: Start AutoBuy Module Loop
    ========================================
--]]

print("[BRAIN] Starting AutoBuy module loop...")
AutoBuy.RunLoop()
print("[BRAIN] AutoBuy loop is running in the background!")

--[[
    ========================================
    All Done! 🎉
    ========================================
--]]
