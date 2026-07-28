local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Shared pool factory. Every pooled widget in this addon (event bars, day
-- cells, filter chips, agenda rows) is created through this one function so
-- they all get the same Acquire/Release/ReleaseAll semantics from Blizzard's
-- own CreateFramePool primitive instead of three bespoke implementations.
function CalendarPlus:CreatePool(parent, frameType, template, mixin, resetFunc)
	-- resetFunc is NOT handed to CreateFramePool directly: Blizzard's pool
	-- calls the resetter on a brand new frame immediately after creating it
	-- (inside Acquire's CreateNewObject path), before this wrapper gets a
	-- chance to mix in the widget's own Reset method -- so resetFunc's
	-- frame:Reset() call would fail on a frame that has no Reset yet. Mix in
	-- first, then run resetFunc ourselves.
	local pool = CreateFramePool(frameType or "Frame", parent, template)
	local origAcquire = pool.Acquire
	pool.Acquire = function(self)
		local frame, isNew = origAcquire(self)
		if isNew then
			Mixin(frame, mixin)
			if frame.OnPoolAcquire then
				frame:OnPoolAcquire()
			end
		end
		if resetFunc then
			resetFunc(self, frame)
		end
		return frame, isNew
	end
	return pool
end
