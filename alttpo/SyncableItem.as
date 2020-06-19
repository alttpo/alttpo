
funcdef uint16 ItemMutate(uint16 oldValue, uint16 newValue);

funcdef void NotifyItemReceived(const string &in name);
funcdef void NotifyNewItems(uint16 oldValue, uint16 newValue, NotifyItemReceived @notify);

// list of SRAM values to sync as items:
class SyncableItem {
  uint16  offs;   // SRAM offset from $7EF000 base address
  uint8   size;   // 1 - byte, 2 - word
  uint8   type;   // 0 - custom mutate, 1 - highest wins, 2 - bitfield, 3+ TBD...
  ItemMutate @mutate = null;
  NotifyNewItems @notifyNewItems = null;

  SyncableItem(uint16 offs, uint8 size, uint8 type, NotifyNewItems @notifyNewItems = null) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.notifyNewItems = notifyNewItems;
  }

  SyncableItem(uint16 offs, uint8 size, ItemMutate @mutate, NotifyNewItems @notifyNewItems = null) {
    this.offs = offs;
    this.size = size;
    this.type = 0;
    @this.mutate = mutate;
    @this.notifyNewItems = notifyNewItems;
  }

  uint16 oldValue;
  uint16 newValue;
  void start() {
    oldValue = readRAM();
    newValue = oldValue;
  }

  void apply(GameState @remote) {
    auto remoteValue = read(remote.sram);
    newValue = modify(newValue, remoteValue);
  }

  void finish(NotifyItemReceived @notifyItemReceived = null) {
    if (newValue != oldValue) {
      if (!(notifyNewItems is null) && !(notifyItemReceived is null)) {
        notifyNewItems(oldValue, newValue, notifyItemReceived);
      }
      write(newValue);
    }
  }

  uint16 modify(uint16 oldValue, uint16 newValue) {
    if (type == 0) {
      if (@this.mutate is null) {
        return oldValue;
      }
      return this.mutate(oldValue, newValue);
    } else if (type == 1) {
      // max value:
      if (newValue > oldValue) {
        return newValue;
      }
      return oldValue;
    } else if (type == 2) {
      // bitfield OR:
      newValue = oldValue | newValue;
      return newValue;
    }
    return oldValue;
  }

  uint16 readRAM() {
    if (size == 1) {
      return bus::read_u8(0x7EF000 + offs);
    } else {
      return bus::read_u16(0x7EF000 + offs);
    }
  }

  uint16 read(const array<uint8> &in sram) {
    if (size == 1) {
      return sram[offs];
    } else {
      return uint16(sram[offs]) | (uint16(sram[offs+1]) << 8);
    }
  }

  void write(uint16 newValue) {
    if (size == 1) {
      bus::write_u8(0x7EF000 + offs, uint8(newValue));
    } else if (size == 2) {
      bus::write_u16(0x7EF000 + offs, newValue);
    }
  }
};

class SyncableHealthCapacity : SyncableItem {
  SyncableHealthCapacity() {
    super(0x36C, 1, 0);

    // this custom SyncableItem covers both:
    // SyncableItem(0x36B, 1, 1),  // heart pieces (out of four)
    // SyncableItem(0x36C, 1, 1),  // health capacity
  }

  uint16 modify(uint16 oldValue, uint16 newValue) override {
    // max value:
    if (newValue > oldValue) {
      return newValue;
    }
    return oldValue;
  }

