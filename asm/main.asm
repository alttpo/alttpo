architecture wdc65816
endian lsb

// patch over header values to extend ROM size from 8Mb to 16Mb:
{
    //origin 0x007FC0 // <- 7FC0 - Bank00.asm : 9173 (db "THE LEGEND OF ZELDA  " ; 21 bytes)
    //db $23, $4E

    origin 0x007FD5 // <- 7FD5 - Bank00.asm : 9175 (db $20   ; rom layout)
    //db #$35 // set fast exhirom
    db $30 // set fast lorom

    //origin 0x007FD6 // <- 7FD6 - Bank00.asm : 9176 (db $02   ; cartridge type)
    //db $55 // enable S-RTC

    origin 0x007FD7 // <- 7FD7 - Bank00.asm : 9177 (db $0A   ; rom size)
    db $0B // mark rom as 16mbit

    //origin 0x007FD8 // <- 7FD8 - Bank00.asm : 9178 (db $03   ; ram size (sram size))
    //db $05 // mark sram as 32k

    origin 0x1FFFFF // <- 1FFFFF
    db $00 // expand file to 2mb
}

// Main loop hook:
origin 0x000056
base   0x008056
    jml mainLoopHook

origin 0x00005A
base   0x00805A
mainLoopReturn:;

// Post-NMI hook:
origin 0x00021B
base   0x00821B
    jml nmiPostHook

origin 0x000220
base   0x008220
nmiPostReturn:;

/////////////////////////////////////////////////////////////////////////////

constant pkt.location.lo = 0
constant pkt.location.hi = 2
constant pkt.x = 3
constant pkt.y = 5
constant pkt.z = 7
constant pkt.xoffs = 9
constant pkt.yoffs = 11
constant pkt.oam_count = 13
// Each OAM sprite is 5 bytes:
constant oam_entry_size = 5
// [0]: xxxxxxxx X coordinate on screen in pixels. This is the lower 8 bits.
// [1]: yyyyyyyy Y coordinate on screen in pixels.
// [2]: cccccccc Character number to use. This is the lower 8 bits. See [3]
// [3]: vhoopppc
//   v - vertical flip
//   h - horizontal flip
//   p - palette (0-7)
//   o - priority bits (0-3)
//   c - the 9th (and most significant) bit of the character number for this sprite.
// [4]: ------sx
//   x - 9th bit of X coordinate
//   s - size toggle bit
constant pkt.oam_table = 14
constant pkt.oam_table.0 = 14
constant pkt.oam_table.1 = 15
constant pkt.oam_table.2 = 16
constant pkt.oam_table.3 = 17
constant pkt.oam_table.4 = 18
constant pkt.tiledata = pkt.oam_table + (12 * oam_entry_size)
constant pkt.tiledata_size = (0x40 * 0x20) // 0x800
constant pkt.total_size = (pkt.tiledata + pkt.tiledata_size)

/////////////////////////////////////////////////////////////////////////////

constant bank = $7F
constant free_ram_addr = $7667

// scratch space
constant scratch = free_ram_addr
constant tmp_oam_size = 0

// local packet addr
constant local = $7700
// remote packet addr
constant remote = $8200 // local + pkt.total_size    // $8198

expression addr(base, offs) = base + offs
expression long(base, offs) = (bank << 16) + base + offs

/////////////////////////////////////////////////////////////////////////////


// our NMI hook:
origin 0x100000
base   0xA08000
mainLoopHook:
    // execute the code we replaced:
    // 22 B5 80 00     JSL Module_MainRouting
    jsl $0080B5

    phb
    rep #$20

    // Sets DP to $0000
    //lda.w #$0000 ; tcd

    // $7EC84A[0x1FB6] - seemingly free ram (nearly 8K!)
    // $7F7667[0x6719] = free RAM!

    sep #$30    // 8-bit accumulator and x,y mode

    // set data bank to $7F
    //lda.b #$7F; pha ; plb

    // $7E0010 = main module
    lda $10
    // $07 is dungeon
    cmp #$07
    beq validModule
    // $09 is overworld
    cmp #$09
    beq validModule
    // $0e can be dialogue/monologue or menu
    cmp #$0e
    bne invalidModule
    // check $0e submodule == $02 which is dialogue/monologue
    lda $11
    cmp #$02
    beq validModule
invalidModule:
    // not a good time to sync state:
    jmp mainLoopHookDone

validModule:
    // build local packet to send to remote players:
    lda $0FFF   // in dark world = $01, else $00
    asl
    ora $1B   // in dungeon = $01, else $00
    sta.l long(local, pkt.location.hi)
    // if in dungeon, use dungeon room value:
    and #$01
    beq overworld   // if dungeon == 0, load overworld room number:

    // load dungeon room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $A0
    sta.l long(local, pkt.location.lo)
    bra coords
overworld: // load overworld room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $8A
    sta.l long(local, pkt.location.lo)

