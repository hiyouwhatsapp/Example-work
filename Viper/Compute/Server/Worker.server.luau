--!strict
local actor = script:GetActor()
if not actor then return end

local root = game:GetService("ServerScriptService").Viper

local Replay = require(root.Contexts.Replay.Public)
local Contract = require(root.Contexts.Compute.Contract)

local resultEvent = actor.Parent:WaitForChild("Results") :: BindableEvent
local index = actor:GetAttribute("WorkerIndex") :: number
local profiling = actor:GetAttribute("Profiling") == true

actor:BindToMessageParallel("Analyze", function(job: Contract.Job)
	local started = os.clock()
	if profiling then
		debug.profilebegin("Viper.Actor.Analyze")
	end
	local ok, value = pcall(Replay.run, job.recording)
	if profiling then
		debug.profileend()
	end
	local result: Contract.Result = {
		id = job.id,
		success = ok,
		value = if ok then value else nil,
		elapsedSeconds = math.max(0, os.clock() - started),
		errorCode = if ok then nil else "ANALYSIS_FAILED",
	}
	task.synchronize()
	resultEvent:Fire(index, result)
end)

resultEvent:Fire(index, nil)