  void finish(NotifyItemReceived @notifyItemReceived = null) override {
    if (newValue != oldValue) {
      if (!(notifyItemReceived is null)) {
        auto oldHearts = uint8(oldValue) & ~uint8(7);
        auto oldPieces = uint8(oldValue) & uint8(3);
        auto newHearts = uint8(newValue) & ~uint8(7);
        auto newPieces = uint8(newValue) & uint8(3);

        auto diffHearts = (newHearts + (newPieces << 1)) - (oldHearts + (oldPieces << 1));
        auto fullHearts = diffHearts >> 3;
        auto pieces = (diffHearts & 7) >> 1;

        string hc;
        if (fullHearts == 1) {
          hc = "1 new heart";
        } else if (fullHearts > 1) {
          hc = fmtInt(fullHearts) + " new hearts";
        }
        if (fullHearts >= 1 && pieces >= 1) hc += ", ";

        if (pieces == 1) {
          hc += "1 new heart piece";
        } else if (pieces > 0) {
          hc += fmtInt(pieces) + " new heart pieces";
        }

        notifyItemReceived(hc);
      }
      write(newValue);
    }
  }

  uint16 readRAM() override {
    return (bus::read_u8(0x7EF36C) & ~7) | (bus::read_u8(0x7EF36B) & 3);
  }

  uint16 read(const array<uint8> &in sram) override {
    // this works because [0x36C] is always a multiple of 8 and the lower 3 bits are always zero
    // and [0x36B] is in the range [0..3] aka 2 bits:
    return (sram[0x36C] & ~7) | (sram[0x36B] & 3);
  }

  void write(uint16 newValue) override {
    // split out the full hearts from the heart pieces:
    auto hearts = uint8(newValue) & ~uint8(7);
    auto pieces = uint8(newValue) & uint8(3);
    //message("heart write! " + fmtHex(uint8(oldValue),2) + " -> " + fmtHex(uint8(newValue),2) + " = " + fmtInt(hearts) + ", " + fmtInt(pieces));
    bus::write_u8(0x7EF36C, hearts);
    bus::write_u8(0x7EF36B, pieces);
  }
}

uint16 mutateWorldState(uint16 oldValue, uint16 newValue) {
  // if local player is in the intro sequence, keep them there:
  if (oldValue < 2) return oldValue;

  // sync the bigger value:
  if (newValue > oldValue) return newValue;
  return oldValue;
}

uint16 mutateProgress1(uint16 oldValue, uint16 newValue) {
  // don't sync progress bits unless we're past the escape sequence; too many opportunities for soft-locks:
  auto worldState = bus::read_u8(0x7EF000 + 0x3C5);
  if (worldState < 2) {
    return oldValue;
  }

  // if local player has not grabbed gear from uncle, then keep uncle alive in the secret passage otherwise Zelda's
  // telepathic prompts will get rather annoying.
  if (oldValue & 0x01 == 0) {
    newValue &= ~uint8(0x01);
  }
  // if local player has not achieved uncle leaving house, leave it cleared otherwise link never wakes up.
  if (oldValue & 0x10 == 0) {
    newValue &= ~uint8(0x10);
  }
  return newValue | oldValue;
}

uint16 mutateSword(uint16 oldValue, uint16 newValue) {
  // during the dwarven swordsmith quest, sword goes to 0xFF when taken away, so avoid that trap:
  if (newValue >= 1 && newValue <= 4 && newValue > oldValue) {
    // JSL DecompSwordGfx
    pb.jsl(rom.fn_decomp_sword_gfx);
    pb.jsl(rom.fn_sword_palette);
    return newValue;
  }
  return oldValue;
}

uint16 mutateShield(uint16 oldValue, uint16 newValue) {
  if (newValue > oldValue) {
    // JSL DecompShieldGfx
    pb.jsl(rom.fn_decomp_shield_gfx);
    pb.jsl(rom.fn_shield_palette);
    return newValue;
  }
  return oldValue;
}

// NOTE: this is called for both gloves and armor separately so could JSL twice in succession for one frame.
uint16 mutateArmorGloves(uint16 oldValue, uint16 newValue) {
  if (newValue > oldValue) {
    // JSL Palette_ChangeGloveColor
    pb.jsl(rom.fn_armor_glove_palette);
    return newValue;
  }
  return oldValue;
}

