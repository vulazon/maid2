--!strict
--!native
--!optimize 2

local Cleaner = {} :: CleanerMethods
Cleaner.__index = Cleaner

type GenericConnection = {Disconnect: (GenericConnection) -> ()}
type GenericObject = {Destroy: (GenericObject) -> ()}
type GenericSignal = {DisconnectAll: (GenericSignal) -> ()}
type NoParameterFunction = () -> ()
export type AcceptedTasks = RBXScriptConnection | Instance | NoParameterFunction | thread | Cleaner | GenericConnection | GenericObject | GenericSignal | any

local TablePool: {any} = {}

local function GetTable(): any
	if #TablePool == 0 then
		return {}
	else
		return table.remove(TablePool)
	end
end

function ReturnTable(tbl)
	TablePool[#TablePool + 1] = tbl
end

type CleanerFields = {Tasks: {AcceptedTasks}}
export type CleanerMethods = {
	__index: CleanerMethods,
	new: () -> Cleaner,
	Add: <T>(self: Cleaner, task_: T & AcceptedTasks) -> T,
	Clear: (self: Cleaner) -> (),
	Cleanup: (self: Cleaner) -> (),
}

export type Cleaner = typeof(setmetatable({} :: CleanerFields, {} :: CleanerMethods))

local DEBUG_MODE = false

local function UnknownTaskTypeMessage(task_: any): string
	return `Unknown task type to clean. Task: {task_} Type: {typeof(task_)}`
end

function Cleaner.new(): Cleaner
	return setmetatable({Tasks = {}} :: CleanerFields, Cleaner)
end

-- Adds a task to the cleaner
function Cleaner.Add(self, task_)
	table.insert(self.Tasks, task_ :: any)
	return task_
end

if DEBUG_MODE then
	Cleaner.Add = function(self, task_)
		local taskType = typeof(task_)
		if taskType == "table" then
			if getmetatable((task_ :: any)) ~= Cleaner and not (task_ :: any).Destroy and not (task_ :: any).Disconnect and not (task_ :: any).DisconnectAll then
				error(UnknownTaskTypeMessage(task_))
			end
		elseif taskType ~= "RBXScriptConnection" and taskType ~= "Instance" and taskType ~= "function" and taskType ~= "thread" then
			error(UnknownTaskTypeMessage(task_))
		end
		table.insert(self.Tasks, task_ :: any)
		return task_
	end
end

-- Releases all references
function Cleaner.Clear(self: Cleaner)
	self.Tasks = {}
end

-- Cleans up all tasks and releases all references
function Cleaner.Cleanup(self: Cleaner)
	local tasks = self.Tasks
	self.Tasks = GetTable()

	local task_: AcceptedTasks
	local taskType: string
	for i=#tasks, 1, -1 do
		task_ = tasks[i]
		tasks[i] = nil
		taskType = typeof(task_)

		if taskType == "RBXScriptConnection" then
			(task_ :: RBXScriptConnection):Disconnect()
		elseif taskType == "Instance" then
			(task_ :: Instance):Destroy()
		elseif taskType == "function" then
			(task_ :: () -> ())()
		elseif taskType == "table" then
			if (task_ :: GenericConnection).Disconnect then
				(task_ :: GenericConnection):Disconnect()
			elseif (task_ :: GenericObject).Destroy then
				(task_ :: GenericObject):Destroy()
			elseif (task_ :: GenericSignal).DisconnectAll then
				(task_ :: GenericSignal):DisconnectAll()
			elseif getmetatable((task_ :: Cleaner)) == Cleaner then
				(task_ :: Cleaner):Cleanup()
			else
				warn(UnknownTaskTypeMessage(task_))
			end
		elseif taskType == "thread" then
			if coroutine.status(task_ :: thread) == "suspended" then
				task.cancel(task_ :: thread)
			end
		else
			warn(UnknownTaskTypeMessage(task_))
		end
	end

	ReturnTable(tasks)
end

return Cleaner