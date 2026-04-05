-- =============================================
--          LIMB EXTENDER - Versión Ordenada
-- =============================================

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local DEFAULTS = {
    TOGGLE = "L",
    TARGET_LIMB = "UpperTorso",
    LIMB_SIZE = 15,
    LIMB_TRANSPARENCY = 0.9,
    LIMB_CAN_COLLIDE = false,
    MOBILE_BUTTON = false,
    LISTEN_FOR_INPUT = true,
    TEAM_CHECK = true,
    FORCEFIELD_CHECK = true,
    RESET_LIMB_ON_DEATH2 = false,
    USE_HIGHLIGHT = true,
    DEPTH_MODE = "AlwaysOnTop",
    HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 233, 201),
    HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
    HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(138, 169, 255),
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
}

-- Persistencia global
local limbExtenderData = getgenv().limbExtenderData or {}
getgenv().limbExtenderData = limbExtenderData

-- Terminar proceso anterior si existe
if limbExtenderData.terminateOldProcess and type(limbExtenderData.terminateOldProcess) == "function" then
    pcall(limbExtenderData.terminateOldProcess, "FullKill")
    limbExtenderData.terminateOldProcess = nil
end

-- Cargar ConnectionManager
if not limbExtenderData.ConnectionManager then
    limbExtenderData.ConnectionManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ConnectionManager.lua'))()
end

local ConnectionManager = limbExtenderData.ConnectionManager

-- Bypass anti-kick (índice)
if not limbExtenderData._indexBypassDone then
    limbExtenderData._indexBypassDone = true
    pcall(function()
        for _, obj in ipairs(getgc(true)) do
            local idx = rawget(obj, "indexInstance")
            if typeof(idx) == "table" and idx[1] == "kick" then
                for _, pair in pairs(obj) do
                    if typeof(pair) == "table" and pair[2] then
                        pair[2] = function() return false end
                    end
                end
                break
            end
        end
    end)
end

-- ==================== UTILIDADES ====================

local function mergeSettings(user)
    local s = {}
    for k, v in pairs(DEFAULTS) do
        s[k] = v
    end
    if user then
        for k, v in pairs(user) do
            s[k] = v
        end
    end
    return s
end

local function watchProperty(instance, prop, callback)
    if not instance or type(prop) ~= "string" or type(callback) ~= "function" then
        return nil
    end
    local signal = instance:GetPropertyChangedSignal(prop)
    if signal and type(signal.Connect) == "function" then
        return signal:Connect(function()
            callback(instance)
        end)
    end
    return nil
end

local function makeHighlight(settings)
    local hiFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Limb Extender Highlights Folder")
    if not hiFolder then
        hiFolder = Instance.new("Folder")
        hiFolder.Name = "Limb Extender Highlights Folder"
        hiFolder.Parent = game:GetService("ReplicatedStorage")
    end

    local hi = Instance.new("Highlight")
    hi.Name = "LimbHighlight"
    hi.Enabled = true

    if settings then
        if settings.DEPTH_MODE and Enum.HighlightDepthMode[settings.DEPTH_MODE] then
            hi.DepthMode = Enum.HighlightDepthMode[settings.DEPTH_MODE]
        end
        if settings.HIGHLIGHT_FILL_COLOR then
            hi.FillColor = settings.HIGHLIGHT_FILL_COLOR
        end
        if settings.HIGHLIGHT_FILL_TRANSPARENCY then
            hi.FillTransparency = settings.HIGHLIGHT_FILL_TRANSPARENCY
        end
        if settings.HIGHLIGHT_OUTLINE_COLOR then
            hi.OutlineColor = settings.HIGHLIGHT_OUTLINE_COLOR
        end
        if settings.HIGHLIGHT_OUTLINE_TRANSPARENCY then
            hi.OutlineTransparency = settings.HIGHLIGHT_OUTLINE_TRANSPARENCY
        end
    end

    hi.Parent = hiFolder
    return hi
end

-- ==================== PLAYER DATA ====================

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
    local self = setmetatable({
        _parent = parent,
        player = player,
        conns = ConnectionManager.new(),
        highlight = nil,
        PartStreamable = nil,
        _charDelay = nil,
        _destroyed = false,
    }, PlayerData)

    if player and player.CharacterAdded then
        self.conns:Connect(player.CharacterAdded, function(c)
            self:onCharacter(c)
        end, ("Player_%s_CharacterAdded"):format(player.Name))
    end

    local character = player and (player.Character or workspace:FindFirstChild(player.Name))
    self:onCharacter(character)

    return self