uint16 mutateBottleItem(uint16 oldValue, uint16 newValue) {
  // only sync gaining a new bottle: 0 = no bottle, 2 = empty bottle.
  if (oldValue == 0 && newValue != 0) return newValue;
  return oldValue;
}

uint16 mutateZeroToNonZero(uint16 oldValue, uint16 newValue) {
  // Allow if replacing 'no item':
  if (oldValue == 0 && newValue != 0) return newValue;
  return oldValue;
}

uint16 mutateFlute(uint16 oldValue, uint16 newValue) {
  // Allow if replacing 'no item':
  if (oldValue == 0 && newValue != 0) return newValue;
  // Allow if replacing 'flute' with 'bird+flute':
  if (oldValue == 2 && newValue == 3) return newValue;
  return oldValue;
}

const uint8 bitPowder   = 1<<4;
const uint8 bitMushroom = 1<<5;

uint16 mutateRandomizerItems(uint16 oldValue, uint16 newValue) {
  // INVENTORY_SWAP = "$7EF38C"
  // Item Tracking Slot
  // brmpnskf
  // b = blue boomerang
  // r = red boomerang
  // m = mushroom current
  // p = magic powder
  // n = mushroom past
  // s = shovel
  // k = fake flute
  // f = working flute

  uint8 mushroom = bus::read_u8(0x7EF344);
  // if gaining powder and have no inventory:
  if (
    ((oldValue & bitPowder) == 0) &&
    ((newValue & bitPowder) == bitPowder) &&
    mushroom == 0
  ) {
    // set powder in inventory:
    bus::write_u8(0x7EF344, 2);
  }

  // if gaining mushroom and have no inventory:
  if (
    ((oldValue & bitMushroom) == 0) &&
    ((newValue & bitMushroom) == bitMushroom) &&
    mushroom == 0
  ) {
    // set mushroom in inventory:
    bus::write_u8(0x7EF344, 1);
  }

  //// if had mushroom and lost mushroom:
  //if (
  //  ((oldValue & bitMushroom) == bitMushroom) &&
  //  ((newValue & bitMushroom) == 0) &&
  //  mushroom == 1
  //) {
  //  // if don't have powder, set to empty:
  //  if ((oldValue & bitPowder) == 0) {
  //    bus::write_u8(0x7EF344, 0);
  //  } else {
  //    // else set powder in inventory:
  //    bus::write_u8(0x7EF344, 2);
  //  }
  //}

  return oldValue | newValue;
}

void notifySingleItem(const array<string> @names, NotifyItemReceived @notify, uint16 new) {
  if (new == 0) return;

  new--;
  if (new >= names.length()) return;

  notify(names[new]);
}

const array<string> @bowNames         = {"Bow", "Bow", "Bow w/ Silver Arrows"};
const array<string> @boomerangNames   = {"Blue Boomerang", "Red Boomerang"};
const array<string> @hookshotNames    = {"Hookshot"};
const array<string> @mushroomNames    = {"Mushroom", "Magic Powder"};
const array<string> @firerodNames     = {"Fire Rod"};
const array<string> @icerodNames      = {"Ice Rod"};
const array<string> @bombosNames      = {"Bombos Medallion"};
const array<string> @etherNames       = {"Ether Medallion"};
const array<string> @quakeNames       = {"Quake Medallion"};
const array<string> @torchNames       = {"Torch"};
const array<string> @hammerNames      = {"Hammer"};
const array<string> @fluteNames       = {"Shovel", "Flute", "Flute (activated)"};
const array<string> @bugnetNames      = {"Bug Catching Net"};
const array<string> @bookNames        = {"Book of Mudora"};
const array<string> @canesomariaNames = {"Cane of Somaria"};
const array<string> @canebyrnaNames   = {"Cane of Byrna"};
const array<string> @magiccapeNames   = {"Magic Cape"};
const array<string> @magicmirrorNames = {"Magic Scroll", "Magic Mirror"};
const array<string> @glovesNames      = {"Power Gloves", "Titan's Mitts"};
const array<string> @bootsNames       = {"Pegasus Boots"};
const array<string> @flippersNames    = {"Flippers"};
const array<string> @moonpearlNames   = {"Moon Pearl"};
const array<string> @swordNames       = {"Fighter Sword", "Master Sword", "Tempered Sword", "Golden Sword"};
const array<string> @shieldNames      = {"Blue Shield", "Red Shield", "Mirror Shield"};
const array<string> @armorNames       = {"Blue Mail", "Red Mail"};
const array<string> @bottleNames      = {"", "Empty Bottle", "Red Potion", "Green Potion", "Blue Potion", "Fairy", "Bee", "Good Bee"};
const array<string> @magicNames       = {"1/2 Magic", "1/4 Magic"};
const array<string> @worldStateNames  = {"Q#Hyrule Castle Dungeon started", "Q#Hyrule Castle Dungeon completed", "Q#Search for Crystals started"};

