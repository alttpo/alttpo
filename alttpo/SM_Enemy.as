
const uint sm_enemy_bank = 0x7E0F78;
const uint sm_enemy_count = 0x7E0E4E;
const uint sm_enemy_kills = 0x7E0E50;
const uint sm_enemy_active_distance = 30000;

class SM_Enemy {

  uint8 enemy_index;
  bool is_new;
  
  uint8 host_index;
  bool is_active;
  
  uint16 pointer;
  array<uint16> enemy_data(0x20);
  uint16 health;
  uint16 Xpos;
  uint16 Ypos;
  
  SM_Enemy(){
    enemy_index = 33;
  }
  
  SM_Enemy(uint8 temp_index){
    enemy_index = temp_index;
  }
  
  SM_Enemy(uint8 temp_index, bool active_host){
    enemy_index = temp_index;
    is_active = active_host;
    read();
    is_new = true;
  }
  
  SM_Enemy(uint8 temp_index, array<uint16> temp_data, uint8 temp_host_index, bool active_host, bool temp_is_new){
    enemy_index = temp_index;
    enemy_data = temp_data;
    host_index = temp_host_index;
    is_active = active_host;
    
    read(false);
    is_new = temp_is_new;
  }
  
  void compare_to_remote(SM_Enemy remote){
    
    if (remote.pointer == 0 && !remote.is_new){
      pointer = 0;
      enemy_data[0] = 0;
      return;
    }
    
    // min health between two players
    enemy_data[10] = min(health, remote.health);
    health = enemy_data[10];
    
    if (enemy_data[19] == 0){
      uint16 temp = 0;
      if (remote.enemy_data[19] > 0){temp = remote.enemy_data[19];}
      enemy_data[19] = max(enemy_data[19], temp);
    }
  }
  
  
  void read(bool local = true){
    if (local) bus::read_block_u16(sm_enemy_bank + 0x40*enemy_index, 0, 0x20, enemy_data);
  
    pointer = enemy_data[0];
    Xpos = enemy_data[1];
    Ypos = enemy_data[3];
    health = enemy_data[10];
    is_new = false;
  }
  
  void write(){
    uint bound; //determines how much memory to copy into enemy slot
    
    switch(pointer){
      
      case 0x0000: {
        //Enemy is dead from remote, so delete the enemy here
        //update the count for number of enemies in the room
        for(uint i = 0; i < 0x20; i++){
          bus::write_u16(sm_enemy_bank + enemy_index*0x40 + i*2, 0);
        }
      
        bus::write_u16(0x7E0E4E, bus::read_u16(0x7E0E4E) - 1);
        bus::write_u16(0x7E0E50, bus::read_u16(0x7E0E50) + 1);
        return;
      }
      case 0xD73F: return; // skip elevators
      case 0xD0BF: return; // skip ship
      case 0xD07F: return; // skip ship part 2
      case 0xE87F: bound = 24; break;
      case 0xEaFF: bound = 24; break;
      default: bound = 32;
    }
  
    
    // if the "respawn when killed" flag is set, skip syncing this enemy
    if(enemy_data[15] & 0b01000000 == 0b01000000){
      return;
    }
    
    for(uint i = 0; i < bound; i++){
          bus::write_u16(sm_enemy_bank + enemy_index*0x40 + i*2, enemy_data[i]);
    }
    
  }
}