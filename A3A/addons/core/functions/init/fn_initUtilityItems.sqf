/*
    Initialize data for buyable items
    Sets global vars A3A_utilityItemList and A3A_utilityItemHM

Arguments: none
Returns: none

Environment: Server, must be called after faction loading
*/

#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

private _fuelDrum = FactionGet(reb,"vehicleFuelDrum");
private _fuelTank = FactionGet(reb,"vehicleFuelTank");
private _medCrate = FactionGet(reb,"vehicleMedicalBox");
private _medTent = FactionGet(reb,"vehicleHealthStation");
private _ammoStation = FactionGet(reb,"vehicleAmmoStation");
private _ammoContainer = FactionGet(reb,"vehicleAmmoContainer");
private _repairStation = FactionGet(reb,"vehicleRepairStation");

// TODO: Name should be stringtabled somewhere

private _items = [
    [FactionGet(reb,"surrenderCrate"), 10, "lootbox", "gear", ["move", "loot"]],
    [_fuelDrum#0, _fuelDrum#1, "fueldrum", "refuel", ["fuel", "move", "save"]],
    [_fuelTank#0, _fuelTank#1, "fueltank", "refuel", ["cmmdr", "fuel", "place", "move", "rotate", "save"]],
    [_medTent#0, _medTent#1, "medicaltent", "heal", ["place", "move", "rotate", "pack"]],
    [_ammoStation#0, _ammoStation#1, "ammostation", "rearm", ["ammo", "place", "move", "rotate", "save"]],
    [_ammoContainer#0, _ammoContainer#1, "ammocontainer", "rearm", ["cmmdr", "ammo", "place", "move", "rotate", "save"]],
    [_repairStation#0, _repairStation#1, "repairstation", "repair", ["cmmdr", "place", "move", "rotate", "pack", "save"]],
    [FactionGet(reb,"vehicleLightSource"), 25, "light", "", ["move"]],           // note: If we do want this saved, need to switch saveLoop to nearObjects
    ["Land_PlasticCase_01_medium_F", 100, "buildboxsmall", "", ["place", "move", "build"]],
    ["Land_PlasticCase_01_large_F", 500, "buildboxmedium", "", ["place", "move", "build"]],
    ["Land_WoodenCrate_01_F", 1500, "buildboxlarge", "", ["place", "move", "build"]],
    ["Land_WoodenCrate_01_stack_x3_F", 2500, "buildboxhuge", "", ["place", "build"]],
    ["Land_WoodenCrate_01_stack_x5_F", 5000, "buildboxmega", "", ["place", "build"]],
    // Military construction kit: the only box that carries the military (basetier) catalogue.
    // "basetier" is read by the placer dialog to unlock those entries, "yardonly" gates the
    // purchase behind an existing Construction Yard. No "move": it is freight, like the other
    // big kits, and has to be driven or flown to where it is needed.
    // Priced below the mega kit on purpose: the box price is also its build budget, so an
    // equally-priced military kit would make the mega kit pointless once a yard exists.
    ["Land_Pallet_MilBoxes_F", 3000, "buildboxmilitary", "", ["place", "build", "basetier", "yardonly"]],
    // Airport construction kit: carries the airport (airtier) infrastructure catalogue.
    // "airtier" is read by the placer dialog, "acconly" gates the purchase behind an
    // existing Air Control Center at HQ.
    ["CargoNet_01_box_F", 4000, "buildboxairport", "", ["place", "build", "airtier", "acconly"]]
//    ["Land_Cargo10_cyan_F", 10000, "buildboxenormous", "", ["place", "build", "hugebuild"]]

];

// CHAOS: site upgrade container. Price -1 keeps it OUT of the purchase list
// (A3A_utilityItemList filters on price >= 0) while keeping it IN the lookup
// hashmap, which is the same mechanism the packed logistics variants use. It is
// spawned by the site upgrade mission and never sold: the effort is the
// delivery, not the purchase. Its build budget is set on the object at spawn
// time as A3A_itemPrice, which fn_lockBuilderBox turns into build money - and
// because fn_lockBuilderBox deletes a box released with nothing left, the
// container disposes of itself once the warehouse is paid for.
// NOT "save": the container is mission scaffolding, not an upgrade. The task's
// own checkpoint records its position and respawns it on load (see
// A3A_Tasks_fnc_ECON_SiteUpgrade), so persisting it as well would put two
// containers at the site after a campaign reload.
_items pushBack ["Land_Cargo10_blue_F", -1, "sitecontainer", "", ["place","noclear","build","sitetier"]];
// CHAOS: the Tier 2 crate. Same blue container family as the Tier 1 box and a
// different subclass of it, so the two missions read as one set of freight while
// staying tellable apart. It exists because Land_PowerGenerator_F is a
// House_Small_F: no PhysX body, no mass, and no slingLoadCargoMemoryPoints
// anywhere in its chain, so the vanilla Sling Load Assistant will never list it
// and no script can make it. Cargo10_base_F declares those memory points and
// sits on ThingX, so the crate flies. The generator is created at the drop point
// when the delivery completes (A3A_Tasks_fnc_ECON_SiteUpgrade).
// Flagged like the Tier 1 container and for the same reasons: NOT "save" -
// it is mission scaffolding whose position the task's own checkpoint records,
// and no "build", because it is not a builder box.
_items pushBack ["Land_Cargo10_light_blue_F", -1, "sitegeneratorcrate", "", ["place","noclear"]];
// The Tier 2 power generator. Registered so that "save" persists it once it has
// been created at the site - it IS the upgrade, so losing it on reload would
// silently downgrade the site. Not buildable and not purchasable: the mission
// creates it out of the crate above.
_items pushBack ["Land_PowerGenerator_F", -1, "sitegenerator", "", ["place","save","noclear"]];

if (LootToCrateRadius == 0) then { _items deleteAt 0 };

if(A3A_hasACE) then {
    _items pushBack [_medCrate#0, _medCrate#1, "medicalbox", "heal", ["noclear", "move"]];
    _items pushBack ["ACE_Wheel", 5, "", "", []];
    _items pushBack ["ACE_Track", 5, "", ""];       // check names
};

// BAR (BuildAndRessources) resource crates and depot.
// noclear is load-bearing: prevents cargo wipe that would empty BAR resource contents.
// No 'move'/'rotate': these are freight, not gear. They move by flatbed or by air only,
// which BAR and Advanced Sling Loading already handle.
// barsupply puts a "resupply nearby crates" action on the depot - BAR itself only ever
// builds out of crates, so without it a depot is inert to the build menu.
// CHAOS: crates are empty freight, the depot is the only source of material.
// "barempty" zeroes a bought crate's contents in fn_initObject, so 250 buys the
// container and nothing else - material comes from the depot, which is filled by
// connected factories (A3A_fnc_factoryDepotTick) and emptied into crates by the
// depot's own resupply action (A3A_fnc_barResupply). Buying a full crate outright
// would have made that whole loop optional.
//
// The depot is BUILT, not bought: it lives in the general construction catalogue
// (fn_initBuildableObjects) and is gated there on A3A_fnc_hasConstructionYard, so
// BAR material is a Construction Yard capability like the military and airport
// build kits. That does make BAR a late-game system: before the yard there is no
// depot, so there is no material at all. Deliberate - trenches and the
// small/medium/large build boxes carry the early game.
//
// Its item entry stays, priced -1: A3A_utilityItemList filters on price >= 0 so it
// is unpurchasable, while A3A_utilityItemHM keeps it, and that hashmap membership
// is load-bearing three times over.
//   1. fn_garrisonServer_addVehicle files a utility item under "vehicles" rather
//      than "buildings", which is the array fn_spawnGarrisonVehicles respawns
//      through fn_AIVEHinit -> fn_initObject. Drop the entry and a saved depot
//      comes back as a bare prop with no resupply action.
//   2. "barsupply" is read by fn_initObjectRemote, so the action follows from the
//      same registration on both the build and the respawn path.
//   3. "noclear" keeps BAR's cargo intact, and "save" installs the attach/detach
//      handler so a sling-loaded depot re-garrisons where it lands.
//
// Crates must NOT be removed even though they are empty: BAR builds only ever
// draw from a crate, so a depot with no crate near it is inert to the build menu.
if (A3A_hasBAR) then {
    _items pushBack ["RessourceCrate_Concrete", 250, "barcrate_concrete", "", ["place","save","noclear","barempty"]];
    _items pushBack ["RessourceCrate_Metal",    250, "barcrate_metal",    "", ["place","save","noclear","barempty"]];
    _items pushBack ["RessourceCrate_Sand",     250, "barcrate_sand",     "", ["place","save","noclear","barempty"]];
    _items pushBack ["RessourceCrate_Wood",     250, "barcrate_wood",     "", ["place","save","noclear","barempty"]];
    _items pushBack ["RessourceDepot",           -1, "bardepot",          "", ["cmmdr","place","save","noclear","barsupply"]];
};

// Apply item name localization
{
    if (_x#2 == "") then { continue };
    _x set [2, localize ("STR_A3A_Utility_Items_Name_" + _x#2)];
} forEach _items;

// Add packed variants so that they can be initialized properly
{
    private _packClass = getText (configFile >> "A3A" >> "A3A_Logistics_Packable" >> _x#0 >> "packObject");
    if (_packClass == "") then { Error_1("Packable item %1 has no packed object", _x#0); continue };
    _items pushBack [_packClass, -1, "", "", ["move", "unpack"]];
} forEach (_items select { "pack" in _x#4 });

A3A_utilityItemList = _items select { _x#1 >= 0 } apply { _x#0 };
A3A_utilityItemHM = (_items apply { _x#0 }) createHashMapFromArray _items;