void nameForBow        (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bowNames, notify, new); }
void nameForBoomerang  (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(boomerangNames, notify, new); }
void nameForHookshot   (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(hookshotNames, notify, new); }
void nameForMushroom   (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(mushroomNames, notify, new); }
void nameForFirerod    (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(firerodNames, notify, new); }
void nameForIcerod     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(icerodNames, notify, new); }
void nameForBombos     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bombosNames, notify, new); }
void nameForEther      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(etherNames, notify, new); }
void nameForQuake      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(quakeNames, notify, new); }
void nameForTorch      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(torchNames, notify, new); }
void nameForHammer     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(hammerNames, notify, new); }
void nameForFlute      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(fluteNames, notify, new); }
void nameForBugnet     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bugnetNames, notify, new); }
void nameForBook       (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bookNames, notify, new); }
void nameForCanesomaria(uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(canesomariaNames, notify, new); }
void nameForCanebyrna  (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(canebyrnaNames, notify, new); }
void nameForMagiccape  (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(magiccapeNames, notify, new); }
void nameForMagicmirror(uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(magicmirrorNames, notify, new); }
void nameForGloves     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(glovesNames, notify, new); }
void nameForBoots      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bootsNames, notify, new); }
void nameForFlippers   (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(flippersNames, notify, new); }
void nameForMoonpearl  (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(moonpearlNames, notify, new); }
void nameForSword      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(swordNames, notify, new); }
void nameForShield     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(shieldNames, notify, new); }
void nameForArmor      (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(armorNames, notify, new); }
void nameForBottle     (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(bottleNames, notify, new); }

void nameForMagic         (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(magicNames, notify, new); }
void nameForWorldState    (uint16 _, uint16 new, NotifyItemReceived @notify) { notifySingleItem(worldStateNames, notify, new); }
void nameForTriforcePieces(uint16 old, uint16 new, NotifyItemReceived @notify) {
  auto diff = new - old;
  if (diff == 1) {
    notify("1 new triforce piece");
  } else {
    notify(fmtInt(diff) + " new triforce pieces");
  }
}

void notifyBitfieldItem(const array<string> @names, NotifyItemReceived @notify, uint16 old, uint16 new) {
  if (new == 0) return;

  for (uint i = 0, k = 1; i < 8; i++, k <<= 1) {
    if ((old & k) == 0 && (new & k) == k) {
      notify(names[i]);
    }
  }
}

const array<string> @compass1Names = { "",
                                       "",
                                       "Ganon's Tower Compass",
                                       "Turtle Rock Compass",
                                       "Thieves Town Compass",
                                       "Tower of Hera Compass",
                                       "Ice Palace Compass",
                                       "Skull Woods Compass" };

const array<string> @compass2Names = { "Misery Mire Compass",
                                       "Dark Palace Compass",
                                       "Swamp Palace Compass",
                                       "Hyrule Castle 2 Compass",
                                       "Desert Palace Compass",
                                       "Eastern Palace Compass",
                                       "Hyrule Castle Compass",
                                       "Sewer Passage Compass" };

