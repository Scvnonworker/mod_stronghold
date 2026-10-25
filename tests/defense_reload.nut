// Run from the repository root with the Battle Brothers mod kit's sq.exe.
::inherit <- function(_path, _body) { return _body; };
::WeakTableRef <- function(_object) { return _object; };
::Const <- { Strings = { Direction8 = ["north"] } };
::Stronghold <- { BaseTiers = { [4] = { BattleCount = 4, Name = "Stronghold" } } };
::Time <- { getVirtualTimeF = function() { return 100.0; } };
::Math <- { rand = function(_min, _max) { return _min; } };

function check(_condition, _message)
{
	if (!_condition) throw _message;
}

function makeStream()
{
	return {
		Data = [], Index = 0,
		writeI32 = function(v) { this.Data.push(v); },
		writeU32 = function(v) { this.Data.push(v); },
		writeF32 = function(v) { this.Data.push(v); },
		writeBool = function(v) { this.Data.push(v); },
		writeString = function(v) { this.Data.push(v); },
		readI32 = function() { return this.Data[this.Index++]; },
		readU32 = function() { return this.Data[this.Index++]; },
		readF32 = function() { return this.Data[this.Index++]; },
		readBool = function() { return this.Data[this.Index++]; },
		readString = function() { return this.Data[this.Index++]; }
	};
}

function makeContract()
{
	dofile("scripts/contracts/contracts/stronghold_defeat_assailant_contract.nut");
	local c = ::stronghold_defeat_assailant_contract;
	c.m.States <- []; c.m.Screens <- []; c.m.BulletpointsObjectives <- [];
	c.m.ActiveState <- null; c.m.ActiveScreen <- null;
	c.createStates(); c.createScreens();
	c.m.TargetLevel = 4; c.m.AttacksRemaining = 4; c.m.TimeOfNextAttack = 10.0;
	c.m.Flags <- { get = function(_key) { return _key == "Introduced"; } };
	c.m.Origin <- { getFlags = function() { return { get = function(_key) { return false; } }; } };
	local tile = { getDirection8To = function(_tile) { return 0; } };
	c.m.Home <- { Tile = tile, getTile = function() { return this.Tile; } };
	c.SpawnCalls <- 0;
	c.World <- {
		Entities = {},
		getEntityByID = function(_id) { return this.Entities[_id]; },
		getTime = function() { return { SecondsPerHour = 1.0 }; },
		State = { getWorldScreen = function() { return { updateContract = function(_contract) {} }; } },
		Contracts = { showActiveContract = function() {} }
	};
	::World <- c.World;
	// Isolate world generation. The real incoming-screen handler and serialization run below.
	c.spawnNewAttackers = function() {
		this.SpawnCalls++;
		local party = {
			ID = this.SpawnCalls,
			isNull = function() { return false; },
			getID = function() { return this.ID; },
			getSprite = function(_name) { return { Visible = false }; },
			getTile = function() { return 0; }
		};
		this.World.Entities[party.ID] <- party;
		this.m.Target = party;
		this.m.HasSpawnedUnit = true;
		this.m.AttacksRemaining--;
	};
	c.setState <- function(_id) {
		foreach (state in this.m.States) {
			if (state.ID != _id) continue;
			this.m.ActiveState = state;
			state.Contract <- this;
			state.start();
			return;
		}
		throw "Unknown state";
	};
	c.setScreen <- function(_id) {
		foreach (screen in this.m.Screens) {
			if (screen.ID != _id) continue;
			this.m.ActiveScreen = screen;
			screen.Contract <- this;
			screen.start();
			return;
		}
		throw "Unknown screen";
	};
	local owner = c;
	c.contract <- {
		onSerialize = function(_out) {
			_out.writeString(owner.m.ActiveScreen.ID);
			_out.writeString(owner.m.ActiveState.ID);
		},
		onDeserialize = function(_in) {
			local screen = _in.readString(); local state = _in.readString();
			// Vanilla contract.onDeserialize restores state, then screen; each calls start().
			owner.setState(state);
			owner.setScreen(screen);
		}
	};
	c.setState("Running");
	c.setScreen("Under_Construction");
	return c;
}

function roundTrip(_contract)
{
	local stream = makeStream();
	_contract.onSerialize(stream);
	_contract.m.Target = null;
	_contract.m.Destination = null;
	_contract.m.AttacksRemaining = -1;
	_contract.m.HasSpawnedUnit = false;
	_contract.m.ActiveScreen = null;
	_contract.m.ActiveState = null;
	_contract.onDeserialize(stream);
	check(stream.Index == stream.Data.len(), "Save stream not fully consumed");
}

function checkObjective(_contract, _count)
{
	check(_contract.m.BulletpointsObjectives[0] == format("Defend against %i more %s", _count, _count == 1 ? "attack." : "attacks."), "Incorrect remaining-defense objective");
}

local c = makeContract();
roundTrip(c);
check(c.SpawnCalls == 0 && c.m.AttacksRemaining == 4, "Load before first wave spawned enemies");
checkObjective(c, 4);
print("PASS: reload before the first invasion\n");

for (local wave = 1; wave <= 4; ++wave)
{
	c.m.TimeOfNextAttack = 0.0;
	c.m.ActiveState.update();
	check(c.m.ActiveScreen.ID == "Enemies_Incoming", "Next wave did not start");
	check(c.SpawnCalls == wave && c.m.AttacksRemaining == 4 - wave, "Wave count incorrect");
	checkObjective(c, 5 - wave);
	local target = c.m.Target;
	for (local reload = 0; reload < 3; ++reload)
	{
		roundTrip(c);
		check(c.SpawnCalls == wave, "Reload spawned duplicate attackers");
		check(c.m.Target == target, "Reload replaced the existing invasion target");
		check(c.m.AttacksRemaining == 4 - wave, "Reload consumed an invasion");
		checkObjective(c, 5 - wave);
	}
	// A victory can be saved before the Running state has shown its victory screen.
	c.m.ActiveState.onCombatVictory("Stronghold");
	local remaining = c.m.AttacksRemaining;
	roundTrip(c);
	check(c.SpawnCalls == wave && c.m.Target == null, "Reload after combat respawned defeated enemies");
	check(c.m.AttacksRemaining == remaining, "Reload after victory consumed next invasion");
	checkObjective(c, 4 - wave);
	c.m.ActiveState.update();
	if (wave < 4)
	{
		check(c.m.ActiveScreen.ID == "Victory_More_Left", "Next-wave victory screen missing");
		roundTrip(c);
		check(c.SpawnCalls == wave, "Victory screen reload spawned enemies");
		checkObjective(c, 4 - wave);
	}
	else
	{
		check(c.m.ActiveScreen.ID == "Victory_None_Left", "Last wave did not complete defense");
		roundTrip(c);
		check(c.SpawnCalls == 4 && c.m.AttacksRemaining == 0, "Final reload changed completed invasion count");
	}
}
print("PASS: four waves, repeated save/load, preserved targets, victory transitions, final wave\n");

// A dead weak reference also must not count as an active invasion or respawn it.
c = makeContract();
c.setScreen("Enemies_Incoming");
c.m.Target = { isNull = function() { return true; } };
c.setScreen("Enemies_Incoming");
check(c.SpawnCalls == 1 && c.m.AttacksRemaining == 3, "Expired target caused duplicate invasion");
checkObjective(c, 3);
print("PASS: expired invasion target\n");
