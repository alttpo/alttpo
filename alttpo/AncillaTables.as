
// 17 tables of 10 bytes each
const uint ancilla_facts = 17;
const uint ancilla_count = 10;
const uint ancilla_table_size = ancilla_facts * ancilla_count;
const uint32 ancilla_table1_addr = 0x7E0BF0;

class AncillaTables {
  array<uint8> data(ancilla_table_size);

  void read_ram() {
    bus::read_block_u8(ancilla_table1_addr, 0, ancilla_table_size, data);
  }

  uint8 get_misc(int n)         const property { return      data[ 0*10 + n]; }   // 0x7E0BF0
  uint8 get_y_posl(int n)       const property { return      data[ 1*10 + n]; }   // 0x7E0BFA
  uint8 get_x_posl(int n)       const property { return      data[ 2*10 + n]; }   // 0x7E0C04
  uint8 get_y_posh(int n)       const property { return      data[ 3*10 + n]; }   // 0x7E0C0E
  uint8 get_x_posh(int n)       const property { return      data[ 4*10 + n]; }   // 0x7E0C18
   int8 get_y_velocity(int n)   const property { return int8(data[ 5*10 + n]); }  // 0x7E0C22
   int8 get_x_velocity(int n)   const property { return int8(data[ 6*10 + n]); }  // 0x7E0C2C
  uint8 get_y_subpixel(int n)   const property { return      data[ 7*10 + n]; }   // 0x7E0C36
  uint8 get_x_subpixel(int n)   const property { return      data[ 8*10 + n]; }   // 0x7E0C40
  uint8 get_mode(int n)         const property { return      data[ 9*10 + n]; }   // 0x7E0C4A
  uint8 get_effects(int n)      const property { return      data[10*10 + n]; }   // 0x7E0C54
  uint8 get_item(int n)         const property { return      data[11*10 + n]; }   // 0x7E0C5E
  uint8 get_timer(int n)        const property { return      data[12*10 + n]; }   // 0x7E0C68
  uint8 get_hitbox_index(int n) const property { return      data[13*10 + n]; }   // 0x7E0C72
  uint8 get_room_level(int n)   const property { return      data[14*10 + n]; }   // 0x7E0C7C
  uint8 get_oam_index(int n)    const property { return      data[15*10 + n]; }   // 0x7E0C86
  uint8 get_oam_count(int n)    const property { return      data[16*10 + n]; }   // 0x7E0C90

  uint8 get_timer1(int n)       const property { return bus::read_u8(0x7E03B1 + n); } // 0x7E03B1

  void set_misc(int n, uint8 value)         property { data[ 0*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  0*10 + n, uint8(value)); }   // 0x7E0BF0
  void set_y_posl(int n, uint8 value)       property { data[ 1*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  1*10 + n, uint8(value)); }   // 0x7E0BFA
  void set_x_posl(int n, uint8 value)       property { data[ 2*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  2*10 + n, uint8(value)); }   // 0x7E0C04
  void set_y_posh(int n, uint8 value)       property { data[ 3*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  3*10 + n, uint8(value)); }   // 0x7E0C0E
  void set_x_posh(int n, uint8 value)       property { data[ 4*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  4*10 + n, uint8(value)); }   // 0x7E0C18
  void set_y_velocity(int n, int8 value)    property { data[ 5*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  5*10 + n, uint8(value)); }   // 0x7E0C22
  void set_x_velocity(int n, int8 value)    property { data[ 6*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  6*10 + n, uint8(value)); }   // 0x7E0C2C
  void set_y_subpixel(int n, uint8 value)   property { data[ 7*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  7*10 + n, uint8(value)); }   // 0x7E0C36
  void set_x_subpixel(int n, uint8 value)   property { data[ 8*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  8*10 + n, uint8(value)); }   // 0x7E0C40
  void set_mode(int n, uint8 value)         property { data[ 9*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr +  9*10 + n, uint8(value)); }   // 0x7E0C4A
  void set_effects(int n, uint8 value)      property { data[10*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 10*10 + n, uint8(value)); }   // 0x7E0C54
  void set_item(int n, uint8 value)         property { data[11*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 11*10 + n, uint8(value)); }   // 0x7E0C5E
  void set_timer(int n, uint8 value)        property { data[12*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 12*10 + n, uint8(value)); }   // 0x7E0C68
  void set_hitbox_index(int n, uint8 value) property { data[13*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 13*10 + n, uint8(value)); }   // 0x7E0C72
  void set_room_level(int n, uint8 value)   property { data[14*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 14*10 + n, uint8(value)); }   // 0x7E0C7C
  void set_oam_index(int n, uint8 value)    property { data[15*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 15*10 + n, uint8(value)); }   // 0x7E0C86
  void set_oam_count(int n, uint8 value)    property { data[16*10 + n] = uint8(value); bus::write_u8(ancilla_table1_addr + 16*10 + n, uint8(value)); }   // 0x7E0C90

  void set_timer1(int n, uint8 value)       property { bus::write_u8(0x7E03B1 + n, value); } // 0x7E03B1

