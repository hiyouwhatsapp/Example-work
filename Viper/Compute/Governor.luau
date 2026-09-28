--!strict
local Contract = require("./Contract")
local Governor = {}

function Governor.new(): Contract.Governor
	local tier, healthyFor = 1, 0

	return table.freeze({
		observe = function(
			frameSeconds: number,
			queueFraction: number,
			jobSeconds: number,
			delta: number
		): (number, number, Contract.PressureReason)

			local pressure = 1
			if frameSeconds ~= frameSeconds or frameSeconds >= 0.1 then
				pressure = 5
			elseif frameSeconds >= 0.05 or jobSeconds >= 0.02 then
				pressure = 4
			elseif frameSeconds >= 0.035 or jobSeconds >= 0.008 then
				pressure = 3
			elseif frameSeconds >= 0.025 or jobSeconds >= 0.004 or queueFraction >= 0.75 then
				pressure = 2
			end
			local reason: Contract.PressureReason = "Healthy"
			if
				frameSeconds ~= frameSeconds
				or frameSeconds >= 0.1
				or (pressure == 4 and frameSeconds >= 0.05)
				or (pressure == 3 and frameSeconds >= 0.035)
				or (pressure == 2 and frameSeconds >= 0.025)
			then
				reason = "Frame"
			elseif
				(pressure == 4 and jobSeconds >= 0.02)
				or (pressure == 3 and jobSeconds >= 0.008)
				or (pressure == 2 and jobSeconds >= 0.004)
			then
				reason = "Job"
			elseif pressure == 2 then
				reason = "Queue"
			end
			if pressure > tier then
				tier, healthyFor = pressure, 0
			elseif pressure < tier then
				healthyFor += math.clamp(delta, 0, 0.1)
				if healthyFor >= 3 then
					tier -= 1
					healthyFor = 0
				end
			else
				healthyFor = 0
			end
			return tier, pressure, reason
		end,

		tier = function(): number
			return tier
		end,

		dispatchLimit = function(): number
			if tier >= 4 then
				return 0
			end
			return if tier == 1 then 2 else 1
		end,
	})
end

return table.freeze(Governor)
