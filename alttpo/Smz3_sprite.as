

int draw_samuses(int x, int y, int ei, uint8 pose, uint8 bank, uint16 address, uint16 size0, uint16 size1, array<uint16> palette){
	//message("attempted to draw a samus");
	
	array<array<uint16>> sprs(32, array<uint16>(16)); // array of 32 different 8x8 sprite blocks
	int p = 0; // palette int, use is unknown
	int protocol = determine_protocol(pose); // decides which protocol is used for placing samus' blocks to build the sprite
	
	int offsx = offs_x(pose); // X offset to align sprite with actual location, differs by pose
	int offsy = offs_y(pose); // Y offset to align sprite with actual location, differs by pose 
	
	//initialize tile
	auto @tile = ppu::extra[ei++];
	tile.index = 0;
	tile.source = 4;
	tile.x = x + offsx;
    tile.y = y + offsy;
	tile.priority = -1;
	tile.hflip = false;
    tile.vflip = false;
    tile.width = 64;
    tile.height = 128;
	tile.pixels_clear();

	uint32 transfer0 = 0x010000 * bank + address;
	uint32 transfer1 = transfer0 + size0;

	uint16 len1 = min(size0 / 32, 16);
	uint16 len2 = min(size1 / 32, 16);
	//load data from vram into sprs
	for (int i = 0; i < len1; i++) {
		bus::read_block_u16(transfer0 + 0x20 * i, 0, 16, sprs[i]);
	}
	for (int i = 0; i < len2; i++) {
		bus::read_block_u16(transfer1 + 0x20 * i, 0, 16, sprs[i+16]);
	}
	
	
	//most of samus' poses, with only a few exceptions
	if (protocol == 0){
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
	// aim upwards
	else if(protocol == 1){
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 12; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
		tile.draw_sprite_4bpp(0, 48, p, sprs[12], palette);
		tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
		tile.draw_sprite_4bpp(24, 48, p, sprs[29], palette);
		tile.draw_sprite_4bpp(32, 48, p, sprs[30], palette);
	}
	// crouching no aim
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
	// crouching aim diagonally
	else if (protocol == 3){
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 8; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(24, 32, p, sprs[27], palette);
		tile.draw_sprite_4bpp(16, 32, p, sprs[11], palette);
		tile.draw_sprite_4bpp(8, 32, p, sprs[26], palette);
	}
	// morph ball
	else if (protocol == 4){
		for (int i = 0; i < 4; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 4; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
		tile.draw_sprite_4bpp(16, 16, p, sprs[5], palette);
		tile.draw_sprite_4bpp(8, 16, p, sprs[20], palette);
	}
	//spin jump
	else if (protocol == 5){
		for (int i = 0; i < 16; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
		}
		for (int i = 0; i < 16; i++){
			tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
		}
	}
	
	return ei;
}

int determine_protocol(uint8 pose){
	switch(pose){
		case 0x03: return 1;
		case 0x04: return 1;
		case 0x27: return 2;
		case 0x28: return 2;
		case 0x38: return 3;
		case 0x3e: return 3;
		case 0x43: return 3;
		case 0x44: return 3;
		case 0x71: return 3;
		case 0x72: return 3;
		case 0x73: return 3;
		case 0x74: return 3;
		case 0x79: return 4;
		case 0x7a: return 4;
		case 0x7b: return 4;
		case 0x7c: return 4;
		case 0x7d: return 4;
		case 0x7e: return 4;
		case 0x7f: return 4;
		case 0x80: return 4;
		case 0x81: return 5;
		case 0x82: return 5;
		default: return 0;
	
	}
	return 0;
}

uint16 min(uint16 a, uint16 b){
	if (a < b) return a;
	return b;
}

int offs_x(uint8 pose){
	
	return -16;
}

int offs_y(uint8 pose){
	//do stuff here
	return -20;
}