
class Projectile {
  AncillaTables@ ancillaTables;
  uint8 index;        // ancilla index

  uint8 mode;         // $0C4A
  uint16 x;           // $0BFA:$0C0E (lo:hi)
  uint16 y;           // $0C04:$0C18 (lo:hi)
   int8 vx;           // $0C2C
   int8 vy;           // $0C22
  uint8 hitbox_index; // $0C72
  uint8 room_level;   // $0C7C

  Hitbox hitbox;

  Projectile() {}

  Projectile(AncillaTables@ ancillaTables, uint8 i) {
    @this.ancillaTables = @ancillaTables;
    this.index = i;

    this.mode = ancillaTables.mode[i];
    this.x = ancillaTables.x[i];
    this.y = ancillaTables.y[i];
    this.vx = ancillaTables.x_velocity[i];
    this.vy = ancillaTables.y_velocity[i];
    this.hitbox_index = ancillaTables.hitbox_index[i];
    this.room_level = ancillaTables.room_level[i];
    this.calc_hitbox();
  }

  void calc_hitbox() {
    if (mode == 0) {
      //dbgData("projectile mode = 0");
      hitbox.setActive(false);
      hitbox.setBox(0x8000, 0, 0, 0);
      return;
    }

    // set a default hitbox if we can't figure it out:
    hitbox.setActive(true);
    hitbox.setBox(x, y, 8, 8);
    if (rom is null) {
      return;
    }

    if (hitbox_index >= 12) {
      //dbgData("bad hitbox index {0}".format({hitbox_index}));
      return;
    }

    // special adjustment for sword beam:
    uint k = hitbox_index;
    if (mode == 0x0C) {
      k |= 0x08;
    }

    // look up hitbox x,y,w,h from ROM tables:
    hitbox.setBox(
      x + rom.hitbox_ancilla_x[k],
      y + rom.hitbox_ancilla_y[k],
      rom.hitbox_ancilla_w[k],
      rom.hitbox_ancilla_h[k]
    );
  }

  // calc_damage results:
  uint8 damage;
  int8 recoil_dx;
  int8 recoil_dy;
  // end calc_damage results

  bool calc_damage(GameState@ defendant, GameState@ attacker) {
    // reset results:
    damage = 0;
    recoil_dx = 0;
    recoil_dy = 0;

    if (!hitbox.active) {
      return false;
    }

    bool intersects = hitbox.intersects(defendant.hitbox);
    //dbgData("pr ({0},{1},{2},{3}) vs pl ({4},{5},{6},{7}) = {8}".format({
    //  fmtHex(hitbox.x,4),
    //  fmtHex(hitbox.y,4),
    //  fmtHex(hitbox.w,2),
    //  fmtHex(hitbox.h,2),
    //  fmtHex(defendant.hitbox.x,4),
    //  fmtHex(defendant.hitbox.y,4),
    //  fmtHex(defendant.hitbox.w,2),
    //  fmtHex(defendant.hitbox.h,2),
    //  fmtBool(intersects)
    //}));
    if (!intersects) {
      return false;
    }

    // determine our armor strength as a bit shift right amount to reduce damage by:
    int armor_shr = defendant.sram[0x35B];      // 0 = green, 1 = blue, 2 = red

    // take away the no-sword case to get a bit shift left amount:
    int sword = attacker.action_sword_type;   // 0 = none, 1 = fighter, 2 = master, 3 = tempered, 4 = gold
    int sword_shl = sword - 1;              //           0 = fighter, 1 = master, 2 = tempered, 3 = gold

    // default recoil direction for defendant player is the same direction the projectile is traveling in:
    float dx = float(vx);
    float dy = float(vy);

    // determine damage amount:
    switch (mode) {
      case 0x09:  // arrow or silver arrow
        // sram[0x340] = arrow type
        if (attacker.sram[0x340] >= 0x03) {
          // silver arrow:
          damage = 20*8;
        } else {
          // regular arrow:
          damage = 2*8;
        }

        damage >>= armor_shr;
        break;

      case 0x0C:  // sword beam
        damage = 8;
        if (sword > 0) {
          damage <<= sword_shl;
        }
        damage >>= armor_shr;
        break;

      case 0x01:  // somaria blast
      case 0x0B:  // ice rod
      case 0x02:  // fire rod
        damage = 4 * 8;
        break;

      case 0x1F:  // hookshot
        damage = 2 * 8;
        break;

      case 0x31:  // Cane of Byrna sparkle
        damage = 2 * 8;
        // set recoil direction away from attacker player:
        dx = float(x) - attacker.hitbox.mx;
        dy = float(y) - attacker.hitbox.my;
        break;
    }

    // determine recoil vector from this projectile where it was last frame:
    float mag = mathf::sqrt(dx * dx + dy * dy);
    if (mag == 0) {
      mag = 1.0f;
    }

    // scale recoil vector with damage amount:
    dx = dx * (16 + damage * 0.25f) / mag;
    dy = dy * (16 + damage * 0.25f) / mag;

    recoil_dx = int8(dx);
    recoil_dy = int8(dy);

    return true;
  }
};
