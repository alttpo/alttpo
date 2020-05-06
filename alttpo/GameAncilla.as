
// Represents an ALTTP ancilla object with fields scattered about WRAWM:
const int ancillaeFactsCount1 = 0x20;
const int ancillaeFactsCount2 = 0x16;
class GameAncilla {
  // for all 10 ancillae:
  // $0BF0 = 0x00..0x10
  // $0280 = 0x11..0x15

  // for lowest 5 ancillae indexes only:
  // $0380 = 0x16
  // $0385 = 0x17
  // $038A = 0x18
  // $038F = 0x19
  // $0394 = 0x1A
  // skip $0399 which is special for boomearngs
  // $039F = 0x1B
  // skip $03A4 which is for receiving items
  // $03A9 = 0x1C
  // $03B1 = 0x1D   // lifting state?
  // -- $03C4 special for rock debris, maybe bombs
  // $03C5 = 0x1E
  // $03CA = 0x1F

  array<uint8> facts;
  uint8 index;
  bool requestOwnership = false;

  int deserialize(const array<uint8> &in r, int c) {
    uint8 value = r[c++];
    if ((value & 0x80) == 0x80) {
      this.requestOwnership = true;
      this.index = value & 0x7F;
    } else {
      this.requestOwnership = false;
      this.index = value;
    }

    // copy ancilla facts from:
    if (index < 5) {
      facts.resize(ancillaeFactsCount1);
    } else {
      facts.resize(ancillaeFactsCount2);
    }
    for (uint i = 0; i < facts.length(); i++) {
      facts[i] = r[c++];
    }

    return c;
  }

  void serialize(array<uint8> &r) {
    uint8 value = this.index;
    if (requestOwnership) {
      value |= 0x80;
    }

    r.insertLast(value);
    r.insertLast(facts);
  }

  void readRAM(uint8 index) {
    this.index = index;

    if (index < 5) {
      facts.resize(ancillaeFactsCount1);
    } else {
      facts.resize(ancillaeFactsCount2);
    }

    for (uint i = 0, j = index; i < 0x11; i++, j += 0x0A) {
      facts[0x00+i] = bus::read_u8(0x7E0BF0 + j);
    }
    for (uint i = 0, j = index; i < 0x05; i++, j += 0x0A) {
      facts[0x11+i] = bus::read_u8(0x7E0280 + j);
    }

    // first 5 ancillae are special and have more supporting data:
    if (index < 5) {
      facts[0x16] = bus::read_u8(0x7E0380 + index);
      facts[0x17] = bus::read_u8(0x7E0385 + index);
      facts[0x18] = bus::read_u8(0x7E038A + index);
      facts[0x19] = bus::read_u8(0x7E038F + index);
      facts[0x1A] = bus::read_u8(0x7E0394 + index);
      facts[0x1B] = bus::read_u8(0x7E039F + index);
      facts[0x1C] = bus::read_u8(0x7E03A9 + index);
      facts[0x1D] = bus::read_u8(0x7E03B1 + index);
      facts[0x1E] = bus::read_u8(0x7E03C5 + index);
      facts[0x1F] = bus::read_u8(0x7E03CA + index);
    }
  }

  void writeRAM() {
    for (uint i = 0, j = index; i < 0x11; i++, j += 0x0A) {
      bus::write_u8(0x7E0BF0 + j, facts[0x00+i]);
    }
    for (uint i = 0, j = index; i < 0x05; i++, j += 0x0A) {
      bus::write_u8(0x7E0280 + j, facts[0x11+i]);
    }
    if (index < 5) {
      bus::write_u8(0x7E0380 + index, facts[0x16]);
      bus::write_u8(0x7E0385 + index, facts[0x17]);
      bus::write_u8(0x7E038A + index, facts[0x18]);
      bus::write_u8(0x7E038F + index, facts[0x19]);
      bus::write_u8(0x7E0394 + index, facts[0x1A]);
      bus::write_u8(0x7E039F + index, facts[0x1B]);
      bus::write_u8(0x7E03A9 + index, facts[0x1C]);
      bus::write_u8(0x7E03B1 + index, facts[0x1D]);
      bus::write_u8(0x7E03C5 + index, facts[0x1E]);
      bus::write_u8(0x7E03CA + index, facts[0x1F]);
    }
  }

  //uint16 y         { get { return uint16(facts[0x01]) | uint16(facts[0x03] << 8); } };
  //uint16 x         { get { return uint16(facts[0x02]) | uint16(facts[0x04] << 8); } };
  uint8  type      { get { return facts[0x09]; } };
  //uint8  oam_index { get { return facts[0x0F]; } };
  //uint8  oam_count { get { return facts[0x10]; } };
  uint8  held      { get { return facts[0x16]; } };

  bool is_enabled  { get { return type != 0; } };

