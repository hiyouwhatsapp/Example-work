--!strict

local TowerRuntimeTypes = require(script.Parent.TowerRuntimeTypes)

local TowerTargeting = {}

local function better(
	left: TowerRuntimeTypes.TargetCandidate,
	right: TowerRuntimeTypes.TargetCandidate,
	priority: TowerRuntimeTypes.TargetPriority
): boolean
	if priority == "Boss" and left.isBoss ~= right.isBoss then
		return left.isBoss
	end
	if priority == "Last" then
		return left.progress < right.progress or (left.progress == right.progress and left.id < right.id)
	end
	if priority == "Strongest" then
		return left.maxHealth > right.maxHealth
			or (left.maxHealth == right.maxHealth and left.progress > right.progress)
			or (left.maxHealth == right.maxHealth and left.progress == right.progress and left.id < right.id)
	end
	return left.progress > right.progress or (left.progress == right.progress and left.id < right.id)
end

function TowerTargeting.select(
	candidates: { TowerRuntimeTypes.TargetCandidate },
	priority: TowerRuntimeTypes.TargetPriority
): TowerRuntimeTypes.TargetCandidate?
	local selected: TowerRuntimeTypes.TargetCandidate? = nil
	for _, candidate in candidates do
		if candidate.health > 0 and (selected == nil or better(candidate, selected, priority)) then
			selected = candidate
		end
	end
	return selected
end

return table.freeze(TowerTargeting)