const array<string> @bigkey1Names  = { "",
                                       "",
                                       "Ganon's Tower Big Key",
                                       "Turtle Rock Big Key",
                                       "Thieves Town Big Key",
                                       "Tower of Hera Big Key",
                                       "Ice Palace Big Key",
                                       "Skull Woods Big Key" };

const array<string> @bigkey2Names  = { "Misery Mire Big Key",
                                       "Dark Palace Big Key",
                                       "Swamp Palace Big Key",
                                       "Hyrule Castle 2 Big Key",
                                       "Desert Palace Big Key",
                                       "Eastern Palace Big Key",
                                       "Hyrule Castle Big Key",
                                       "Sewer Passage Big Key" };

const array<string> @map1Names     = { "",
                                       "",
                                       "Ganon's Tower Map",
                                       "Turtle Rock Map",
                                       "Thieves Town Map",
                                       "Tower of Hera Map",
                                       "Ice Palace Map",
                                       "Skull Woods Map" };

const array<string> @map2Names     = { "Misery Mire Map",
                                       "Dark Palace Map",
                                       "Swamp Palace Map",
                                       "Hyrule Castle 2 Map",
                                       "Desert Palace Map",
                                       "Eastern Palace Map",
                                       "Hyrule Castle Map",
                                       "Sewer Passage Map" };

const array<string> @pendantsNames  = { "Pendant of Courage",
                                        "Pendant of Wisdom",
                                        "Pendant of Power",
                                        "",
                                        "",
                                        "",
                                        "",
                                        "" };

const array<string> @crystalsNames  = { "Misery Mire Crystal",
                                        "Dark Palace Crystal",
                                        "Ice Palace Crystal",
                                        "Turtle Rock Crystal",
                                        "Swamp Palace Crystal",
                                        "Thieves Town Crystal",
                                        "Skull Woods Crystal",
                                        "" };

const array<string> @progress1Names = { "Q#Uncle check completed",
                                        "Q#Priest's Wishes started",
                                        "Q#Zelda Rescue completed",
                                        "",
                                        "",
                                        "",
                                        "",
                                        "" };

const array<string> @progress2Names = { "Q#Hobo check completed",
                                        "Q#Bottle Salesman check completed",
                                        "",
                                        "Q#Flute Boy completed",
                                        "Q#Purple Chest completed",
                                        "Q#Smithy Rescue completed",
                                        "",
                                        "Q#Sword Tempering started" };

void nameForCompass1 (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(compass1Names, notify, old, new); }
void nameForCompass2 (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(compass2Names, notify, old, new); }
void nameForBigkey1  (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(bigkey1Names, notify, old, new); }
void nameForBigkey2  (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(bigkey2Names, notify, old, new); }
void nameForMap1     (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(map1Names, notify, old, new); }
void nameForMap2     (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(map2Names, notify, old, new); }
void nameForPendants (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(pendantsNames, notify, old, new); }
void nameForCrystals (uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(crystalsNames, notify, old, new); }
void nameForProgress1(uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(progress1Names, notify, old, new); }
void nameForProgress2(uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(progress2Names, notify, old, new); }

const array<string> @randomizerItems1Names = { "Flute (activated)",
                                               "Flute",
                                               "Shovel",
                                               "Q#Mushroom complete",
                                               "Magic Powder",
                                               "Mushroom",
                                               "Red Boomerang",
                                               "Blue Boomerang" };

const array<string> @randomizerItems2Names = { "",
                                               "",
                                               "",
                                               "",
                                               "",
                                               "",  // Progressive Bow
                                               "Bow w/ Silver Arrows",
                                               "Bow" };

void nameForRandomizerItems1(uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(randomizerItems1Names, notify, old, new); }
void nameForRandomizerItems2(uint16 old, uint16 new, NotifyItemReceived @notify) { notifyBitfieldItem(randomizerItems2Names, notify, old, new); }
