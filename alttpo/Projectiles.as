
// 17 tables of 10 bytes each
uint projectile_facts = 17;
uint projectile_count = 10;
uint projectile_table_size = projectile_facts * projectile_count;

class Projectiles {
  array<uint8> data(projectile_table_size);

  void read_ram() {
    bus::read_block_u8(0x7E0BF0, 0, projectile_table_size, data);
  }

  uint8 get_misc(int n) property       { return      data[n * 10 +  0]; }   // 0x7E0BF0
  uint8 get_y_posl(int n) property     { return      data[n * 10 +  1]; }   // 0x7E0BFA
  uint8 get_x_posl(int n) property     { return      data[n * 10 +  2]; }   // 0x7E0C04
  uint8 get_y_posh(int n) property     { return      data[n * 10 +  3]; }   // 0x7E0C0E
  uint8 get_x_posh(int n) property     { return      data[n * 10 +  4]; }   // 0x7E0C18
   int8 get_y_velocity(int n) property { return int8(data[n * 10 +  5]); }  // 0x7E0C22
   int8 get_x_velocity(int n) property { return int8(data[n * 10 +  6]); }  // 0x7E0C2C
  uint8 get_y_subpixel(int n) property { return      data[n * 10 +  7]; }   // 0x7E0C36
  uint8 get_x_subpixel(int n) property { return      data[n * 10 +  8]; }   // 0x7E0C40
  uint8 get_mode(int n) property       { return      data[n * 10 +  9]; }   // 0x7E0C4A
  uint8 get_effects(int n) property    { return      data[n * 10 + 10]; }   // 0x7E0C54
  uint8 get_item(int n) property       { return      data[n * 10 + 11]; }   // 0x7E0C5E
  uint8 get_timer(int n) property      { return      data[n * 10 + 12]; }   // 0x7E0C68
  uint8 get_direction(int n) property  { return      data[n * 10 + 13]; }   // 0x7E0C72
  uint8 get_room_level(int n) property { return      data[n * 10 + 14]; }   // 0x7E0C7C
  uint8 get_oam_index(int n) property  { return      data[n * 10 + 15]; }   // 0x7E0C86
  uint8 get_oam_count(int n) property  { return      data[n * 10 + 16]; }   // 0x7E0C90

  // TODO: 0x7E03B1

  // typed access:
  uint16 get_y(int n) property { return uint16(y_posl[n]) | (uint16(y_posh[n]) << 16); }
  uint16 get_x(int n) property { return uint16(x_posl[n]) | (uint16(x_posh[n]) << 16); }
};
