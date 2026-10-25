// Run: sq.exe tests/location_levels.nut <Legends attached_location hook .nut>
// Use the hook from the Legends version under test (including installed ZIPs).
if (vargv.len() != 1) throw "Pass the Legends attached_location hook path";
local legendsHook = vargv[0];

function check(_condition, _message)
{
	if (!_condition) throw _message;
}

::QueueExpression <- null;
::mods_registerMod <- function(_id, _version, _name) {};
::mods_queue <- function(_id, _expression, _callback) { ::QueueExpression = _expression; };
dofile("scripts/!mods_preload/mod_stronghold.nut");
check(::QueueExpression == "mod_msu, >mod_legends", "Stronghold must optionally load after Legends");

::Stronghold.Mod <- { Serialization = {
	flagSerialize = function(_id, _value, _flags) { _flags[_id] <- clone _value; },
	flagDeserialize = function(_id, _default, _object, _flags) {
		return _id in _flags ? clone _flags[_id] : _default;
	}
} };
::mods_hookExactClass <- function(_path, _callback) {
	if (_path == "entity/world/attached_location") _callback(::TestLocation);
};

function fixture()
{
	local o = {
		m = { Flags = {}, IsActive = true, Settlement = null },
		create = function() {},
		getID = function() { return 123; },
		getFlags = function() { return this.m.Flags; },
		isActive = function() { return true; },
		getName = function() { return "Test"; },
		getDescription = function() { return "Test"; },
		setActive = function(_value, _force = false) {},
		setAttackable = function(_value) {},
		onInit = function() {},
		getSprite = function(_name) { return { Color = null }; },
		createColor = function(_value) { return _value; },
		onSerialize = function(_out) {},
		onDeserialize = function(_in) {}
	};
	local owner = o;
	// Represent vanilla's location/attached_location stream layout: flags, settlement, active.
	o.location <- { onDeserialize = function(_in) { owner.m.Flags = clone _in.readFlags(); } };
	o.onSerialize = function(_out) {
		_out.writeFlags(this.m.Flags);
		_out.writeU32(0);
		_out.writeBool(true);
	};
	o.onDeserialize = function(_in) {
		this.location.onDeserialize(_in);
		_in.readU32(); _in.readBool();
	};
	return o;
}

function stream()
{
	return {
		Data = [], Index = 0,
		writeFlags = function(_flags) { this.Data.push(clone _flags); },
		writeU32 = function(_value) { this.Data.push(_value); },
		writeBool = function(_value) { this.Data.push(_value); },
		readFlags = function() { return this.Data[this.Index++]; },
		readU32 = function() { return this.Data[this.Index++]; },
		readBool = function() { return this.Data[this.Index++]; }
	};
}

// Confirm the reported hook order really loses the level before testing the fix.
::TestLocation <- fixture();
dofile("mod_stronghold/hooks/attached_location.nut");
dofile(legendsHook);
// Sprite/world updates are unrelated to persistence; isolate those engine calls.
::TestLocation.setActive = function(_value, _force = false) {};
::TestLocation.create();
::TestLocation.m.Level = 4;
local oldSave = stream();
::TestLocation.onSerialize(oldSave);
::TestLocation.m.Level = 1;
::TestLocation.m.Flags = {};
::TestLocation.onDeserialize(oldSave);
check(::TestLocation.m.Level == 1, "Original hook order no longer reproduces lost level");
check(::TestLocation.m.Flags["123"].Level == 4, "Original save did not retain level metadata");
print("PASS: original hook order saves level 4 but loads level 1\n");

foreach (withLegends in [false, true])
{
	for (local level = 0; level <= 4; ++level)
	{
		::TestLocation = fixture();
		if (withLegends) dofile(legendsHook);
		dofile("mod_stronghold/hooks/attached_location.nut");
		::TestLocation.setActive = function(_value, _force = false) {};
		::TestLocation.create();
		::TestLocation.m.Level = level;
		for (local reload = 0; reload < 3; ++reload)
		{
			local saved = stream();
			::TestLocation.onSerialize(saved);
			::TestLocation.m.Level = 1;
			::TestLocation.m.Flags = {};
			::TestLocation.onDeserialize(saved);
			check(saved.Index == saved.Data.len(), "Location stream layout changed");
			check(::TestLocation.getLevel() == level, "Saved location level did not survive reload");
		}
	}
	print("PASS: levels 0-4 survive repeated save/load, Legends=" + withLegends + "\n");
}

// The hook ordering fix must also read saves created before the fix.
::TestLocation = fixture();
dofile(legendsHook);
dofile("mod_stronghold/hooks/attached_location.nut");
::TestLocation.setActive = function(_value, _force = false) {};
::TestLocation.create();
oldSave.Index = 0;
::TestLocation.onDeserialize(oldSave);
check(::TestLocation.getLevel() == 4, "Could not restore saved level from an older save");
print("PASS: existing saved level restored without changing the save format\n");
