What it is
===

This directory contains the ASM code (WDC 65816) which directly patches an SMC ROM dump of ALTTP.
Currently only tested against US v1.2 version of the ROM.

Requires [bass](https://code.byuu.org/bass) to assemble, see the `build.sh` bash script I use for
testing and development.

What it does
===

This patch to the ALTTP ROM enhances the game to add support for rendering a remote player's sprites
onto the local player's screen if the two players happen to be in the same area/room.

How it works
===

In order to render the remote player's sprites into the local player's game, the OAM table and VRAM
sprite tile data (graphics) must be updated every frame that the remote player is on the screen.
The first challenge is in finding free VRAM space to use for synchronizing the remote player's graphics
to.

Finding free VRAM space
---
After some not-so-extensive testing, I've identified 5 16x16 sprite slots that I consider free space.

![Sprite VRAM](vram.png)

(sorry for weird colors on some of these sprites - this is just a result of using a single palette for
all of the sprites)

Looking at the VRAM snapshot image above, we can see that sprites are naturally aligned at 8x8 pixel
boundaries. Sprites in ALTTP can be either 16x16 in size or 8x8 in size. As you can see from the
very top row, rendering Link's body with sword and shield requires 18 8x8 sprite blocks (or 4 16x16
blocks and 2 8x8 blocks). The challenge here is that we now have to identify some unused sprites or
rarely-used sprites in this same page of VRAM to use to render the remote player's sprites.

You may ask, "where are all the other animation frames used for Link's walking and slashing etc."? The
answer is that only those 4 16x16 and 2 8x8 blocks are used to render Link but their contents are
updated when Link's animation frame changes. This graphics update happens every video frame (at 60fps)
via DMA during the vertical blank period (aka v-blank) because is the one of the few times the PPU
allows VRAM data to be updated.

This DMA updating procedure is only used for Link (and rupee shimmer animations) while all other
sprite animation frames are stored as separate tiles in the same VRAM page and are not updated every
frame.

Anyway, looking at the VRAM page above, I've found 5 16x16 tiles that appear to be free or rarely used:

1. `$40` - this is that weird looking 16x16 area immediately left of the signpost sprite. I've never
seen it used but I could be wrong.
1. `$64` - this is the two 16x16 blocks for the "blob" sprite that some enemies transform into after
using the magic powder on them. These are used so infrequently in casual play let alone during speedruns,
tournaments, or randomizer races that I consider them practically free.
1. `$CB` - this is the two 16x16 blocks for the "bubble" sprites on the second to last row above the
fairy sprites. I don't think they're ever used but I could be wrong.

Those `$XY` numbers are hexadecimal addresses of 8x8 tiles and are known as CHR numbers, aka character
numbers. The top-left tile is `$00`, the immediately right tile of that is `$01`, immediately below
top-left is `$10` and so on. There are 16 rows and 16 columns of 8x8 tiles which means the bottom-right
tile is `$FF`. Hexadecimal values `0-9A-F` represent decimal values `0-15`, where characters `A-F`
represent decimal values `10-15` so that they only take up one hexadecimal place.

Why not use the two follower/tag-along sprites immediately below Link's body and head? Because these
sprites *may* be used by the local player when having a follower. I'd have to change the CHR mapping
from static to dynamic based on whether the local player has a follower or not.

Only the first page of sprite VRAM is considered for usage because its layout is relatively static.
There are two pages of sprite VRAM available but the second page changes too frequently to be useful,
despite the fact that some configurations of the second page offer many more free sprite slots.
Determining the exact configuration of the second page is a challenge because several independent
DMA transfers may be initiated over multiple frames during screen transitions which update different
sections of the second page. It would be very difficult to correctly track these DMA transfers and
determine which sprite slots can be considered free or in-use.

In total we have 5 16x16 nearly-guaranteed free sprite blocks to map the remote player's sprite data
to now. We only waste 2 8x8 blocks since Link only requires 4 16x16 blocks and 2 8x8 blocks to
render his body, shield, and sword. The other two 8x8 blocks are used for the sweat sprites when
pulling objects or for extended arm sprites when stabbing swords or throwing boomerangs, etc.

Extracting OAM sprites
---
The OAM table is what tells the PPU which 8x8 tiles (or 16x16 tiles) to render where on the screen.
There may be a total of 128 OAM sprites in the OAM table. The SNES PPU is limited to about 34 OAM
sprites per screen row.

The OAM table is actually broken into two tables: one main table where each entry is 4 bytes, and
one extra attribute table where each entry is actually 2 bits where 4 sprite entries are condensed
into one byte.

The next step is to identify which OAM sprites in the OAM table are actually used to render Link's
body, shield, and sword. Luckily for us, as it turns out, there are 12 OAM slots reserved by the
game code for this exact purpose. However, there are 2 possible locations in the OAM table where
these slots are found and that location depends on if the room has multiple levels in it (where Link
could go under or over an overpass) and whether Link is on the upper or lower level. By default, if
there is a single level in the room or if Link is on the upper level, Link's OAM sprites start at
index `$64` into the OAM table. Otherwise, if Link is on the lower level, they start at `$3E`. Even
more luckily for us, we don't have to figure this out with our own logic. The RAM address `$0352` has
us covered for this purpose as it points to the multiple-of-4 offset from the start of the OAM table
where Link's OAM slots are.