  // typed access:
  uint16 get_y(int n) const property { return uint16(y_posl[n]) | (uint16(y_posh[n]) << 8); }
  uint16 get_x(int n) const property { return uint16(x_posl[n]) | (uint16(x_posh[n]) << 8); }

  bool is_projectile(int n) const {
    auto t = mode[n];

    // 0x00 - Nothing, and actually an indicator that no ancilla is currently active in this slot.
    if (t == 0x00) return false;

    // 0x01 - Somarian Blast; Results from splitting a Somarian Block
    if (t == 0x01) return true;
    // 0x02 - Fire Rod Shot
    if (t == 0x02) return true;
    // 0x03 - Unused; Instantiating one of these creates an object that does nothing.
    // 0x04 - Beam Hit; Master sword beam or Somarian Blast dispersing after hitting something
    if (t == 0x04) return true;
    // 0x05 - Boomerang
    // 0x06 - Wall Hit; Spark-like effect that occurs when you hit a wall with a boomerang or hookshot
    // 0x07 - Bomb; Normal bombs laid by the player
    // 0x08 - Door Debris; Rock fall effect from bombing a cracked cave or dungeon wall
    // 0x09 - Arrow; Fired from the player's bow
    if (t == 0x09) return true;
    // 0x0A - Halted Arrow; Player's arrow that is stuck in something (wall or sprite)
    // 0x0B - Ice Rod Shot
    if (t == 0x0B) return true;
    // 0x0C - Sword Beam
    if (t == 0x0C) return true;
    // 0x0D - Sword Full Charge Spark; The sparkle that briefly appears at the tip of the player's sword when their spin attack fully charges up.
    // 0x0E - Unused; Duplicate of the Blast Wall
    // 0x0F - Unused; Duplicate of the Blast Wall

    // 0x10 - Unused; Duplicate of the Blast Wall
    // 0x11 - Ice Shot Spread; Ice shot dispersing after hitting something.
    // 0x12 - Unused; Duplicate of the Blast Wall
    // 0x13 - Ice Shot Sparkle; The only actually visible parts of the ice shot.
    // 0x14 - Unused; Don't use as it will crash the game.
    // 0x15 - Jump Splash; Splash from the player jumping into or out of deep water
    // 0x16 - The Hammer's Stars / Stars from hitting hard ground with the shovel
    // 0x17 - Dirt from digging a hole with the shovel
    // TODO: maybe?
    // 0x18 - The Ether Effect
    // TODO: maybe?
    // 0x19 - The Bombos Effect
    // TODO: maybe?
    // 0x1A - Precursor to torch flame / Magic powder
    // 0x1B - Sparks from tapping a wall with your sword
    // 0x1C - The Quake Effect
    // TODO: maybe?
    // 0x1D - Jarring effect from hitting a wall while dashing
    // 0x1E - Pegasus boots dust flying
    // 0x1F - Hookshot
    if (t == 0x1F) return true;

    // 0x20 - Link's Bed Spread
    // 0x21 - Link's Zzzz's from sleeping
    // 0x22 - Received Item Sprite
    // 0x23 - Bunny / Cape transformation poof
    // 0x24 - Gravestone sprite when in motion
    // 0x25 -
    // 0x26 - Sparkles when swinging lvl 2 or higher sword
    // 0x27 - the bird (when called by flute)
    // 0x28 - item sprite that you throw into magic faerie ponds.
    // 0x29 - Pendants and crystals
    // 0x2A - Start of spin attack sparkle
    // 0x2B - During Spin attack sparkles
    // 0x2C - Cane of Somaria blocks
    // TODO: maybe?
    // 0x2D -
    // 0x2E - ????
    // 0x2F - Torch's flame

    // 0x30 - Initial spark for the Cane of Byrna activating
    // 0x31 - Cane of Byrna spinning sparkle
    if (t == 0x31) return true;
    // 0x32 - Flame blob, possibly from wall explosion
    // 0x33 - Series of explosions from blowing up a wall (after pulling a switch)
    // 0x34 - Burning effect used to open up the entrance to skull woods.
    // 0x35 - Master Sword ceremony.... not sure if it's the whole thing or a part of it
    // 0x36 - Flute that pops out of the ground in the haunted grove.
    // 0x37 - Appears to trigger the weathervane explosion.
    // 0x38 - Appears to give Link the bird enabled flute.
    // 0x39 - Cane of Somaria blast which creates platforms (sprite 0xED)
    // 0x3A - super bomb explosion (also does things normal bombs can)
    // 0x3B - Unused hit effect. Looks similar to Somaria block being nulled out.
    // 0x3C - Sparkles from holding the sword out charging for a spin attack.
    // 0x3D - splash effect when things fall into the water
    // 0x3E - 3D crystal effect (or transition into 3D crystal?)
    // 0x3F - Disintegrating bush poof (due to magic powder)
    // 0x40 - Dwarf transformation cloud
    // 0x41 - Water splash in the waterfall of wishing entrance (and swamp palace)
    // 0x42 - Rupees that you throw in to the Pond of Wishing
    // 0x43 - Ganon's Tower seal being broken. (not opened up though!)

    return false;
  }
};
