--!strict
local Contract = require("../Contract")
local Queue = require("../../../Core/Queue")
local Lifetime = require("../../../Core/Lifetime")
local Metrics = require("../../Observability/Public")

type Worker = { actor: Actor, ready: boolean, jobId: string?, assignedAt: number }

local ActorExecutor = {}

function ActorExecutor.new(
	parent: Instance,
	template: Script,
	count: number,
	metrics: Metrics.Metrics
): Contract.Executor
	assert(count % 1 == 0 and count >= 1 and count <= Contract.MAX_WORKERS, "invalid Actor count")
	assert(template.Archivable, "worker template must be archivable")
	local owned = Lifetime.new()
	local folder = Instance.new("Folder")
	folder.Name = "ViperWorkers"
	owned.add(function()
		folder:Destroy()
	end)
	local workers: { Worker } = {}
	local results: Queue.Queue<Contract.Result> = Queue.new(Contract.MAX_RESULTS)
	local closed = false
	local createdAt = os.clock()
	local ok = pcall(function()
		local resultEvent = Instance.new("BindableEvent")
		resultEvent.Name = "Results"
		resultEvent.Parent = folder
		local connection = resultEvent.Event:Connect(function(index: number, result: Contract.Result?)
			if closed then
				return
			end
			local worker = workers[index]
			if not worker then
				metrics.add("jobsLate")
				return
			end
			if result == nil then
				worker.ready = true
				return
			end
			if worker.jobId ~= result.id then
				metrics.add("jobsLate")
				return
			end
			worker.jobId = nil
			if not results.push(result) then
				metrics.add("resultsDropped")
			end
		end)
		owned.add(function()
			connection:Disconnect()
		end)
		for i = 1, count do
			local actor = Instance.new("Actor")
			actor.Parent = folder
			actor.Name = "Worker" .. tostring(i)
			actor:SetAttribute("WorkerIndex", i)
			actor:SetAttribute("Profiling", metrics.profiling)
			local copy = template:Clone()
			copy.Name, copy.Enabled, copy.Parent = "Worker", true, actor
			workers[i] = { actor = actor, ready = false, jobId = nil, assignedAt = 0 }
		end
		folder.Parent = parent
	end)
	if not ok then
		owned.destroy()
		error("ACTOR_STARTUP_FAILED", 0)
	end
	local function alive(worker: Worker): boolean
		return not closed and folder.Parent == parent and worker.actor.Parent == folder
	end
	return table.freeze({
		submit = function(job: Contract.Job): boolean
			if closed then
				return false
			end
			for _, worker in workers do
				if alive(worker) and worker.ready and worker.jobId == nil then
					worker.jobId, worker.assignedAt = job.id, os.clock()
					worker.actor:SendMessage("Analyze", job)
					return true
				end
			end
			return false
		end,
		poll = results.pop,
		available = function(): number
			local available = 0
			for _, worker in workers do
				if alive(worker) and worker.ready and worker.jobId == nil then
					available += 1
				end
			end
			return available
		end,
		health = function(): Contract.ExecutorHealth
			local ready, busy, unavailable = 0, 0, 0
			local now = os.clock()
			for _, worker in workers do
				if alive(worker) then
					if worker.ready then
						ready += 1
					end
					if worker.jobId then
						busy += 1
					end
					if (not worker.ready and now - createdAt >= 5) or (worker.jobId ~= nil and now - worker.assignedAt >= Contract.MAX_JOB_SECONDS) then
						unavailable += 1
					end
				else
					unavailable += 1
				end
			end
			local snapshot: Contract.ExecutorHealth = {
				state = if closed
					then "Stopped"
					elseif unavailable > 0 then "Degraded"
					elseif ready < count then "Starting"
					else "Ready",
				total = count,
				ready = ready,
				busy = busy,
				unavailable = unavailable,
			}
			return table.freeze(snapshot)
		end,
		destroy = function()
			if closed then
				return
			end
			closed = true
			owned.destroy()
			results.clear()
			table.clear(workers)
		end,
	})
end

return table.freeze(ActorExecutor)
