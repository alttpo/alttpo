ROMMapping @rom = null;

// Lookup table of ROM addresses depending on version:
abstract class ROMMapping {
  // MUST be sorted by offs ascending:
  array<SyncableItem@> @syncables = {
    @SyncableItem(0x340, 1, 1, @nameForBow),         // bow
    @SyncableItem(0x341, 1, 1, @nameForBoomerang),   // boomerang
    @SyncableItem(0x342, 1, 1, @nameForHookshot),    // hookshot
    //SyncableItem(0x343, 1, 3),  // bombs (TODO)
    @SyncableItem(0x344, 1, 1, @nameForMushroom),    // mushroom
    @SyncableItem(0x345, 1, 1, @nameForFirerod),     // fire rod
    @SyncableItem(0x346, 1, 1, @nameForIcerod),      // ice rod
    @SyncableItem(0x347, 1, 1, @nameForBombos),      // bombos
    @SyncableItem(0x348, 1, 1, @nameForEther),       // ether
    @SyncableItem(0x349, 1, 1, @nameForQuake),       // quake
    @SyncableItem(0x34A, 1, 1, @nameForLamp),        // lamp/lantern
    @SyncableItem(0x34B, 1, 1, @nameForHammer),      // hammer
    @SyncableItem(0x34C, 1, 1, @nameForFlute),       // flute
    @SyncableItem(0x34D, 1, 1, @nameForBugnet),      // bug net
    @SyncableItem(0x34E, 1, 1, @nameForBook),        // book
    //SyncableItem(0x34F, 1, 1),  // current bottle selection (1-4); do not sync as it locks the bottle selector in place
    @SyncableItem(0x350, 1, 1, @nameForCanesomaria), // cane of somaria
    @SyncableItem(0x351, 1, 1, @nameForCanebyrna),   // cane of byrna
    @SyncableItem(0x352, 1, 1, @nameForMagiccape),   // magic cape
    @SyncableItem(0x353, 1, 1, @nameForMagicmirror), // magic mirror
    @SyncableItem(0x354, 1, @mutateArmorGloves, @nameForGloves),  // gloves
    @SyncableItem(0x355, 1, 1, @nameForBoots),       // boots
    @SyncableItem(0x356, 1, 1, @nameForFlippers),    // flippers
    @SyncableItem(0x357, 1, 1, @nameForMoonpearl),   // moon pearl
    // 0x358 unused
    @SyncableItem(0x359, 1, @mutateSword, @nameForSword),   // sword
    @SyncableItem(0x35A, 1, @mutateShield, @nameForShield),  // shield
    @SyncableItem(0x35B, 1, @mutateArmorGloves, @nameForArmor),   // armor

    // bottle contents 0x35C-0x35F
    @SyncableItem(0x35C, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35D, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35E, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35F, 1, @mutateBottleItem, @nameForBottle),

    @SyncableItem(0x364, 1, 2, @nameForCompass1),  // dungeon compasses 1/2
    @SyncableItem(0x365, 1, 2, @nameForCompass2),  // dungeon compasses 2/2
    @SyncableItem(0x366, 1, 2, @nameForBigkey1),   // dungeon big keys 1/2
    @SyncableItem(0x367, 1, 2, @nameForBigkey2),   // dungeon big keys 2/2
    @SyncableItem(0x368, 1, 2, @nameForMap1),      // dungeon maps 1/2
    @SyncableItem(0x369, 1, 2, @nameForMap2),      // dungeon maps 2/2

    @SyncableHealthCapacity(),  // heart pieces (out of four) [0x36B], health capacity [0x36C]

    @SyncableItem(0x370, 1, 1),  // bombs capacity
    @SyncableItem(0x371, 1, 1),  // arrows capacity

    @SyncableItem(0x374, 1, 2, @nameForPendants),  // pendants
    //SyncableItem(0x377, 1, 1),  // arrows
    @SyncableItem(0x379, 1, 2),  // player ability flags
    @SyncableItem(0x37A, 1, 2, @nameForCrystals),  // crystals

    @SyncableItem(0x37B, 1, 1, @nameForMagic),  // magic usage

    @SyncableItem(0x3C5, 1, @mutateWorldState, @nameForWorldState),  // general progress indicator
    @SyncableItem(0x3C6, 1, @mutateProgress1, @nameForProgress1),  // progress event flags 1/2
    @SyncableItem(0x3C7, 1, 1),  // map icons shown

    //@SyncableItem(0x3C8, 1, 1),  // start at location… options; DISABLED - causes bugs

    // progress event flags 2/2
    @SyncableItem(0x3C9, 1, 2, @nameForProgress2)

    // sentinel null value as last item in array to work around bug where last array item is always nulled out.
    //null

  };
};

class USROMMapping : ROMMapping {
};