coords:
    // load X, Y, Z coords:
    lda $22
    sta.l long(local, pkt.x)
    lda $20
    sta.l long(local, pkt.y)
    lda $24
    sta.l long(local, pkt.z)

    // xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3)) - int16(bus::read_u16(0x7E011A, 0x7E011B));
    lda $E2
    clc
    sbc $011A
    sta.l long(local, pkt.xoffs)
    // yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9)) - int16(bus::read_u16(0x7E011C, 0x7E011D));
    lda $E8
    clc
    sbc $011C
    sta.l long(local, pkt.yoffs)

sprites:
    // in 16-bit accumulator mode

    // $0352 = OAM index where Link sprites were written to
    constant link_oam_start = $0352

    // tmp_oam_size = #$0000
    lda.w #$0000
    sta.l long(scratch, tmp_oam_size)

    // local.oam_count = #$00
    sep #$20        // 8-bit accumulator mode
    sta.l long(local, pkt.oam_count)

    // Y is our index into tmp OAM
    ldy.w link_oam_start
sprloop:
    // read oam.y coord:
    sep #$20        // 8-bit accumulator mode
    lda $0801,y

    // if (oam.y == $f0) continue; // sprite is off screen
    cmp #$f0
    beq sprcont

    // copy OAM sprite into table:
    pha
    rep #$20        // 16-bit accumulator mode
    lda.l long(scratch, tmp_oam_size)
    tax
    sep #$20        // 8-bit accumulator mode
    pla

    // store oam.y into table:
    sta.l long(local, pkt.oam_table.1),x
    // copy oam.b0 into table:
    lda $0800,y
    sta.l long(local, pkt.oam_table.0),x
    // copy oam.b2 into table:
    lda $0802,y
    sta.l long(local, pkt.oam_table.2),x
    // copy oam.b3 into table:
    lda $0803,y
    sta.l long(local, pkt.oam_table.3),x

    // load extra bits from extended table:
    phy
    rep #$20        // 16-bit accumulator mode
    // a = y >> 2
    tya
    lsr
    lsr
    // y = a
    tay
    sep #$20        // 8-bit accumulator mode
    // luckily for us, $0A20 through $0A9F contain each sprite's extra 2-bits at byte boundaries and are not compacted
    lda $0A20,y
    sta.l long(local, pkt.oam_table.4),x
    ply

    // local.oam_size += oam_entry_size
    rep #$20        // 16-bit accumulator mode
    clc
    lda.l long(scratch, tmp_oam_size)
    adc.w #oam_entry_size
    sta.l long(scratch, tmp_oam_size)

    // local.oam_count++
    lda.l long(local, pkt.oam_count)
    inc
    sta.l long(local, pkt.oam_count)

sprcont:
    rep #$20        // 16-bit accumulator mode
    // y += 4
    iny #4
    // if ((y - link_oam_start) < $30) goto sprloop;
    tya
    clc
    sbc.w link_oam_start
    cmp.w #$0030    // number of OAM slots that are reserved for Link body
    bcc sprloop

    // TODO: get sword and sword sparkle tiles too

mainLoopHookDone:
    sep #$30
    plb
    jml mainLoopReturn


// Runs after main NMI routine has completed, i.e. after all DMA writes to VRAM, OAM, and CGRAM.
nmiPostHook:
    sep #$30    // 8-bit accumulator and x,y mode

    // flag used to indicate that special screen updates need to happen.
    //lda $0710
    //bne nmiPostHookDone

    // $7E0010 = main module
    lda $10
    // $07 is dungeon
    cmp #$07
    beq nmiPostValidModule
    // $09 is overworld
    cmp #$09
    beq nmiPostValidModule
nmiPostInvalidModule:
    // not a good time to sync state:
    jmp nmiPostHookDone

