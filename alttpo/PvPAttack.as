
class PvPAttack {
  uint16 player_index;  // which player is being damaged

  uint8 sword_time;     // $3C value
  uint8 melee_item;     // which melee item caused the damage (0 = sword, 1 = bugnet?, 2 = hammer)
  uint8 ancilla_mode;   // which ancilla mode/type caused the damage (0 for melee item)

  uint8 damage;         // how much damage (8 damage = 1 whole heart)

  int8 recoil_dx;       // how much to stagger the player in X direction
  int8 recoil_dy;       // how much to stagger the player in Y direction
  int8 recoil_dz;       // how much to stagger the player in Z direction
};
