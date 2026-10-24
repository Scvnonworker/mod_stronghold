// Run from the repository root with the Battle Brothers mod kit's sq.exe.
// Load the real module before Legends extends item types, as happens in game.
::inherit <- function(_path, _body) { return _body; };

function check(_condition, _message)
{
	if (!_condition) throw _message;
}

function runCase(_extensions)
{
	::Const <- {
		Items = {
			ItemFilter = { All = 4194303, Weapons = 2048 },
			ItemType = { Food = 524288, Usable = 131072, Weapon = 2048 }
		},
		UI = { ItemOwner = { Stash = 1 } }
	};

	dofile("scripts/ui/screens/stronghold/modules/stronghold_screen_stash_module.nut");
	local module = ::stronghold_screen_stash_module;
	for (local i = 0; i < _extensions; ++i)
	{
		foreach (key, value in ::Const.Items.ItemType)
			::Const.Items.ItemType[key] = value << 1;
		foreach (key, value in ::Const.Items.ItemFilter)
			::Const.Items.ItemFilter[key] = value << 1;
		::Const.Items.ItemFilter.All = ::Const.Items.ItemFilter.All | 1;
	}

	local items = [];
	for (local i = 0; i < 7; ++i) items.push(::Const.Items.ItemType.Food);
	items.push(::Const.Items.ItemType.Usable); // map
	items.push(::Const.Items.ItemType.Weapon);
	local stash = {
		Items = items,
		getItems = function() { return this.Items; },
		getNumberOfFilledSlots = function() { return this.Items.len(); },
		getCapacity = function() { return 20; },
		sort = function() {}
	};
	::Stash <- stash;
	module.getStash = function() { return ::Stash; };
	module.getTown <- function() {
		return { getLocation = function(_name) { return null; } };
	};
	module.UIDataHelper <- {
		// Match vanilla data_helper's mask and slot-preserving conversion contract.
		convertItemsToUIData = function(_items, _target, _owner = null, _filter = 0) {
			if (_filter == 0) _filter = ::Const.Items.ItemFilter.All;
			foreach (itemType in _items)
				_target.push((itemType & _filter) != 0 ? itemType : null);
		},
		convertStashToUIData = function(_ignoreLocked = false, _filter = 0) {
			local result = [];
			this.convertItemsToUIData(::Stash.getItems(), result, null, _filter);
			return result;
		}
	};
	module.updateData <- function() {};
	module.m.JSHandle <- {
		LastData = null,
		asyncCall = function(_method, _data) { this.LastData = _data; }
	};

	local data = module.getUIData({});
	foreach (key in ["Stash", "Shop"])
	{
		check(data[key].len() == 9, "Initial view changed slot count");
		foreach (item in data[key]) check(item != null, "Initial All view hides food or map");
	}
	module.onSortButtonClicked();
	data = module.getUIData({});
	foreach (item in data.Stash) check(item != null, "Sorting hides items");
	module.loadStashList();
	foreach (item in module.m.JSHandle.LastData.Stash)
		check(item != null, "Refreshing stash hides items");

	module.onFilterWeapons();
	data = module.getUIData({});
	for (local i = 0; i < 8; ++i)
		check(data.Stash[i] == null, "Weapon filter includes food or map");
	check(data.Stash[8] != null, "Weapon filter hides weapon");
	module.onSortButtonClicked();
	check(module.m.InventoryFilter == ::Const.Items.ItemFilter.Weapons, "Sorting resets selected filter");
	module.onFilterAll();
	data = module.getUIData({});
	foreach (item in data.Stash) check(item != null, "All button hides items");
	print("PASS: warehouse filter with " + _extensions + " added item types\n");
}

runCase(0); // vanilla
runCase(6); // installed Legends 19.4.22