nmiPostValidModule:
    // TODO: forego DMA read transfer in favor of script reading ROM directly using
    // bank $10 addresses for Link's sprite captured from $0ACE, $0AD2, $0AD6, etc.
    // (see bank00.asm: NMI_DoUpdates)

    // We still need DMA to transfer remote player's sprites into VRAM. Remote player's
    // packet could just refer to local player's ROM addresses for sprites. This would
    // mean the local player would not see remote player's customized sprites. Although,
    // this could be made possible if customized sprite data were exchanged before gameplay
    // and included in extra ROM space in this romhack; we added an extra 1MB after all.
    // Going further with this idea, perhaps all known customized sprite sets could be
    // included in the ROM and referred to by bank/addr in exchanged packet data.

    // WRAM locations for source addresses of animated sprite tile data:
    // bank:[addr] where bank is direct and [addr] is indirect

    // $10:[$0ACE] -> $4100 (0x40 bytes) (bottom of head)
    // $10:[$0AD2] -> $4120 (0x40 bytes) (bottom of body)
    // $10:[$0AD6] -> $4140 (0x20 bytes) (bottom sweat/arm/hand)

    // $10:[$0ACC] -> $4000 (0x40 bytes) (top of head)
    // $10:[$0AD0] -> $4020 (0x40 bytes) (top of body)
    // $10:[$0AD4] -> $4040 (0x20 bytes) (top sweat/arm/hand)

    // bank $7E (WRAM) is used to store decompressed 3bpp->4bpp tile data

    // $7E:[$0AC0] -> $4050 (0x40 bytes) (top of sword slash)
    // $7E:[$0AC4] -> $4070 (0x40 bytes) (top of shield)
    // $7E:[$0AC8] -> $4090 (0x40 bytes) (Zz sprites or bugnet top)
    // $7E:[$0AE0] -> $40B0 (0x20 bytes) (top of rupee)
    // $7E:[$0AD8] -> $40C0 (0x40 bytes) (top of movable block)

    // only if bird is active
    // $7E:[$0AF6] -> $40E0 (0x40 bytes) (top of hammer sprites)

    // $7E:[$0AC2] -> $4150 (0x40 bytes) (bottom of sword slash)
    // $7E:[$0AC6] -> $4170 (0x40 bytes) (bottom of shield)
    // $7E:[$0ACA] -> $4190 (0x40 bytes) (music note sprites or bugnet bottom)
    // $7E:[$0AE2] -> $41B0 (0x20 bytes) (bottom of rupee)
    // $7E:[$0ADA] -> $41C0 (0x40 bytes) (bottom of movable block)

    // only if bird is active
    // $7E:[$0AF8] -> $41E0 (0x40 bytes) (bottom of hammer sprites)

    rep #$20    // m,a to 16-bit

    lda $4350 ; pha // preserve DMA parameters
    lda $4352 ; pha // preserve DMA parameters
    lda $4354 ; pha // preserve DMA parameters
    lda $4356 ; pha // preserve DMA parameters

    lda $4360 ; pha // preserve DMA parameters
    lda $4362 ; pha // preserve DMA parameters
    lda $4364 ; pha // preserve DMA parameters
    lda $4366 ; pha // preserve DMA parameters

    lda $4370 ; pha // preserve DMA parameters
    lda $4372 ; pha // preserve DMA parameters
    lda $4374 ; pha // preserve DMA parameters
    lda $4376 ; pha // preserve DMA parameters

    sep #$20    // m,a to  8-bit
    rep #$10    // x,y to 16-bit

    // read first 0x40 sprites from VRAM into WRAM:
    if 1 {
    lda.b   #$80 ; sta $2115    // VRAM address increment mode
    ldy.w #$4DB0 ; sty $2116    // VRAM target address

    ldy.w #$1801 ; sty $4350    // DMA from WRAM to VRAM ($2118)
                   sty $4360
                   sty $4370
    lda.b   #$10 ; sta $4354    // source bank
                   sta $4364
                   sta $4374
    ldy.w  $0ACE ; sty $4352    // source address (5)
    ldy.w  $0AD2 ; sty $4362    // source address (6)
    ldy.w  $0AD6 ; sty $4372    // source address (7)
    ldx.w #$0040 ; stx $4355    // transfer size (5)
                   stx $4365    // transfer size (6)
    ldx.w #$0020 ; stx $4375    // transfer size (7)

    lda.b   #$E0 ; sta $420B    // activates DMA transfers on channel 5, 6 and 7

    ldy.w #$4CB0 ; sty $2116    // VRAM target address
    ldy.w  $0ACC ; sty $4352    // source address (5)
    ldy.w  $0AD0 ; sty $4362    // source address (6)
    ldy.w  $0AD4 ; sty $4372    // source address (7)
    ldx.w #$0040 ; stx $4355    // transfer size (5)
                   stx $4365    // transfer size (6)
    ldx.w #$0020 ; stx $4375    // transfer size (7)

    lda.b   #$E0 ; sta $420B    // activates DMA transfers on channel 5, 6 and 7
    }

    rep #$20    // m,a to 16-bit

    pla ; sta $4376 // restore DMA parameters
    pla ; sta $4374 // restore DMA parameters
    pla ; sta $4372 // restore DMA parameters
    pla ; sta $4370 // restore DMA parameters

    pla ; sta $4366 // restore DMA parameters
    pla ; sta $4364 // restore DMA parameters
    pla ; sta $4362 // restore DMA parameters
    pla ; sta $4360 // restore DMA parameters

    pla ; sta $4356 // restore DMA parameters
    pla ; sta $4354 // restore DMA parameters
    pla ; sta $4352 // restore DMA parameters
    pla ; sta $4350 // restore DMA parameters

nmiPostHookDone:
    sep #$30

    // This is the code our hook JML instruction replaced so we must run it here:
    lda.b $13 ; sta $2100

    // Jump back to the instruction after our JML interception:
    jml nmiPostReturn
