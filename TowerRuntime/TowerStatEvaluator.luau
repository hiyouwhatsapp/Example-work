--!strict

local InventoryTypes = require(script.Parent.Parent.Inventory.InventoryTypes)
local TowerRuntimeDefinitions = require(script.Parent.TowerRuntimeDefinitions)
local TowerRuntimeTypes = require(script.Parent.TowerRuntimeTypes)

local TowerStatEvaluator = {}

local function finite(value: number?): number
	return if value ~= nil and value == value and value > -math.huge and value < math.huge then value else 0
end

function TowerStatEvaluator.atUpgrade(
	stats: InventoryTypes.StatBlock,
	upgradeLevel: number
): TowerRuntimeTypes.CombatStats
	local level = math.clamp(math.floor(upgradeLevel), 0, TowerRuntimeDefinitions.MAX_UPGRADE_LEVEL)
	local multipliers = assert(TowerRuntimeDefinitions.STAT_MULTIPLIERS[level], "Missing tower stat multipliers")
	return {
		damage = math.max(finite(stats.Damage or stats.Power) * multipliers.damage, 0),
		range = math.max(finite(stats.Range) * multipliers.range, 0),
		cooldown = math.max(finite(stats.Cooldown) * multipliers.cooldown, 0.05),
	}
end

function TowerStatEvaluator.upgradeCost(deploymentCost: number, nextUpgradeLevel: number): number?
	local multiplier = TowerRuntimeDefinitions.UPGRADE_COST_MULTIPLIERS[nextUpgradeLevel]
	if multiplier == nil then
		return nil
	end
	return math.max(math.floor(deploymentCost * multiplier + 0.5), 1)
end

function TowerStatEvaluator.sellValue(totalSpent: number): number
	return math.max(math.floor(totalSpent * TowerRuntimeDefinitions.SELL_REFUND_RATIO + 0.5), 0)
end

return table.freeze(TowerStatEvaluator)
