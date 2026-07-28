local ADDON_NAME, ns = ...

local EventBus = {}
CalendarPlus = CalendarPlus or {}
CalendarPlus.EventBus = EventBus

local listeners = {}

function EventBus:On(eventName, callback)
	listeners[eventName] = listeners[eventName] or {}
	table.insert(listeners[eventName], callback)
end

function EventBus:Off(eventName, callback)
	local list = listeners[eventName]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == callback then
			table.remove(list, i)
		end
	end
end

function EventBus:Fire(eventName, ...)
	local list = listeners[eventName]
	if not list then return end
	for _, callback in ipairs(list) do
		callback(...)
	end
end
