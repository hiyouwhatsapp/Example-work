--!strict

-- I sometimes sort definitions on large files :p
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Shared.Packages.Janitor)
local Lifecycle = require(ReplicatedStorage.Shared.Core.Lifecycle)
local GoodSignal = require(ReplicatedStorage.Shared.Packages.GoodSignal)
local InventoryTypes = require(ReplicatedStorage.Shared.Contexts.Inventory.InventoryTypes)
local TowerTargeting = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerTargeting)
local TowerRuntimeTypes = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerRuntimeTypes)
local TowerStatEvaluator = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerStatEvaluator)
local TowerRuntimeDefinitions = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerRuntimeDefinitions)

type TowerState = {
	id: string,
	owner: Player,
	slot: InventoryTypes.GameUnitSlot,
	model: Model,
	janitor: any,
	position: Vector3,
	yaw: number,
	upgradeLevel: number,
	priority: TowerRuntimeTypes.TargetPriority,
	stats: TowerRuntimeTypes.CombatStats,
	totalSpent: number,
	takedowns: number,
	totalDamage: number,
	cooldownRemaining: number,
	revision: number,
	idleTrack: AnimationTrack?,
	attackTrack: AnimationTrack?,
}

type Fields = {
	_janitor: any,
	_clock: any,
	_enemies: any,
	_economy: any,
	_assets: any,
	_matches: any,
	_root: Folder?,
	_states: { TowerState },
	_byId: { [string]: TowerState },
	_byOwner: { [number]: { TowerState } },
	_query: { TowerRuntimeTypes.TargetCandidate },
	_revision: { [number]: number },
	SnapshotChanged: any,
	Placed: any,
	Sold: any,
	Damaged: any,
	Takedown: any,
}

local TowerRuntimeService = {}
TowerRuntimeService.__index = TowerRuntimeService

export type TowerRuntimeService = typeof(setmetatable({} :: Fields, TowerRuntimeService))

local function result(
	requestId: string,
	status: TowerRuntimeTypes.TowerActionStatus,
	towerId: string?,
	message: string?
): TowerRuntimeTypes.ActionResult
	return { requestId = requestId, status = status, towerId = towerId, message = message }
end

local function primaryPart(model: Model): BasePart?
	local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart", true) :: BasePart?
	if part == nil then
		part = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if part ~= nil then
		model.PrimaryPart = part
	end
	return part
end

local function pointInPart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y + 8
		and math.abs(localPoint.Z) <= half.Z
end

