--!strict

local InventoryTypes = require(script.Parent.Parent.Inventory.InventoryTypes)

export type TargetPriority = "First" | "Last" | "Strongest" | "Boss"
export type TowerActionStatus =
	"Applied"
	| "Unchanged"
	| "Invalid"
	| "Unavailable"
	| "NotOwner"
	| "InsufficientFunds"
	| "PlacementBlocked"
	| "PlacementLimit"
	| "MaxUpgrade"

export type Position = {
	x: number,
	y: number,
	z: number,
}

export type PlacementRequest = Position & {
	requestId: string,
	loadoutSlot: number,
	yaw: number,
}

export type ActionResult = {
	requestId: string,
	status: TowerActionStatus,
	message: string?,
	towerId: string?,
}

export type CombatStats = {
	damage: number,
	range: number,
	cooldown: number,
}

export type TowerSnapshot = {
	id: string,
	ownerUserId: number,
	unitInstanceId: string,
	definitionId: string,
	displayName: string,
	rarityId: InventoryTypes.RarityId,
	attackTypeId: InventoryTypes.AttackTypeId,
	iconAssetId: number?,
	upgradeLevel: number,
	maxUpgradeLevel: number,
	priority: TargetPriority,
	position: Position,
	yaw: number,
	stats: CombatStats,
	nextStats: CombatStats?,
	upgradeCost: number?,
	sellValue: number,
	totalSpent: number,
	takedowns: number,
	totalDamage: number,
	revision: number,
}

export type PlayerSnapshot = {
	revision: number,
	cash: number,
	selectedTowerId: string?,
	towers: { TowerSnapshot },
}

export type TargetCandidate = {
	id: string,
	position: Position,
	progress: number,
	health: number,
	maxHealth: number,
	isBoss: boolean,
}

return table.freeze({})
