--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lifecycle = require(ReplicatedStorage.Shared.Core.Lifecycle)
local TowerRuntimeDefinitions = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerRuntimeDefinitions)
local TowerRuntimeTypes = require(ReplicatedStorage.Shared.Contexts.TowerRuntime.TowerRuntimeTypes)
local Janitor = require(ReplicatedStorage.Shared.Packages.Janitor)
local Networker = require(ReplicatedStorage.Shared.Packages.Networker)

type Rate = { tokens: number, updatedAt: number }
local TowerRuntimeNetworkService = {}
TowerRuntimeNetworkService.__index = TowerRuntimeNetworkService
export type TowerRuntimeNetworkService = typeof(setmetatable({} :: { _janitor: any, _networker: any, _towers: any, _rate: { [number]: Rate } }, TowerRuntimeNetworkService))

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 64
end
function TowerRuntimeNetworkService.new(): TowerRuntimeNetworkService
	return setmetatable(
		{ _janitor = Janitor.new(), _networker = nil :: any, _towers = nil :: any, _rate = {} },
		TowerRuntimeNetworkService
	)
end
function TowerRuntimeNetworkService.OnStart(self: TowerRuntimeNetworkService): ()
	self._towers = Lifecycle.resolve("TowerRuntimeService")
	local access: any = {
		self.requestSnapshot :: any,
		self.requestPlace :: any,
		self.requestUpgrade :: any,
		self.requestPriority :: any,
		self.requestSell :: any,
		self.requestSellAll :: any,
	}
	local networker = Networker.server.new(TowerRuntimeDefinitions.NETWORK_TAG, self :: any, access)
	self._networker = networker
	self._janitor:Add(networker, "destroy", "Networker")
	self._janitor:Add(
		self._towers.SnapshotChanged:Connect(function(player: Player)
			self:_push(player)
		end),
		"Disconnect",
		"Changed"
	)
	self._janitor:Add(
		Players.PlayerRemoving:Connect(function(player)
			self._rate[player.UserId] = nil
		end),
		"Disconnect",
		"Removing"
	)
end
function TowerRuntimeNetworkService.requestSnapshot(self: TowerRuntimeNetworkService, player: Player): ()
	if self:_consume(player, 0.25) then
		self:_push(player)
	end
end
function TowerRuntimeNetworkService.requestPlace(self: TowerRuntimeNetworkService, player: Player, raw: any): ()
	if
		not self:_consume(player, 2)
		or type(raw) ~= "table"
		or not validId(raw.requestId)
		or type(raw.loadoutSlot) ~= "number"
		or raw.loadoutSlot % 1 ~= 0
		or type(raw.x) ~= "number"
		or type(raw.y) ~= "number"
		or type(raw.z) ~= "number"
		or type(raw.yaw) ~= "number"
	then
		return
	end
	self:_action(
		player,
		self._towers:place(
			player,
			{ requestId = raw.requestId, loadoutSlot = raw.loadoutSlot, x = raw.x, y = raw.y, z = raw.z, yaw = raw.yaw }
		)
	)
end
function TowerRuntimeNetworkService.requestUpgrade(
	self: TowerRuntimeNetworkService,
	player: Player,
	requestId: any,
	id: any
): ()
	if self:_valid(player, requestId, id, 1) then
		self:_action(player, self._towers:upgrade(player, requestId, id))
	end
end
function TowerRuntimeNetworkService.requestPriority(
	self: TowerRuntimeNetworkService,
	player: Player,
	requestId: any,
	id: any
): ()
	if self:_valid(player, requestId, id, 0.5) then
		self:_action(player, self._towers:cyclePriority(player, requestId, id))
	end
end
function TowerRuntimeNetworkService.requestSell(
	self: TowerRuntimeNetworkService,
	player: Player,
	requestId: any,
	id: any
): ()
	if self:_valid(player, requestId, id, 1) then
		self:_action(player, self._towers:sell(player, requestId, id))
	end
end
function TowerRuntimeNetworkService.requestSellAll(self: TowerRuntimeNetworkService, player: Player, requestId: any): ()
	if validId(requestId) and self:_consume(player, 4) then
		self:_action(player, self._towers:sellAll(player, requestId))
	end
end
function TowerRuntimeNetworkService._push(self: TowerRuntimeNetworkService, player: Player): ()
	if player.Parent == Players then
		self._networker:set(player, TowerRuntimeDefinitions.SNAPSHOT_KEY, self._towers:snapshot(player))
	end
end
function TowerRuntimeNetworkService._action(
	self: TowerRuntimeNetworkService,
	player: Player,
	value: TowerRuntimeTypes.ActionResult
): ()
	if player.Parent == Players then
		self._networker:fire(player, "onTowerAction", value)
		self:_push(player)
	end
end
function TowerRuntimeNetworkService._valid(
	self: TowerRuntimeNetworkService,
	player: Player,
	requestId: any,
	id: any,
	cost: number
): boolean
	return validId(requestId) and validId(id) and self:_consume(player, cost)
end
function TowerRuntimeNetworkService._consume(self: TowerRuntimeNetworkService, player: Player, cost: number): boolean
	local now = os.clock()
	local state = self._rate[player.UserId]
	if state == nil then
		state = { tokens = TowerRuntimeDefinitions.NETWORK_BUCKET_CAPACITY, updatedAt = now }
		self._rate[player.UserId] = state
	end
	state.tokens = math.min(
		TowerRuntimeDefinitions.NETWORK_BUCKET_CAPACITY,
		state.tokens + (now - state.updatedAt) * TowerRuntimeDefinitions.NETWORK_REFILL_PER_SECOND
	)
	state.updatedAt = now
	if state.tokens < cost then
		return false
	end
	state.tokens -= cost
	return true
end
return TowerRuntimeNetworkService.new()
