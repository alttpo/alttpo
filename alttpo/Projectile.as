
class Projectile {
  // serialized fields:
  uint8 mode;         // $0C4A
  uint16 x;           // $0BFA:$0C0E (lo:hi)
  uint16 y;           // $0C04:$0C18 (lo:hi)
  uint8 hitbox_index; // $0C72
  uint8 room_level;   // $0C7C
  // end serialized fields

  Hitbox hitbox;

  void calc_hitbox() {
    if (mode == 0) {
      dbgData("projectile mode = 0");
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
      dbgData("bad hitbox index {0}".format({hitbox_index}));
      return;
    }

    // look up hitbox x,y,w,h from ROM tables:
    hitbox.setBox(
      x + rom.hitbox_ancilla_x[hitbox_index],
      y + rom.hitbox_ancilla_y[hitbox_index],
      rom.hitbox_ancilla_w[hitbox_index],
      rom.hitbox_ancilla_h[hitbox_index]
    );
  }

  // calc_damage results:
  uint8 damage;
  int8 recoil_dx;
  int8 recoil_dy;
  // end calc_damage results

  bool calc_damage(LocalGameState@ local, GameState@ remote) {
    // reset results:
    damage = 0;
    recoil_dx = 0;
    recoil_dy = 0;

    if (!hitbox.active) {
      return false;
    }

    bool intersects = hitbox.intersects(local.hitbox);
    dbgData("pr ({0},{1},{2},{3}) vs pl ({4},{5},{6},{7}) = {8}".format({
      fmtHex(hitbox.x,4),
      fmtHex(hitbox.y,4),
      fmtHex(hitbox.w,2),
      fmtHex(hitbox.h,2),
      fmtHex(local.hitbox.x,4),
      fmtHex(local.hitbox.y,4),
      fmtHex(local.hitbox.w,2),
      fmtHex(local.hitbox.h,2),
      fmtBool(intersects)
    }));
    if (!intersects) {
      return false;
    }

    // determine our armor strength as a bit shift right amount to reduce damage by:
    int armor_shr = local.sram[0x35B];  // 0 = green, 1 = blue, 2 = red

    // determine damage amount:
    switch (mode) {
      case 0x09:  // arrow or silver arrow
        // sram[0x340] = arrow type
        if (remote.sram[0x340] >= 0x03) {
          // silver arrow:
          damage = 20*8;
        } else {
          // regular arrow:
          damage = 2*8;
        }

        damage >>= armor_shr;
        break;

      case 0x01:  // somaria blast
      case 0x0B:  // ice rod
      case 0x02:  // fire rod
        damage = 4 * 8;
        break;

      case 0x1F:  // hookshot
      case 0x31:  // Cane of Byrna sparkle
        damage = 2 * 8;
        break;
    }

    // determine recoil vector from this projectile:
    float dx = local.x - (hitbox.x + (hitbox.w * 0.5f));
    float dy = local.y - (hitbox.y + (hitbox.h * 0.5f));
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
