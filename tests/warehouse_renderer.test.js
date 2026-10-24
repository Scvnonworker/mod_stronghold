"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname,
    "../ui/mods/stronghold_ui_modules/stronghold_screen_stash_dialog_module.js"), "utf8");

function loadWarehouse(shopPrototype)
{
    const context = vm.createContext({
        StrongholdScreenModuleTemplate: function() {},
        WorldTownScreenShopDialogModule: function() {}
    });
    context.WorldTownScreenShopDialogModule.prototype = shopPrototype;
    vm.runInContext(source, context);
    return Object.create(context.StrongholdScreenStashModule.prototype);
}

function checkForwarding(warehouse, shop)
{
    const owner = "stash";
    const slot = {};
    const item = {id: 123};
    let calls = 0;
    shop.assignItemToSlot = function(actualOwner, actualSlot, actualItem)
    {
        assert.equal(this, warehouse);
        assert.equal(actualOwner, owner);
        assert.equal(actualSlot, slot);
        assert.equal(actualItem, item);
        calls++;
        return "rendered";
    };
    assert.equal(warehouse.assignItemToSlot(owner, slot, item), "rendered");
    assert.equal(calls, 1);
}

test("renderer added by a later Legends UI hook remains available to the warehouse", () => {
    const shop = {};
    const warehouse = loadWarehouse(shop);
    checkForwarding(warehouse, shop);
});

test("an existing vanilla or Legends renderer works without a Legends dependency", () => {
    let warehouse;
    const shop = {assignItemToSlot: function(owner, slot, item) {
        assert.equal(this, warehouse);
        assert.equal(owner, "stash");
        assert.equal(slot, "slot");
        assert.equal(item, "item");
        return "rendered";
    }};
    warehouse = loadWarehouse(shop);
    assert.equal(warehouse.assignItemToSlot("stash", "slot", "item"), "rendered");
});

test("warehouse uses the current renderer after another UI hook replaces it", () => {
    const shop = {assignItemToSlot: function() {
        assert.fail("the renderer captured during loading must not be used");
    }};
    const warehouse = loadWarehouse(shop);
    checkForwarding(warehouse, shop);
});
