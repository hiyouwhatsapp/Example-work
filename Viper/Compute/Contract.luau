--!strict
local Replay = require("../Replay/Public")
local Analysis = require("../Analysis/Public")

export type Job = { id: string, submittedAt: number, expiresAt: number, priority: number, recording: Replay.Recording }
export type Result = {
	id: string,
	success: boolean,
	value: Analysis.Assessment?,
	elapsedSeconds: number,
	errorCode: string?,
}
export type ExecutorHealth = {
	state: "Starting" | "Ready" | "Degraded" | "Stopped",
	total: number,
	ready: number,
	busy: number,
	unavailable: number,
}
export type Executor = {
	submit: (Job) -> boolean,
	poll: () -> Result?,
	available: () -> number,
	destroy: () -> (),
	health: (() -> ExecutorHealth)?,
}
export type PressureReason = "Frame" | "Job" | "Queue" | "Healthy"
export type Governor = {
	observe: (number, number, number, number) -> (number, number, PressureReason),
	tier: () -> number,
	dispatchLimit: () -> number,
}

return table.freeze({ MAX_QUEUE = 32, MAX_WORKERS = 4, MAX_RESULTS = 32, MAX_JOB_SECONDS = 5 })
