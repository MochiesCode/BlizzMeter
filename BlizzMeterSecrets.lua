local _, BlizzMeterPrivate = ...;

-- While combat addon restrictions are active, C_DamageMeter returns most of its data
-- (amounts, durations, GUIDs, names, ...) as secret values. Addon code may store secrets,
-- pass them around, concatenate and string.format them, and hand them to widgets
-- (SetText, SetValue, SetMinMaxValues) and to APIs that accept them (AbbreviateLargeNumbers,
-- C_Spell.GetSpellName, C_StringUtil.WrapString, ...). It may not compare them, do arithmetic
-- on them, take their length, use them as table keys, or test secret booleans.
--
-- The Blizzard meter runs untainted, so its code never has to care. Every place where this
-- addon departs from the Blizzard source to cope with secrets is marked "BlizzMeter:".

local issecretvalue = issecretvalue;
local canaccesstable = canaccesstable;

function BlizzMeterPrivate.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value);
end

-- Returns the table if addon code is allowed to read it, or nil otherwise.
function BlizzMeterPrivate.AccessibleTableOrNil(value)
	if type(value) ~= "table" then
		return nil;
	end

	if canaccesstable ~= nil and not canaccesstable(value) then
		return nil;
	end

	return value;
end