local function animationTrack(model: Model, assetId: number?, looped: boolean): AnimationTrack?
	if assetId == nil or assetId <= 0 then
		return nil
	end
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if controller == nil then
		return nil
	end
	local animator = controller:FindFirstChildWhichIsA("Animator") or Instance.new("Animator")
	animator.Parent = controller
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{assetId}`
	local track = animator:LoadAnimation(animation)
	animation:Destroy()
	track.Looped = looped
	return track
end

function TowerRuntimeService.new(): TowerRuntimeService
	return setmetatable({
		_janitor = Janitor.new(),
		_clock = nil :: any,
		_enemies = nil :: any,
		_economy = nil :: any,
		_assets = nil :: any,
		_matches = nil :: any,
		_root = nil,
		_states = {},
		_byId = {},
		_byOwner = {},
		_query = {},
		_revision = {},
		SnapshotChanged = GoodSignal.new(),
		Placed = GoodSignal.new(),
		Sold = GoodSignal.new(),
		Damaged = GoodSignal.new(),
		Takedown = GoodSignal.new(),
	}, TowerRuntimeService)
end

function TowerRuntimeService.OnInit(self: TowerRuntimeService): ()
	for _, pair in
		{
			{ self.SnapshotChanged, "SnapshotChanged" },
			{ self.Placed, "Placed" },
			{ self.Sold, "Sold" },
			{ self.Damaged, "Damaged" },
			{ self.Takedown, "Takedown" },
		}
	do
		self._janitor:Add(pair[1], "DisconnectAll", pair[2] :: string)
	end
end

function TowerRuntimeService.OnStart(self: TowerRuntimeService): ()
	self._clock = Lifecycle.resolve("SimulationClockService")
	self._enemies = Lifecycle.resolve("EnemyRuntimeService")
	self._economy = Lifecycle.resolve("MatchEconomyService")
	self._assets = Lifecycle.resolve("GameUnitAssetService")
	self._matches = Lifecycle.resolve("MatchBootstrapService")
	local old = Workspace:FindFirstChild("RuntimeTowers")
	if old ~= nil then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "RuntimeTowers"
	root.Parent = Workspace
	self._root = root
	self._janitor:Add(root, "Destroy", "RuntimeRoot")
	self._janitor:Add(
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end),
		"Disconnect",
		"Heartbeat"
	)
	self._janitor:Add(
		Players.PlayerRemoving:Connect(function(player)
			self:_removeOwner(player)
		end),
		"Disconnect",
		"Removing"
	)
	self._janitor:Add(
		self._clock.TimeScaleChanged:Connect(function(speed: number)
			self:_setAnimationSpeed(speed)
		end),
		"Disconnect",
		"Clock"
	)
end

function TowerRuntimeService.place(
	self: TowerRuntimeService,
	player: Player,
	request: TowerRuntimeTypes.PlacementRequest
): TowerRuntimeTypes.ActionResult
	if request.x ~= request.x or request.y ~= request.y or request.z ~= request.z or math.abs(request.yaw) > 100000 then
		return result(request.requestId, "Invalid", nil, "Invalid placement transform")
	end
	local context = self._matches:get(player)
	local loadout = if context ~= nil then context.loadouts.Units :: InventoryTypes.GameUnitLoadout? else nil
	if loadout == nil then
		return result(request.requestId, "Unavailable", nil, "Loadout is not ready")
	end
	local slot: InventoryTypes.GameUnitSlot? = nil
	for _, candidate in loadout.slots do
		if candidate.slot == request.loadoutSlot then
			slot = candidate
			break
		end
	end
	if slot == nil then
		return result(request.requestId, "Invalid", nil, "Unit is not equipped")
	end
	local ownerStates = self._byOwner[player.UserId]
	if ownerStates == nil then
		ownerStates = {}
		self._byOwner[player.UserId] = ownerStates
	end
	if #ownerStates >= TowerRuntimeDefinitions.MAX_TOWERS_PER_PLAYER then
		return result(request.requestId, "PlacementLimit", nil, nil)
	end
	local sameDefinition = 0
	for _, tower in ownerStates do
		if tower.slot.unit.instanceId == slot.unit.instanceId then
			sameDefinition += 1
		end
	end
	if sameDefinition >= TowerRuntimeDefinitions.placementLimit(slot.definition.rarityId) then
		return result(request.requestId, "PlacementLimit", nil, nil)
	end
	local position = Vector3.new(request.x, request.y, request.z)
	if not self:_validPlacement(player, position) then
		return result(request.requestId, "PlacementBlocked", nil, nil)
	end
	if not self._economy:spend(player, slot.deploymentCost) then
		return result(request.requestId, "InsufficientFunds", nil, nil)
	end
	local modelId = slot.definition.modelId
	local model = if modelId ~= nil then self._assets:clone(modelId) else nil
	if model == nil or primaryPart(model) == nil then
		self._economy:grant(player, slot.deploymentCost)
		if model ~= nil then
			model:Destroy()
		end
		return result(request.requestId, "Unavailable", nil, "Unit model is unavailable")
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
		end
	end
	local id = HttpService:GenerateGUID(false)
	local janitor = Janitor.new()
	janitor:Add(model, "Destroy", "Model")
	local state: TowerState = {
		id = id,
		owner = player,
		slot = slot,
		model = model,
		janitor = janitor,
		position = position,
		yaw = request.yaw,
		upgradeLevel = 0,
		priority = "First",
		stats = TowerStatEvaluator.atUpgrade(slot.stats, 0),
		totalSpent = slot.deploymentCost,
		takedowns = 0,
		totalDamage = 0,
		cooldownRemaining = 0,
		revision = 1,
		idleTrack = animationTrack(model, slot.definition.animations.idleAssetId, true),
		attackTrack = animationTrack(model, slot.definition.animations.attackAssetId, false),
	}
	model.Name = `{slot.definition.id}_{id}`
	model:SetAttribute("TowerRuntimeId", id)
	model:SetAttribute("TowerOwnerUserId", player.UserId)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, request.yaw, 0))
	model.Parent = assert(self._root, "Tower runtime root is unavailable")
	if state.idleTrack ~= nil then
		state.idleTrack:Play(0.1, 1, self._clock:getTimeScale())
	end
	table.insert(self._states, state)
	table.insert(ownerStates, state)
	self._byOwner[player.UserId] = ownerStates
	self._byId[id] = state
	self._janitor:Add(janitor, "Destroy", `Tower:{id}`)
	self:_changed(player)
	self.Placed:Fire(player, id, slot.unit.instanceId)
	return result(request.requestId, "Applied", id, nil)
end

function TowerRuntimeService.upgrade(
	self: TowerRuntimeService,
	player: Player,
	requestId: string,
	id: string
): TowerRuntimeTypes.ActionResult
	local state = self:_owned(player, id)
	if state == nil then
		return result(requestId, "NotOwner", nil, nil)
	end
	local nextLevel = state.upgradeLevel + 1
	local cost = TowerStatEvaluator.upgradeCost(state.slot.deploymentCost, nextLevel)
	if cost == nil then
		return result(requestId, "MaxUpgrade", id, nil)
	end
	if not self._economy:spend(player, cost) then
		return result(requestId, "InsufficientFunds", id, nil)
	end
	state.upgradeLevel = nextLevel
	state.totalSpent += cost
	state.stats = TowerStatEvaluator.atUpgrade(state.slot.stats, nextLevel)
	state.revision += 1
	self:_changed(player)
	return result(requestId, "Applied", id, nil)
end

function TowerRuntimeService.cyclePriority(
	self: TowerRuntimeService,
	player: Player,
	requestId: string,
	id: string
): TowerRuntimeTypes.ActionResult
	local state = self:_owned(player, id)
	if state == nil then
		return result(requestId, "NotOwner", nil, nil)
	end
	state.priority = TowerRuntimeDefinitions.nextPriority(state.priority)
	state.revision += 1
	self:_changed(player)
	return result(requestId, "Applied", id, nil)
end

function TowerRuntimeService.sell(
	self: TowerRuntimeService,
	player: Player,
	requestId: string,
	id: string
): TowerRuntimeTypes.ActionResult
	local state = self:_owned(player, id)
	if state == nil then
		return result(requestId, "NotOwner", nil, nil)
	end
	local refund = TowerStatEvaluator.sellValue(state.totalSpent)
	self._economy:grant(player, refund)
	self.Sold:Fire(player, id, state.slot.unit.instanceId, refund)
	self:_remove(state)
	self:_changed(player)
	return result(requestId, "Applied", id, nil)
end

function TowerRuntimeService.sellAll(
	self: TowerRuntimeService,
	player: Player,
	requestId: string
): TowerRuntimeTypes.ActionResult
	local owned = self._byOwner[player.UserId]
	local states: { TowerState } = if owned ~= nil then table.clone(owned) else {}
	local refund = 0
	for _, state in states do
		refund += TowerStatEvaluator.sellValue(state.totalSpent)
		self.Sold:Fire(player, state.id, state.slot.unit.instanceId, 0)
		self:_remove(state)
	end
	self._economy:grant(player, refund)
	self:_changed(player)
	return result(requestId, "Applied", nil, nil)
end

function TowerRuntimeService.snapshot(self: TowerRuntimeService, player: Player): TowerRuntimeTypes.PlayerSnapshot
	local towers: { TowerRuntimeTypes.TowerSnapshot } = {}
	local owned = self._byOwner[player.UserId]
	if owned ~= nil then
		for _, state in owned do
			table.insert(towers, self:_snapshot(state))
		end
	end
	return {
		revision = self._revision[player.UserId] or 0,
		cash = self._economy:get(player),
		selectedTowerId = nil,
		towers = towers,
	}
end

function TowerRuntimeService._step(self: TowerRuntimeService, deltaTime: number): ()
	local dt = self._clock:scaleDelta(deltaTime)
	for _, state in self._states do
		state.cooldownRemaining -= dt
		if state.cooldownRemaining <= 0 then
			self:_attack(state)
		end
	end
end

function TowerRuntimeService._attack(self: TowerRuntimeService, state: TowerState): ()
	self._enemies:queryInto(
		state.position,
		state.stats.range,
		self._query,
		TowerRuntimeDefinitions.MAX_QUERY_CANDIDATES
	)
	local target = TowerTargeting.select(self._query, state.priority)
	if target == nil then
		return
	end
	local targetPosition = Vector3.new(target.position.x, target.position.y, target.position.z)
	local flat = Vector3.new(targetPosition.X, state.position.Y, targetPosition.Z)
	if (flat - state.position).Magnitude > 0.01 then
		state.model:PivotTo(CFrame.lookAt(state.position, flat))
	end
	if state.attackTrack ~= nil then
		state.attackTrack:Play(0.03, 1, self._clock:getTimeScale())
	end
	local attackType = state.slot.definition.attackTypeId
	for _, candidate in self._query do
		local hit = candidate.id == target.id or attackType == "Full"
		if attackType == "Line" then
			local point = Vector3.new(candidate.position.x, candidate.position.y, candidate.position.z)
			local direction = targetPosition - state.position
			local lengthSquared = direction:Dot(direction)
			if lengthSquared > 0 then
				local t = math.clamp((point - state.position):Dot(direction) / lengthSquared, 0, 1.25)
				hit = (point - (state.position + direction * t)).Magnitude <= 2.5
			end
		end
		if hit then
			local outcome = self._enemies:damage(candidate.id, state.stats.damage, state.owner, state.id)
			state.totalDamage += outcome.dealt
			if outcome.dealt > 0 then
				self.Damaged:Fire(state.owner, state.id, state.slot.unit.instanceId, outcome.dealt)
			end
			if outcome.killed then
				state.takedowns += 1
				self._economy:grant(state.owner, outcome.rewardCash)
				self.Takedown:Fire(state.owner, state.id, state.slot.unit.instanceId, outcome.rewardCash)
			end
		end
	end
	state.cooldownRemaining = state.stats.cooldown
	state.revision += 1
end

function TowerRuntimeService._validPlacement(self: TowerRuntimeService, player: Player, position: Vector3): boolean
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root ~= nil and (root.Position - position).Magnitude > TowerRuntimeDefinitions.MAX_PLACEMENT_DISTANCE then
		return false
	end
	for _, state in self._states do
		if (state.position - position).Magnitude < TowerRuntimeDefinitions.MIN_TOWER_SEPARATION then
			return false
		end
	end
	local map = Workspace:FindFirstChild("GameplayMap")
	local zones = if map ~= nil then map:FindFirstChild("PlacementZones") else nil
	if zones == nil then
		return RunService:IsStudio()
	end
	for _, zone in zones:GetDescendants() do
		if zone:IsA("BasePart") and pointInPart(position, zone) then
			return true
		end
	end
	return false
end

function TowerRuntimeService._snapshot(_self: TowerRuntimeService, state: TowerState): TowerRuntimeTypes.TowerSnapshot
	local nextLevel = state.upgradeLevel + 1
	local nextCost = TowerStatEvaluator.upgradeCost(state.slot.deploymentCost, nextLevel)
	return {
		id = state.id,
		ownerUserId = state.owner.UserId,
		unitInstanceId = state.slot.unit.instanceId,
		definitionId = state.slot.definition.id,
		displayName = state.slot.definition.displayName,
		rarityId = state.slot.definition.rarityId,
		attackTypeId = state.slot.definition.attackTypeId,
		iconAssetId = state.slot.definition.iconAssetId,
		upgradeLevel = state.upgradeLevel,
		maxUpgradeLevel = TowerRuntimeDefinitions.MAX_UPGRADE_LEVEL,
		priority = state.priority,
		position = { x = state.position.X, y = state.position.Y, z = state.position.Z },
		yaw = state.yaw,
		stats = table.clone(state.stats),
		nextStats = if nextCost ~= nil then TowerStatEvaluator.atUpgrade(state.slot.stats, nextLevel) else nil,
		upgradeCost = nextCost,
		sellValue = TowerStatEvaluator.sellValue(state.totalSpent),
		totalSpent = state.totalSpent,
		takedowns = state.takedowns,
		totalDamage = math.floor(state.totalDamage + 0.5),
		revision = state.revision,
	}
end

function TowerRuntimeService._owned(self: TowerRuntimeService, player: Player, id: string): TowerState?
	local state = self._byId[id]
	return if state ~= nil and state.owner == player then state else nil
end

function TowerRuntimeService._changed(self: TowerRuntimeService, player: Player): ()
	self._revision[player.UserId] = (self._revision[player.UserId] or 0) + 1
	self.SnapshotChanged:Fire(player)
end

function TowerRuntimeService._remove(self: TowerRuntimeService, state: TowerState): ()
	self._byId[state.id] = nil
	local index = table.find(self._states, state)
	if index ~= nil then
		self._states[index] = self._states[#self._states]
		table.remove(self._states)
	end
	local owner = self._byOwner[state.owner.UserId]
	if owner ~= nil then
		local ownerIndex = table.find(owner, state)
		if ownerIndex ~= nil then
			owner[ownerIndex] = owner[#owner]
			table.remove(owner)
		end
	end
	self._janitor:Remove(`Tower:{state.id}`)
end

function TowerRuntimeService._removeOwner(self: TowerRuntimeService, player: Player): ()
	local owned = self._byOwner[player.UserId]
	local states: { TowerState } = if owned ~= nil then table.clone(owned) else {}
	for _, state in states do
		self:_remove(state)
	end
	self._byOwner[player.UserId] = nil
	self._revision[player.UserId] = nil
end

function TowerRuntimeService._setAnimationSpeed(self: TowerRuntimeService, speed: number): ()
	for _, state in self._states do
		if state.idleTrack ~= nil then
			state.idleTrack:AdjustSpeed(speed)
		end
		if state.attackTrack ~= nil and state.attackTrack.IsPlaying then
			state.attackTrack:AdjustSpeed(speed)
		end
	end
end

return TowerRuntimeService.new()