end

function PlayerData:saveLimbProperties(limb)
    if not limb then return end
    local parent = self._parent

    parent._limbStore[limb] = {
        OriginalSize = limb.Size,
        OriginalTransparency = limb.Transparency,
        OriginalCanCollide = limb.CanCollide,
        OriginalMassless = limb.Massless,
        SizeConnection = nil,
        TransparencyConnection = nil,
        CollisionConnection = nil,
    }
end

function PlayerData:restoreLimbProperties(limb)
    if not limb then return end
    local parent = self._parent
    local p = parent._limbStore[limb]
    if not p then return end

    if p.SizeConnection then p.SizeConnection:Disconnect() end
    if p.TransparencyConnection then p.TransparencyConnection:Disconnect() end
    if p.CollisionConnection then p.CollisionConnection:Disconnect() end

    if limb and limb.Parent then
        limb.Size = p.OriginalSize
        limb.Transparency = p.OriginalTransparency
        limb.CanCollide = p.OriginalCanCollide
        limb.Massless = p.OriginalMassless
    end

    parent._limbStore[limb] = nil
    if limbExtenderData.limbs then
        limbExtenderData.limbs[limb] = nil
    end
end

function PlayerData:modifyLimbProperties(limb)
    if not limb then return end
    local parent = self._parent
    if parent._limbStore[limb] then return end

    self:saveLimbProperties(limb)
    local entry = parent._limbStore[limb]

    local sizeVal = parent._settings.LIMB_SIZE or DEFAULTS.LIMB_SIZE
    local newSize = Vector3.new(sizeVal, sizeVal, sizeVal)

    entry.SizeConnection = watchProperty(limb, "Size", function(l)
        l.Size = newSize
    end)

    entry.TransparencyConnection = watchProperty(limb, "Transparency", function(l)
        l.Transparency = parent._settings.LIMB_TRANSPARENCY
    end)

    entry.CollisionConnection = watchProperty(limb, "CanCollide", function(l)
        l.CanCollide = parent._settings.LIMB_CAN_COLLIDE
    end)

    if limb and limb.Parent then
        limb.Size = newSize
        limb.Transparency = parent._settings.LIMB_TRANSPARENCY
        limb.CanCollide = parent._settings.LIMB_CAN_COLLIDE

        -- Massless importante según el limb
        limb.Massless = (parent._settings.TARGET_LIMB == "UpperTorso")
    end

    if limbExtenderData.limbs then
        limbExtenderData.limbs[limb] = parent._limbStore[limb]
    end
end

function PlayerData:spoofSize(part)
    if not part then return end
    local saved = part.Size
    local name = part.Name

    if limbExtenderData._spoofTarget == name then return end
    limbExtenderData._spoofTarget = name

    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        local old = mt.__index

        mt.__index = function(Self, Key)
            if tostring(Self) == name and tostring(Key) == "Size" and not checkcaller() then
                return saved
            end
            return old(Self, Key)
        end

        setreadonly(mt, true)
    end)
end

-- ==================== SETUP CHARACTER ====================

function PlayerData:setupCharacter(char)
    local parent = self._parent
    if not char or not parent then return end
    if not self.player then return end

    -- Team check
    if parent:_isTeam(self.player) then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Cleanup anterior
    if self.PartStreamable and self.PartStreamable.Destroy then
        self.PartStreamable:Destroy()
        self.PartStreamable = nil
    end

    -- Streamable (busca el limb objetivo)
    if parent._Streamable and parent._Streamable.new then
        self.PartStreamable = parent._Streamable.new(char, parent._settings.TARGET_LIMB)

        if self.PartStreamable and self.PartStreamable.Observe then
            self.PartStreamable:Observe(function(part, trove)
                if self._destroyed or not part then return end

                self:spoofSize(part)
                self:modifyLimbProperties(part)

                -- Highlight
                if parent._settings.USE_HIGHLIGHT then
                    if not self.highlight then
                        self.highlight = makeHighlight(parent._settings)
                    end
                    self.highlight.Adornee = part
                end

                -- Cleanup al remover character o morir
                if self.player.CharacterRemoving then
                    self.conns:Connect(self.player.CharacterRemoving, function()
                        self:restoreLimbProperties(part)
                    end)
                end

                local deathEvent = parent._settings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
                if deathEvent then
                    self.conns:Connect(deathEvent, function(hp)
                        if not hp or hp <= 0 then
                            self:restoreLimbProperties(part)
                        end
                    end)
                end

                if trove and trove.Add then
                    trove:Add(function()
                        self:restoreLimbProperties(part)
                    end)
                end
            end)
        end
    end

    -- ==================== FIX FLOTACIÓN AL BAJARSE DE VEHÍCULO ====================
    if humanoid then
        humanoid.Seated:Connect(function(isSeated)
            if not isSeated then
                task.wait(0.2)

                local root = char:FindFirstChild("HumanoidRootPart")
                if root and root.Parent then
                    root.CFrame = root.CFrame + Vector3.new(0, 0.05, 0)
                    root.AssemblyLinearVelocity = Vector3.new(0, 1, 0)

                    task.wait(0.08)
                    for limb, data in pairs(parent._limbStore or {}) do
                        if limb and limb.Parent and data.OriginalSize then
                            limb.Size = data.OriginalSize
                            task.delay(0.05, function()
                                if limb and limb.Parent then
                                    local newSize = parent._settings.LIMB_SIZE or 15
                                    limb.Size = Vector3.new(newSize, newSize, newSize)
                                end
                            end)
                        end
                    end
                end
            end
        end, "VehicleDismountFix_" .. self.player.Name)
    end

    -- Forzar no colisión en torso
    task.delay(0.8, function()
        if self._destroyed or not char or not char.Parent then return end
        forceNoTorsoCollision(char)
    end)
