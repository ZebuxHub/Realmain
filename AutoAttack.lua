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
    AttackMode = "Random",  -- "Random", "HighHP", "LowHP"
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
    
    local success = pcall(function()
        local player = AutoAttack.References.LocalPlayer
        local backpack = player:WaitForChild("Backpack")
        local character = player.Character
        
        if not character then return end
        
        -- Check if already equipped
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == "Leather Grip Bat" then
            AutoAttack.BatEquipped = true
            return
        end
        
        -- Find bat in backpack
        local bat = backpack:FindFirstChild("Leather Grip Bat")
        if bat then
            -- Unequip current tool
            if equippedTool then
                equippedTool.Parent = backpack
            end
            
            -- Equip bat
            bat.Parent = character
            AutoAttack.BatEquipped = true
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
    
    -- Scan workspace for NPCs/Players
    pcall(function()
        local myUserID = AutoAttack.GetUserID()
        
        -- Common locations for NPCs/enemies
        local locations = {
            workspace:FindFirstChild("NPCs"),
            workspace:FindFirstChild("Enemies"),
            workspace:FindFirstChild("Mobs"),
            workspace
        }
        
        for _, location in ipairs(locations) do
            if location then
                for _, model in ipairs(location:GetDescendants()) do
                    if model:IsA("Model") then
                        -- Check if this model is attackable
                        local humanoid = model:FindFirstChildOfClass("Humanoid")
                        local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                        
                        if humanoid and humanoid.Health > 0 and primaryPart then
                            -- OPTIMIZED: O(1) attribute check
                            local associatedPlayer = model:GetAttribute("AssociatedPlayer")
                            
                            -- Only target models NOT owned by us
                            if not associatedPlayer or associatedPlayer ~= myUserID then
                                table.insert(AutoAttack.CachedTargets, {
                                    Model = model,
                                    Humanoid = humanoid,
                                    PrimaryPart = primaryPart,
                                    HP = humanoid.Health,
                                    MaxHP = humanoid.MaxHealth,
                                    AssociatedPlayer = associatedPlayer,
                                    ID = model:GetAttribute("ID") or model.Name
                                })
                            end
                        end
                    end
                end
            end
        end
    end)
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
        -- Find highest HP target
        local highestHP = 0
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.HP > highestHP then
                highestHP = target.HP
                bestTarget = target
            end
        end
        
    elseif mode == "LowHP" then
        -- Find lowest HP target
        local lowestHP = math.huge
        for _, target in ipairs(AutoAttack.CachedTargets) do
            if target.HP < lowestHP and target.HP > 0 then
                lowestHP = target.HP
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
    if not targetID then return false end
    
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
    end
    
    return success
end

-- Main combat loop
function AutoAttack.CombatLoop()
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
            task.wait(1)
            continue
        end
        
        AutoAttack.CurrentTarget = target
        
        -- Check distance
        local distance = AutoAttack.GetDistanceToTarget(target)
        
        if distance > AutoAttack.Settings.AttackRange then
            -- Move closer
            AutoAttack.MoveToTarget(target)
            task.wait(0.5)
        else
            -- In range, attack!
            AutoAttack.Attack(target.ID)
        end
        
        -- Check if target is still alive
        if target.Humanoid.Health <= 0 then
            AutoAttack.CurrentTarget = nil
            task.wait(0.2)
        end
    end
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
--]]

function AutoAttack.Start()
    if AutoAttack.IsRunning then
        return
    end
    
    AutoAttack.IsRunning = true
    AutoAttack.TotalAttacks = 0
    
    -- Equip bat first
    AutoAttack.EquipBat()
    
    -- Start combat loop
    AutoAttack.AttackLoop = task.spawn(function()
        AutoAttack.CombatLoop()
    end)
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

