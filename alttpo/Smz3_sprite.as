

int draw_samuses(int x, int y, int ei, uint8 pose){
	//message("attempted to draw a samus");
	
	array<array<uint16>> sprs(32, array<uint16>(16)); // array of 32 different 8x8 sprite blocks
	array<uint16> palette(0x10); // palette array for loading the right colors
	int p = 0; // palette int, use is unknown
	int protocol = determine_protocol(pose); // decides which protocol is used for placing samus' blocks to build the sprite
	
	int offsx = offs_x(pose); // X offset to align sprite with actual location, differs by pose
	int offsy = offs_y(pose); // Y offset to align sprite with actual location, differs by pose 
	
	//initialize tile
	auto @tile = ppu::extra[ei++];
	tile.index = 0;
	tile.source = 5;
	tile.x = x + offsx;
    tile.y = y + offsy;
	tile.priority = -1;
	tile.hflip = false;
    tile.vflip = false;
    tile.width = 64;
    tile.height = 128;
	tile.pixels_clear();
	
	uint16 offsm = bus::read_u16(0x7e071f);
	uint8 bank = bus::read_u8(0x920000 + offsm + 2);
	uint16 address = bus::read_u16(0x920000 + offsm);

	//load data from vram into sprs
	for (int i = 0; i < sprs.length(); i++){
		//ppu::vram.read_block(0x6000 + 0x10 * i, 0, 16, sprs[i]);
		bus::read_block_u16(0x010000 * bank + address + 0x10 * i, 0, 16, sprs[i]);
	}
	//load (local) palette data from ram
	bus::read_block_u16(0x7eC180, 0, palette.length(), palette);
	
	//ppu::extra.color = ppu::rgb(31, 31, 31);
	//tile.fill(0, 0, 16, 16);
	
	//samus standing
	if (protocol == 0){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
	}
	//samus running
	else if (protocol == 1){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(32, 32, p, sprs[14], palette);
		tile.draw_sprite_4bpp(32, 24, p, sprs[29], palette);
		tile.draw_sprite_4bpp(32, 40, p, sprs[30], palette);
    }
	//samus crouching
	else if (protocol == 2){
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(16, 32, p, sprs[9], palette);
		tile.draw_sprite_4bpp(8, 32, p, sprs[24], palette);
	}
	//morph ball
	else if (protocol == 3){
		tile.draw_sprite_4bpp(0, 0, p, sprs[0], palette);
		tile.draw_sprite_4bpp(8, 0, p, sprs[1], palette);
		tile.draw_sprite_4bpp(16, 0, p, sprs[2], palette);
		tile.draw_sprite_4bpp(24, 0, p, sprs[3], palette);
		tile.draw_sprite_4bpp(0, 8, p, sprs[16], palette);
		tile.draw_sprite_4bpp(8, 8, p, sprs[17], palette);
		tile.draw_sprite_4bpp(16, 8, p, sprs[18], palette);
		tile.draw_sprite_4bpp(24, 8, p, sprs[19], palette);
		tile.draw_sprite_4bpp(16, 16, p, sprs[5], palette);
		tile.draw_sprite_4bpp(8, 16, p, sprs[20], palette);
	}
	//spin jump
	else if (protocol == 4){
		for (int i = 0; i < 32; i++){
			tile.draw_sprite_4bpp(8*(i%4), 8*(i/16)+16*((i/4)%2), p, sprs[i], palette);
		}
	}
	// samus aim up- face left
	else if (protocol == 5){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		//tile.draw_sprite_4bpp(16, 48, p, sprs[29], palette);
		tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
		tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
		tile.draw_sprite_4bpp(24, 48, p, sprs[30], palette);
	}
	// samus aim up - face right
	else if (protocol == 6){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(0, 48, p, sprs[12], palette);
		tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
		tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
	}
	//samus vertical leap
	else if (protocol == 7){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		//tile.draw_sprite_4bpp(16, 48, p, sprs[29], palette);
		tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
		tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
	}
	else if(protocol == 8){
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(16, 32, p, sprs[11], palette);
		tile.draw_sprite_4bpp(8, 32, p, sprs[26], palette);
	}
	else if (protocol == 9){
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(16, 32, p, sprs[11], palette);
		tile.draw_sprite_4bpp(24, 32, p, sprs[27], palette);
	}
	
	ppu::extra.count = 1;
	return ei;
}

int determine_protocol(uint8 pose){
	switch(pose){
		case 0x01: return 0; // stand facing right
		case 0x02: return 0; // stand facing left
		case 0x03: return 6;
		case 0x04: return 5;
		case 0x25: return 0; 
		case 0x26: return 0;
		case 0x27: return 2;
		case 0x28: return 2;
		case 0x35: return 0;
		case 0x36: return 0;
		case 0x38: return 2;
		case 0x39: return 2;
		case 0x3d: return 3;
		case 0x3e: return 3;
		case 0x43: return 2;
		case 0x44: return 2;
		case 0x4e: return 7;
		case 0x4d: return 7;
		case 0x71: return 8;
		case 0x72: return 9;
		case 0x73: return 8;
		case 0x74: return 9;
		case 0x79: return 3;
		case 0x7a: return 3;
		case 0x7b: return 3;
		case 0x7c: return 3;
		case 0x7d: return 3;
		case 0x7e: return 3;
		case 0x7f: return 3;
		case 0x80: return 3;
		case 0x85: return 0;
		case 0x89: return 0;
		case 0x8a: return 0;
		case 0xa5: return 5;
		case 0xa4: return 6;
		default: return 1;
	
	}
	return 1;
}

int offs_x(uint8 pose){
	
	return -16;
}

int offs_y(uint8 pose){
	//do stuff here
	return -20;
}