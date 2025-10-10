--[[
    🌱 Plant Vs Brainrot - Auto Attack Module
    This module handles automatic combat with movement and targeting
    
    Features:
    - Auto equip Leather Grip Bat
    - Multiple movement modes (TP, Tween, Walk)
    - Target selection (Random, High HP, Low HP)
    - Smart targeting with O(1) attribute matching
--]]

local AutoAttack = {}

--[[
    ========================================
    Module Configuration
    ========================================
--]]

AutoAttack.Version = "1.0.0"

--[[
    ========================================
    Dependencies (Set by Main)
    ========================================
--]]

AutoAttack.Services = {
    Players = nil,
    ReplicatedStorage = nil,
    TweenService = nil,
    RunService = nil
}

AutoAttack.References = {
    LocalPlayer = nil
}

AutoAttack.Brain = nil

--[[
    ========================================
    Settings & State
    ========================================
--]]

AutoAttack.Settings = {
    AutoAttackEnabled = false,
    MovementMode = "Walk",  -- "TP", "Tween", "Walk"
    AttackMode = "Random",  -- "Random", "HighHP", "LowHP", "HighMaxHP", "LowMaxHP"
    AttackRange = 20,  -- Distance to start attacking
    TweenSpeed = 50  -- Speed for tween movement
}

AutoAttack.IsRunning = false
AutoAttack.CurrentTarget = nil
AutoAttack.BatEquipped = false
AutoAttack.AttackLoop = nil
AutoAttack.MovementLoop = nil
AutoAttack.TotalAttacks = 0

-- Cached targets for O(1) lookup
AutoAttack.CachedTargets = {}
AutoAttack.LastCacheUpdate = 0
AutoAttack.CacheUpdateInterval = 1  -- Update cache every 1 second

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Format numbers with suffixes
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

-- Get player's User ID
function AutoAttack.GetUserID()
    return AutoAttack.References.LocalPlayer.UserId
end

--[[
    ========================================
    Equipment Management
    ========================================
--]]

-- Equip Leather Grip Bat
function AutoAttack.EquipBat()
    if AutoAttack.BatEquipped then return true end
    
    print("[AutoAttack] 🔧 Attempting to equip Leather Grip Bat...")
    
    local success = pcall(function()
        local player = AutoAttack.References.LocalPlayer
        local backpack = player:WaitForChild("Backpack")
        local character = player.Character
        
        if not character then
            print("[AutoAttack] ❌ No character found")
            return
        end
        
        -- Check if already equipped
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == "Leather Grip Bat" then
            print("[AutoAttack] ✅ Bat already equipped")
            AutoAttack.BatEquipped = true
            return
        end
        
        -- Find bat in backpack
        local bat = backpack:FindFirstChild("Leather Grip Bat")
        if bat then
            print("[AutoAttack] 🎯 Found bat in backpack, equipping...")
            -- Unequip current tool
            if equippedTool then
                equippedTool.Parent = backpack
            end
            
            -- Equip bat
            bat.Parent = character
            AutoAttack.BatEquipped = true
            print("[AutoAttack] ✅ Bat equipped successfully!")
        else
            print("[AutoAttack] ❌ Leather Grip Bat not found in backpack")
            -- List all tools in backpack
            print("[AutoAttack] 📦 Tools in backpack:")
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") then
                    print("  -", tool.Name)
                end
            end
        end
    end)
    
    return success and AutoAttack.BatEquipped
end

--[[
    ========================================
    Target Selection (O(1) Optimization)
    ========================================
--]]

