--!strict

local InventoryTypes = require(script.Parent.Parent.Inventory.InventoryTypes)
local TowerRuntimeTypes = require(script.Parent.TowerRuntimeTypes)

local PLACEMENT_LIMITS: { [InventoryTypes.RarityId]: number } = table.freeze({
	Common = 8,
	Uncommon = 7,
	Rare = 6,
	Epic = 5,
	Legendary = 4,
	Mythic = 3,
})

local STAT_MULTIPLIERS = table.freeze({
	[0] = table.freeze({ damage = 1, range = 1, cooldown = 1 }),
	[1] = table.freeze({ damage = 1.22, range = 1.04, cooldown = 0.97 }),
	[2] = table.freeze({ damage = 1.48, range = 1.08, cooldown = 0.94 }),
	[3] = table.freeze({ damage = 1.8, range = 1.13, cooldown = 0.91 }),
	[4] = table.freeze({ damage = 2.18, range = 1.18, cooldown = 0.88 }),
	[5] = table.freeze({ damage = 2.65, range = 1.24, cooldown = 0.84 }),
})

local UPGRADE_COST_MULTIPLIERS = table.freeze({
	[1] = 0.65,
	[2] = 0.9,
	[3] = 1.25,
	[4] = 1.7,
	[5] = 2.3,
})

local PRIORITIES: { TowerRuntimeTypes.TargetPriority } = { "First", "Last", "Strongest", "Boss" }

local TowerRuntimeDefinitions = {
	NETWORK_TAG = "TowerRuntimeContext",
	SNAPSHOT_KEY = "towerRuntimeSnapshot",
	MAX_TOWERS_PER_PLAYER = 64,
	MAX_UPGRADE_LEVEL = 5,
	MAX_QUERY_CANDIDATES = 96,
	MAX_PLACEMENT_DISTANCE = 600,
	MIN_TOWER_SEPARATION = 2.5,
	SELL_REFUND_RATIO = 0.7,
	PLACEMENT_LIMITS = PLACEMENT_LIMITS,
	STAT_MULTIPLIERS = STAT_MULTIPLIERS,
	UPGRADE_COST_MULTIPLIERS = UPGRADE_COST_MULTIPLIERS,
	PRIORITIES = table.freeze(PRIORITIES),
	NETWORK_BUCKET_CAPACITY = 24,
	NETWORK_REFILL_PER_SECOND = 10,
}

function TowerRuntimeDefinitions.placementLimit(rarityId: InventoryTypes.RarityId): number
	return assert(PLACEMENT_LIMITS[rarityId], `Unknown placement rarity: {rarityId}`)
end

function TowerRuntimeDefinitions.nextPriority(
	priority: TowerRuntimeTypes.TargetPriority
): TowerRuntimeTypes.TargetPriority
	local index = table.find(PRIORITIES, priority) or 1
	return PRIORITIES[index % #PRIORITIES + 1]
end

return table.freeze(TowerRuntimeDefinitions)
