// CHAOS site upgrade tiers - shared class names and the one radius constant.
//
// Both halves of the tier feature have to agree on these or a built structure
// is invisible to the thing that reads it:
//   A3A_fnc_buildingComplete   files the structure into a site's garrison record
//   A3A_fnc_siteTiers          derives the site's tier from that record
//
// SITE_CLAIM_RADIUS is a FLOOR on the marker's own extent, not a replacement
// for it. Resource and factory markers are often smaller than the footprint of
// the site they name, and the RTS placer legitimately puts the warehouse just
// outside the outline, next to the container the player parked.

#define TIER_WAREHOUSE_CLASSES ["a3a_warehouse", "Land_Warehouse_03_F"]
#define TIER_GENERATOR_CLASS "Land_PowerGenerator_F"
#define TIER_STRUCTURE_CLASSES ["a3a_warehouse", "Land_Warehouse_03_F", "Land_PowerGenerator_F"]
#define SITE_CLAIM_RADIUS 150