-- Get all valid targets (cached for performance)
function AutoAttack.UpdateTargetCache()
    local now = tick()
    
    -- Only update if cache is stale
    if now - AutoAttack.LastCacheUpdate < AutoAttack.CacheUpdateInterval then
        return
    end
    
    AutoAttack.CachedTargets = {}
    AutoAttack.LastCacheUpdate = now
    
    print("[AutoAttack] 🔍 Scanning for targets in workspace.ScriptedMap.Brainrots...")
    
    -- Scan workspace.ScriptedMap.Brainrots for NPCs only
    pcall(function()
        local myUserID = AutoAttack.GetUserID()
        print("[AutoAttack] My User ID:", myUserID)
        
        -- Get the Brainrots folder
        local scriptedMap = workspace:FindFirstChild("ScriptedMap")
        if not scriptedMap then
            print("[AutoAttack] ❌ ScriptedMap not found in workspace!")
            return
        end
        
        local brainrots = scriptedMap:FindFirstChild("Brainrots")
        if not brainrots then
            print("[AutoAttack] ❌ Brainrots folder not found in ScriptedMap!")
            return
        end
        
        print("[AutoAttack] ✅ Found Brainrots folder, scanning...")
        
        -- Scan only Brainrots folder for NPCs
        for _, model in ipairs(brainrots:GetDescendants()) do
            if model:IsA("Model") then
                -- Check if this model is attackable
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                
                if humanoid and primaryPart then
                    -- Read health from attributes (preferred) or Humanoid
                    local health = model:GetAttribute("Health") or humanoid.Health
                    local maxHealth = model:GetAttribute("MaxHealth") or humanoid.MaxHealth
                    
                    if health > 0 then
                        -- Get model ID and associated player
                        local associatedPlayer = model:GetAttribute("AssociatedPlayer")
                        local modelID = model:GetAttribute("ID")
                        
                        print("[AutoAttack] 👤 Found Brainrot:", model.Name, "| HP:", health, "/", maxHealth, "| AssociatedPlayer:", associatedPlayer, "| ID:", modelID)
                        
                        -- Only target Brainrots NOT owned by us (exclude player characters)
                        if not associatedPlayer or associatedPlayer ~= myUserID then
                            table.insert(AutoAttack.CachedTargets, {
                                Model = model,
                                Humanoid = humanoid,
                                PrimaryPart = primaryPart,
                                HP = health,
                                MaxHP = maxHealth,
                                AssociatedPlayer = associatedPlayer,
                                ID = modelID or model.Name
                            })
                            print("[AutoAttack] ✅ Added as valid target:", model.Name)
                        else
                            print("[AutoAttack] ❌ Skipped (owned by player):", model.Name)
                        end
                    end
                end
            end
        end
    end)
    
    print("[AutoAttack] 📊 Found", #AutoAttack.CachedTargets, "valid targets")
end

-- Select best target based on attack mode
function AutoAttack.SelectTarget()
    AutoAttack.UpdateTargetCache()
    
    if #AutoAttack.CachedTargets == 0 then
        return nil
    end
    
    local player = AutoAttack.References.LocalPlayer
    local character = player.Character
    if not character then return nil end
    
    local myPos = character:FindFirstChild("HumanoidRootPart")
    if not myPos then return nil end
    
    local mode = AutoAttack.Settings.AttackMode
    local bestTarget = nil
    
    if mode == "Random" then
        -- Random selection
        bestTarget = AutoAttack.CachedTargets[math.random(1, #AutoAttack.CachedTargets)]
        
    elseif mode == "HighHP" then
        -- Find highest CURRENT HP target
        local highestHP = 0
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.HP > highestHP then
                highestHP = target.HP
                bestTarget = target
            end
        end
        
    elseif mode == "LowHP" then
        -- Find lowest CURRENT HP target
        local lowestHP = math.huge
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.HP < lowestHP and target.HP > 0 then
                lowestHP = target.HP
                bestTarget = target
            end
        end
        
    elseif mode == "HighMaxHP" then
        -- Find highest MAX HP target (tankiest enemies)
        local highestMaxHP = 0
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.MaxHP > highestMaxHP then
                highestMaxHP = target.MaxHP
                bestTarget = target
            end
        end
        
    elseif mode == "LowMaxHP" then
        -- Find lowest MAX HP target (weakest enemies)
        local lowestMaxHP = math.huge
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.MaxHP < lowestMaxHP then
                lowestMaxHP = target.MaxHP
                bestTarget = target
            end
        end
    end
    
    return bestTarget
end

--[[
    ========================================
    Movement System
    ========================================
--]]

-- Calculate distance to target
function AutoAttack.GetDistanceToTarget(target)
    if not target or not target.PrimaryPart then return math.huge end
    
    local player = AutoAttack.References.LocalPlayer
    local character = player.Character
    if not character then return math.huge end
    
    local myPos = character:FindFirstChild("HumanoidRootPart")
    if not myPos then return math.huge end
    
    return (myPos.Position - target.PrimaryPart.Position).Magnitude
end

-- Teleport to target
function AutoAttack.TeleportToTarget(target)
    if not target or not target.PrimaryPart then return false end
    
    local success = pcall(function()
        local player = AutoAttack.References.LocalPlayer
        local character = player.Character
        if not character then return end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        -- TP slightly in front of target
        local targetPos = target.PrimaryPart.Position
        local offset = Vector3.new(0, 2, 5)  -- Slightly above and in front
        hrp.CFrame = CFrame.new(targetPos + offset)
    end)
    
    return success
end

-- Tween to target (smooth movement)
function AutoAttack.TweenToTarget(target)
    if not target or not target.PrimaryPart then return false end
    
    local success = pcall(function()
        local player = AutoAttack.References.LocalPlayer
        local character = player.Character
        if not character then return end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        -- Calculate tween
        local targetPos = target.PrimaryPart.Position
        local offset = Vector3.new(0, 2, 5)
        local distance = (hrp.Position - (targetPos + offset)).Magnitude
        local duration = distance / AutoAttack.Settings.TweenSpeed
        
        -- Create tween
        local tweenInfo = TweenInfo.new(
            duration,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out
        )
        
        local goal = {CFrame = CFrame.new(targetPos + offset)}
        local tween = AutoAttack.Services.TweenService:Create(hrp, tweenInfo, goal)
        
        tween:Play()
    end)
    
    return success
end

-- Walk to target (using Humanoid)
function AutoAttack.WalkToTarget(target)
    if not target or not target.PrimaryPart then return false end
    
    local success = pcall(function()
        local player = AutoAttack.References.LocalPlayer
        local character = player.Character
        if not character then return end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        
        -- Set walk target
        humanoid:MoveTo(target.PrimaryPart.Position)
    end)
    
    return success
end

-- Move to target based on selected mode
function AutoAttack.MoveToTarget(target)
    local mode = AutoAttack.Settings.MovementMode
    
    if mode == "TP" then
        return AutoAttack.TeleportToTarget(target)
    elseif mode == "Tween" then
        return AutoAttack.TweenToTarget(target)
    elseif mode == "Walk" then
        return AutoAttack.WalkToTarget(target)
    end
    
    return false
end

--[[
    ========================================
    Combat System
    ========================================
--]]

-- Fire attack remote
function AutoAttack.Attack(targetID)
    if not targetID then
        print("[AutoAttack] ❌ No target ID provided")
        return false
    end
    
    print("[AutoAttack] 🔥 Firing attack for ID:", targetID)
    
    local success = pcall(function()
        local args = {
            [1] = {
                [1] = tostring(targetID)
            }
        }
        
        AutoAttack.Services.ReplicatedStorage:WaitForChild("Remotes")
            :WaitForChild("AttacksServer")
            :WaitForChild("WeaponAttack")
            :FireServer(unpack(args))
    end)
    
    if success then
        AutoAttack.TotalAttacks = AutoAttack.TotalAttacks + 1
        print("[AutoAttack] ✅ Attack fired! Total attacks:", AutoAttack.TotalAttacks)
    else
        print("[AutoAttack] ❌ Attack failed!")
    end
    
    return success
end

-- Main combat loop
function AutoAttack.CombatLoop()
    print("[AutoAttack] 🎯 Combat loop started!")
    
    while AutoAttack.IsRunning and AutoAttack.Settings.AutoAttackEnabled do
        task.wait(0.1)  -- Attack interval
        
        -- Ensure bat is equipped
        if not AutoAttack.BatEquipped then
            AutoAttack.EquipBat()
            task.wait(0.5)
            continue
        end
        
        -- Select target
        local target = AutoAttack.SelectTarget()
        
        if not target then
            print("[AutoAttack] ⚠️ No valid targets found, waiting...")
            task.wait(1)
            continue
        end
        
        print("[AutoAttack] 🎯 Target selected:", target.Model.Name, "| HP:", target.HP, "/", target.MaxHP)
        AutoAttack.CurrentTarget = target
        
        -- Check distance
        local distance = AutoAttack.GetDistanceToTarget(target)
        print("[AutoAttack] 📏 Distance to target:", math.floor(distance), "studs")
        
        if distance > AutoAttack.Settings.AttackRange then
            -- Move closer
            print("[AutoAttack] 🚶 Moving to target using", AutoAttack.Settings.MovementMode, "mode...")
            AutoAttack.MoveToTarget(target)
            task.wait(0.5)
        else
            -- In range, attack!
            print("[AutoAttack] ⚔️ Attacking target:", target.ID)
            AutoAttack.Attack(target.ID)
        end
        
        -- Check if target is still alive (read from attributes or Humanoid)
        local currentHP = target.Model:GetAttribute("Health") or target.Humanoid.Health
        if currentHP <= 0 then
            print("[AutoAttack] 💀 Target defeated!")
            AutoAttack.CurrentTarget = nil
            task.wait(0.2)
        end
    end
    
    print("[AutoAttack] 🛑 Combat loop ended")
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
--]]

function AutoAttack.Start()
    if AutoAttack.IsRunning then
        print("[AutoAttack] ⚠️ Already running!")
        return
    end
    
    print("[AutoAttack] 🚀 Starting Auto Attack...")
    print("[AutoAttack] ⚙️ Movement Mode:", AutoAttack.Settings.MovementMode)
    print("[AutoAttack] 🎯 Attack Mode:", AutoAttack.Settings.AttackMode)
    print("[AutoAttack] 📏 Attack Range:", AutoAttack.Settings.AttackRange)
    
    AutoAttack.IsRunning = true
    AutoAttack.TotalAttacks = 0
    
    -- Equip bat first
    AutoAttack.EquipBat()
    
    -- Start combat loop
    AutoAttack.AttackLoop = task.spawn(function()
        AutoAttack.CombatLoop()
    end)
    
    print("[AutoAttack] ✅ Auto Attack started!")
end

function AutoAttack.Stop()
    if not AutoAttack.IsRunning then
        return
    end
    
    AutoAttack.IsRunning = false
    AutoAttack.CurrentTarget = nil
    AutoAttack.BatEquipped = false
    
    -- Cancel loops
    if AutoAttack.AttackLoop then
        task.cancel(AutoAttack.AttackLoop)
        AutoAttack.AttackLoop = nil
    end
    
    -- Clear cache
    AutoAttack.CachedTargets = {}
end

--[[
    ========================================
    Initialize Module
    ========================================
--]]

function AutoAttack.Init(services, references, brain)
    AutoAttack.Services = services
    AutoAttack.References = references
    AutoAttack.Brain = brain
    
    return true
end

--[[
    ========================================
    Return Module
    ========================================
--]]

return AutoAttack