  // Determine if this ancilla should be synced based on its type:
  bool is_syncable() {
    uint8 t = type;

    // 0x00 - Nothing - means slot is unused
    if (t == 0x00) return true;

    // 0x01 - Somarian Blast; Results from splitting a Somarian Block
    if (t == 0x01) return true;
    // 0x02 - Fire Rod Shot
    if (t == 0x02) return true;
    // 0x03 - Unused; Instantiating one of these creates an object that does nothing.
    // 0x04 - Beam Hit; Master sword beam or Somarian Blast dispersing after hitting something
    // 0x05 - Boomerang
    if (t == 0x05) return true;
    // 0x06 - Wall Hit; Spark-like effect that occurs when you hit a wall with a boomerang or hookshot
    if (t == 0x06) return true;
    // 0x07 - Bomb; Normal bombs laid by the player
    if (t == 0x07) return true;
    // 0x08 - Door Debris; Rock fall effect from bombing a cracked cave or dungeon wall
    if (t == 0x08) return true;
    // 0x09 - Arrow; Fired from the player's bow
    if (t == 0x09) return true;
    // 0x0A - Halted Arrow; Player's arrow that is stuck in something (wall or sprite)
    if (t == 0x0A) return true;
    // 0x0B - Ice Rod Shot
    if (t == 0x0B) return true;
    // 0x0C - Sword Beam
    //if (t == 0x0C) return true;
    // 0x0D - Sword Full Charge Spark; The sparkle that briefly appears at the tip of the player's sword when their spin attack fully charges up.
    //if (t == 0x0D) return true;
    // 0x0E - Unused; Duplicate of the Blast Wall
    // 0x0F - Unused; Duplicate of the Blast Wall

    // 0x10 - Unused; Duplicate of the Blast Wall
    // 0x11 - Ice Shot Spread; Ice shot dispersing after hitting something.
    if (t == 0x11) return true;
    // 0x12 - Unused; Duplicate of the Blast Wall
    // 0x13 - Ice Shot Sparkle; The only actually visible parts of the ice shot.
    if (t == 0x13) return true;
    // 0x14 - Unused; Don't use as it will crash the game.
    // 0x15 - Jump Splash; Splash from the player jumping into or out of deep water
    if (t == 0x15) return true;
    // 0x16 - The Hammer's Stars / Stars from hitting hard ground with the shovel
    if (t == 0x16) return true;
    // 0x17 - Dirt from digging a hole with the shovel
    if (t == 0x17) return true;
    // 0x18 - The Ether Effect
    //if (t == 0x18) return true;
    // 0x19 - The Bombos Effect
    //if (t == 0x19) return true;
    // 0x1A - Precursor to torch flame / Magic powder
    if (t == 0x1A) return true;
    // 0x1B - Sparks from tapping a wall with your sword
    if (t == 0x1B) return true;
    // 0x1C - The Quake Effect
    // BREAKS TILEMAP AND VRAM!!!
    //if (t == 0x1C) return true;
    // 0x1D - Jarring effect from hitting a wall while dashing
    // 0x1E - Pegasus boots dust flying
    if (t == 0x1E) return true;
    // 0x1F - Hookshot
    // Messed up graphics
    //if (t == 0x1F) return true;

    // 0x20 - Link's Bed Spread
    // 0x21 - Link's Zzzz's from sleeping
    // 0x22 - Received Item Sprite
    if (t == 0x22) return true;
    // 0x23 - Bunny / Cape transformation poof
    if (t == 0x23) return true;
    // 0x24 - Gravestone sprite when in motion
    if (t == 0x24) return true;
    // 0x25 -
    // 0x26 - Sparkles when swinging lvl 2 or higher sword
    //if (t == 0x26) return true;
    // 0x27 - the bird (when called by flute)
    // This softlocks a player caught up by another player's bird
    //if (t == 0x27) return true;
    // 0x28 - item sprite that you throw into magic faerie ponds.
    if (t == 0x28) return true;
    // 0x29 - Pendants and crystals
    if (t == 0x29) return true;
    // 0x2A - Start of spin attack sparkle
    // 0x2B - During Spin attack sparkles
    // 0x2C - Cane of Somaria blocks
    if (t == 0x2C) return true;
    // 0x2D -
    // 0x2E - ????
    // 0x2F - Torch's flame
    if (t == 0x2F) return true;

    // 0x30 - Initial spark for the Cane of Byrna activating
    // 0x31 - Cane of Byrna spinning sparkle
    // 0x32 - Flame blob, possibly from wall explosion
    if (t == 0x32) return true;
    // 0x33 - Series of explosions from blowing up a wall (after pulling a switch)
    if (t == 0x33) return true;
    // 0x34 - Burning effect used to open up the entrance to skull woods.
    // 0x35 - Master Sword ceremony.... not sure if it's the whole thing or a part of it
    // 0x36 - Flute that pops out of the ground in the haunted grove.
    if (t == 0x36) return true;
    // 0x37 - Appears to trigger the weathervane explosion.
    // 0x38 - Appears to give Link the bird enabled flute.
    // 0x39 - Cane of Somaria blast which creates platforms (sprite 0xED)
    if (t == 0x39) return true;
    // 0x3A - super bomb explosion (also does things normal bombs can)
    if (t == 0x3A) return true;
    // 0x3B - Unused hit effect. Looks similar to Somaria block being nulled out.
    // 0x3C - Sparkles from holding the sword out charging for a spin attack.
    // 0x3D - splash effect when things fall into the water
    if (t == 0x3D) return true;
    // 0x3E - 3D crystal effect (or transition into 3D crystal?)
    // 0x3F - Disintegrating bush poof (due to magic powder)
    if (t == 0x3F) return true;

    // 0x40 - Dwarf transformation cloud
    if (t == 0x40) return true;
    // 0x41 - Water splash in the waterfall of wishing entrance (and swamp palace)
    if (t == 0x41) return true;
    // 0x42 - Rupees that you throw in to the Pond of Wishing
    if (t == 0x42) return true;
    // 0x43 - Ganon's Tower seal being broken. (not opened up though!)

    return false;
  }
};