Knowing this, it's just a matter of reading the value at `$0352` and finding out which of the 12
sprites from there are in use. Determining if a sprite is in-use is as simple as checking if the Y
coordinate equals `$F0` aka `240` as this indicates the sprite is just below the visible portion of
the screen.

This process only captures Link's body, sword, shield, and shadow underneath. Much more work has to
be done to identify other OAM sprites like sword charge sparkles or dash dust that are related to
Link but may not be found within the 12 reserved slots. There may be false-positive matches to weed
out because the sword charge sparkle and dash dust sprites are reused by other game objects, e.g.
the village dashing idiot and ghosts in the sanctuary graveyard and sparkles on the magic boomerang.



WRAM communication interface
===

This patch communicates with the external world via WRAM. It is assumed that either an emulator or a
console hardware unit (like the SD2SNES) is able to read and write blocks of WRAM that the game will
then freely access. We can think of it as basically a memory-mapped network driver. It is also
assumed that this external interface (emulator or hardware) reading/writing blocks of WRAM is also
able to communicate with another hardware console or emulator running a copy of the patched ROM via
a network of some kind.

There are two defined WRAM block addresses, one representing the local player's data packet to be
sent to the remote player, and another representing the remote player's data packet that was received
from the remote player.

* `$7F7700` - local player's data packet
* `$7F8200` - remote player's data packet

Both data packets share an identical format and there is no need for external processing of the data
within these packets. The data packet is natively produced by this ROM patch and intended for direct
consumption by this ROM patch as well.

It is recommended to wrap the data packet with a message envelope when sending on the wire to
include things like a packet version, an identifying header, and possibly a checksum for error
detection / correction purposes. This message envelope must be stripped away when copying the
data into WRAM though since the ROM patch only recognizes the `struct Packet` raw binary layout
described above. The ROM patch does not need to concern itself with those kinds of details since
it won't have any means of reporting a data packet error or checksum failure to the end users.

Data packet format is defined by `struct Packet`:

    struct Packet {
        // positional information about the player:

        // -------- ------wd rrrrrrrr rrrrrrrr
        //   w: 0 = light world, 1 = dark world
        //   d: 0 = overworld, 1 = dungeon
        //   r: 16-bit area/room number (overworld/dungeon)
        uint32 location;
        uint16 x;
        uint16 y;
        uint16 z;
        // screen scroll offset from top-left corner of area:
        uint16 xoffs;
        uint16 yoffs;

        // visual aspects of player taken from SRAM at $7EFxxx:
        uint8  sword;  // $359
        uint8  shield; // $35A
        uint8  armor;  // $35B

        // DMA source address words read from WRAM at $7E0AC0..$7E0ACA which point to bank $7E:
        // These are pointers to 4bpp sprite data for sword, shield, and others. They are in
        // WRAM (bank $7E) because they are decompressed from a custom 3bpp format stored in ROM.
        uint16 dma7E_addr[6];
        // DMA source address words read from WRAM at $7E0ACC..$7E0AD6 which point to bank $10:
        // These are pointers to 4bpp sprite data for Link's body.
        uint16 dma10_addr[6];

        // Number of OAM sprites used to render Link:
        uint8        oam_count;
        // Main OAM table data (fixed array of max 12 OAM sprites):
        // (found in WRAM at $7E0800)
        OAMSprite    oam_table[12];
        // Extended OAM table data (fixed array of max 12 OAM sprites):
        // (found in WRAM at $7E0A20)
        OAMSpriteExt oam_table_ext[12];
    }

    // 4 byte struct that represents a hardware OAM sprite:
    struct OAMSprite {
        uint8 b0; // xxxxxxxx | x = X coordinate (lower 8 bits)
        uint8 b1; // yyyyyyyy | y = Y coordinate
        uint8 b2; // cccccccc | c = CHR (lower 8-bits)
        uint8 b3; // vhoopppc | c = CHR 9th bit, p = priority, o = palette, v = vertical flip, h = horiz flip
    }

    // 1 byte struct represents the extra 2 bits that couldn't fit in the 4 byte OAM struct:
    struct OAMSpriteExt {
        uint8 b4; // ------sx | s = size toggle (8x8 vs 16x16), x = X coordinate 9th bit
    }

The data packet is laid out optimally considering the limitations of 65816 assembly and the lack of
integer multiply and division opcodes. All alignment, especially for tabular data, therefore must be
at powers of two since `ASL` and `LSR` (shift left and shift right, respectively) are the only
multiplication- and division-like operations available. This explains why the OAMSprite table,
which would otherwise naturally be table of 5-byte-wide structs, is split into two tables: a
4-byte-wide entry table and a 1-byte-wide entry table for the extended attributes. This split of
the OAM table is reflected in the SNES PPU hardware design as well. The only difference is that the
extended OAM attribute table in this data packet is not compacted to fit 4 sprite entries in one byte
like the OAM hardware table. Each OAM sprite in the data packet is given one full byte and only the
two least significant bits in each byte are used.

To fully support custom shield and sword graphics for the remote player, we'd need to run a
3bpp-to-4bpp decompression routine against the ROM source address driven by the `sword` and `shield`
values for the remote player, just like how the game itself does. Hopefully this decompression only
needs to be done whenever these values change instead of on every frame. We can find free space in
WRAM (outside of the local player's buffer at `$7E9000`) to decompress the remote player's graphics
to.