end

local function forceNoTorsoCollision(character)
    if not character or not character.Parent then return end

    local upper = character:FindFirstChild("UpperTorso") or character:WaitForChild("UpperTorso", 5)
    local lower = character:FindFirstChild("LowerTorso") or character:WaitForChild("LowerTorso", 5)
    if not (upper and lower) then return end
    if upper:FindFirstChild("NoTorsoCollideTag") then return end

    local RunService = game:GetService("RunService")

    local conn1 = RunService.Stepped:Connect(function()
        pcall(function()
            if upper and upper.Parent then upper.CanCollide = false end
            if lower and lower.Parent then lower.CanCollide = false end
        end)
    end)

    local conn2 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if upper and upper.Parent then upper.CanCollide = false end
            if lower and lower.Parent then lower.CanCollide = false end
        end)
    end)

    local tag = Instance.new("BoolValue")
    tag.Name = "NoTorsoCollideTag"
    tag.Parent = upper

    local function cleanup()
        if conn1 then conn1:Disconnect() end
        if conn2 then conn2:Disconnect() end
    end

    character.AncestryChanged:Connect(function()
        if not character:IsDescendantOf(game) then
            cleanup()
        end
    end)

    tag.Destroying:Connect(cleanup)
end

function PlayerData:onCharacter(char)
    if not char then return end
    if self._charDelay then
        task.cancel(self._charDelay)
        self._charDelay = nil
    end

    self._charDelay = task.delay(0.1, function()
        if self._destroyed then return end

        if self._parent._settings.FORCEFIELD_CHECK then
            local ff = char:FindFirstChildOfClass("ForceField")
            if ff then
                self.conns:Connect(ff.Destroying, function()
                    self:setupCharacter(char)
                end)
                return
            end
        end

        self:setupCharacter(char)
    end)
end

function PlayerData:Destroy()
    if self._destroyed then return end
    self._destroyed = true

    if self.conns then
        self.conns:DisconnectAll()
        if self.conns.Destroy then self.conns:Destroy() end
        self.conns = nil
    end

    if self.highlight and self.highlight.Destroy then
        self.highlight:Destroy()
        self.highlight = nil
    end

    if self.PartStreamable and self.PartStreamable.Destroy then
        self.PartStreamable:Destroy()
        self.PartStreamable = nil
    end

    if self._charDelay then
        task.cancel(self._charDelay)
        self._charDelay = nil
    end

    setmetatable(self, nil)
    for k in pairs(self) do self[k] = nil end
end

-- ==================== MAIN CLASS ====================

local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender.new(userSettings)
    local self = setmetatable({
        _settings = mergeSettings(userSettings),
        _playerTable = limbExtenderData.playerTable or {},
        _limbStore = limbExtenderData.limbs or {},
        _Streamable = limbExtenderData.Streamable,
        _CAU = limbExtenderData.CAU,
        _connections = ConnectionManager.new(),
        _running = limbExtenderData.running or false,
        _destroyed = false,
    }, LimbExtender)

    -- Guardar referencias globales
    limbExtenderData.playerTable = self._playerTable
    limbExtenderData.limbs = self._limbStore
    limbExtenderData.Streamable = self._Streamable
    limbExtenderData.CAU = self._CAU
    limbExtenderData.running = self._running

    limbExtenderData.terminateOldProcess = function(reason)
        if type(self.Destroy) == "function" then self:Destroy() end
    end

    -- Cargar módulos necesarios
    if self._settings.LISTEN_FOR_INPUT then
        self._CAU = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ContextActionUtility.lua'))()
        limbExtenderData.CAU = self._CAU
    end

    self._Streamable = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/Streamable.lua'))()
    limbExtenderData.Streamable = self._Streamable

    -- Bind toggle key
    if self._settings.LISTEN_FOR_INPUT and self._CAU and self._CAU.BindAction then
        self._CAU:BindAction(
            "LimbExtenderToggle",
            function(_, inputState)
                if inputState == Enum.UserInputState.Begin then
                    self:Toggle()
                end
            end,
            self._settings.MOBILE_BUTTON,
            Enum.KeyCode[self._settings.TOGGLE]
        )
    end

    return self
end

function LimbExtender:_isTeam(player)
    return self._settings.TEAM_CHECK and localPlayer and localPlayer.Team and player.Team == localPlayer.Team
end

function LimbExtender:Terminate()
    -- Cleanup completo (ya implementado en tu código original)
    for _, pd in pairs(limbExtenderData.playerTable or {}) do
        if pd and pd.Destroy then pd:Destroy() end
    end

    for limb, props in pairs(limbExtenderData.limbs or {}) do
        if props.SizeConnection then props.SizeConnection:Disconnect() end
        if props.CollisionConnection then props.CollisionConnection:Disconnect() end
        if limb and limb.Parent then
            if props.OriginalSize then limb.Size = props.OriginalSize end
            if props.OriginalTransparency then limb.Transparency = props.OriginalTransparency end
            if props.OriginalCanCollide ~= nil then limb.CanCollide = props.OriginalCanCollide end
            if props.OriginalMassless ~= nil then limb.Massless = props.OriginalMassless end
        end
    end

    if self._CAU and self._CAU.UnbindAction then
        self._CAU:UnbindAction("LimbExtenderToggle")
    end

    if self._connections then
        self._connections:DisconnectAll()
        if self._connections.Destroy then self._connections:Destroy() end
    end
end

function LimbExtender:Start()
    if self._running then return end
    self._running = true
    limbExtenderData.running = true

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and not self._playerTable[p.Name] then
            self._playerTable[p.Name] = PlayerData.new(self, p)
        end
    end

    -- Team change del localplayer
    if localPlayer:GetPropertyChangedSignal then
        self._connections:Connect(localPlayer:GetPropertyChangedSignal("Team"), function()
            self:Restart()
        end)
    end

    self._connections:Connect(Players.PlayerAdded, function(p)
        if p ~= localPlayer and not self._playerTable[p.Name] then
            self._playerTable[p.Name] = PlayerData.new(self, p)
        end
    end)

    self._connections:Connect(Players.PlayerRemoving, function(p)
        local pd = self._playerTable[p.Name]
        if pd and pd.Destroy then pd:Destroy() end
        self._playerTable[p.Name] = nil
    end)
end

function LimbExtender:Stop()
    if not self._running then return end
    self._running = false
    limbExtenderData.running = false

    if self._connections then
        self._connections:DisconnectAll()
        self._connections = ConnectionManager.new()
    end

    for _, pd in pairs(self._playerTable) do
        if pd and pd.Destroy then pd:Destroy() end
    end
    self._playerTable = {}
end

function LimbExtender:Toggle(state)
    if type(state) == "boolean" then
        self._running = state
    else
        self._running = not self._running
    end

    limbExtenderData.running = self._running

    if self._running then
        self:Stop()
    else
        self:Start()
    end
end

function LimbExtender:Restart()
    local wasRunning = self._running
    self:Stop()
    if wasRunning then self:Start() end
end

function LimbExtender:Destroy()
    if self._destroyed then return end
    self._destroyed = true

    self:Stop()
    self:Terminate()

    limbExtenderData.running = false
    limbExtenderData.terminateOldProcess = nil
    limbExtenderData.playerTable = nil
    limbExtenderData.limbs = nil
    limbExtenderData.Streamable = nil
    limbExtenderData.CAU = nil
end

function LimbExtender:Set(key, value)
    if self._settings[key] ~= value then
        self._settings[key] = value
        self:Restart()
    end
end

function LimbExtender:Get(key)
    return self._settings[key]
end

-- ==================== EXPORT ====================

return setmetatable({}, {
    __call = function(_, userSettings)
        return LimbExtender.new(userSettings)
    end,
    __index = LimbExtender,
})
