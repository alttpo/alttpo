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

// patch over PHA : PHX : PHY : PHD within original NMI routine in bank 00:
origin 0x0000D1
base   0x0080D1
    jml nmiPreHook

// give our NMI hook somewhere to return to:
origin 0x0000D5
base   0x0080D5
nmiPreReturn:;

origin 0x00021B
base   0x00821B
    jml nmiPostHook

origin 0x000220
base   0x008220
nmiPostReturn:;

// our NMI hook:
origin 0x100000
base   0x208000
nmiPreHook:
    // This is the code we replaced in the main NMI routine with the JML instruction:

    // Sets DP to $0000
    lda.w #$0000 ; tcd

    // $7EC84A[0x1FB6] - seemingly free ram (nearly 8K!)
    // $7F7667[0x6719] = free RAM!

    sep #$30    // 8-bit accumulator and x,y mode

    // $7E0010 = main module
    lda $0010
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
    lda $0011
    cmp #$02
    beq validModule
invalidModule:
    // not a good time to sync state:
    jmp nmiPreHookDone

validModule:
    constant tmp = $7F7667

    // build local packet to send to remote players:
    constant local = $7F7668
    constant local.location.lo = local + 0
    constant local.location.hi = local + 2
    constant local.x = local + 3
    constant local.y = local + 5
    constant local.z = local + 7
    constant local.xoffs = local + 9
    constant local.yoffs = local + 11
    constant local.oam_size = local + 13
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
    constant local.oam_table.0 = local + 15
    constant local.oam_table.1 = local + 16
    constant local.oam_table.2 = local + 17
    constant local.oam_table.3 = local + 18
    constant local.oam_table.4 = local + 19
    constant local.tiledata = $7F7900

    lda $0FFF   // in dark world = $01, else $00
    asl
    ora $001B   // in dungeon = $01, else $00
    sta local.location.hi
    // if in dungeon, use dungeon room value:
    and #$01
    beq overworld   // if dungeon == 0, load overworld room number:

    // load dungeon room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $00A0
    sta local.location.lo
    bra coords
overworld: // load overworld room number as word:
    rep #$30        // 16-bit accumulator and x,y mode
    lda $008A
    sta local.location.lo

coords:
    // load X, Y, Z coords:
    lda $0022
    sta local.x
    lda $0020
    sta local.y
    lda $0024
    sta local.z

    // xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3)) - int16(bus::read_u16(0x7E011A, 0x7E011B));
    lda $00E2
    clc
    sbc $011A
    sta local.xoffs
    // yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9)) - int16(bus::read_u16(0x7E011C, 0x7E011D));
    lda $00E8
    clc
    sbc $011C
    sta local.yoffs

sprites:
    // in 16-bit accumulator mode

    // $0352 = OAM index where Link sprites were written to
    constant link_oam_start = $0352

    // local.oam_size = 0;
    lda.w #$0000
    sta.l local.oam_size
    // Y is our index into tmp OAM
    ldy.w link_oam_start
sprloop:
    // read oam.y coord:
    sep #$20        // 8-bit accumulator mode
    lda.w $0801,y

    // if (oam.y == $f0) continue; // sprite is off screen
    cmp #$f0
    beq sprcont

    // copy OAM sprite into table:
    pha
    rep #$20        // 16-bit accumulator mode
    lda.l local.oam_size
    tax
    sep #$20        // 8-bit accumulator mode
    pla

    // store oam.y into table:
    sta.l local.oam_table.1,x
    // copy oam.b0 into table:
    lda.w $0800,y
    sta.l local.oam_table.0,x
    // copy oam.b2 into table:
    lda.w $0802,y
    sta.l local.oam_table.2,x
    // copy oam.b3 into table:
    lda.w $0803,y
    sta.l local.oam_table.3,x

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
    sta.l local.oam_table.4,x
    ply

    // local.oam_size += oam_entry_size
    rep #$20        // 16-bit accumulator mode
    clc
    lda.l local.oam_size
    adc.w #oam_entry_size
    sta.l local.oam_size

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

nmiPreHookDone:
    rep #$30
    jml nmiPreReturn

// Runs after main NMI routine has completed, i.e. after all DMA writes to VRAM, OAM, and CGRAM.
nmiPostHook:
    rep #$10

    // read OAM sprite 00 from VRAM into WRAM:
    if 1 {
    // base dma register is $2118, write two registers once mode ($2118/$2119), with autoincrementing target addr, read from VRAM to WRAM.
    ldx.w #$1881 ; stx $4300

    // Sets the WRAM address
    ldy.w #$7900 ; sty $4302

    // Sets the WRAM bank
    lda.b #$7F ; sta $4304

    // setup VRAM address increment mode:
    lda.b #$80 ; sta $2115

    // The vram target address is $4000 (word)
    ldy.w #$4000 ; sty $2116

    // going to read 0x10 bytes on channel 0
    ldx.w #$0010 ; stx $4305

    // activates DMA transfers on channel 0
    lda.b #$01 ; sta $420B
    }

    // This is the code our hook JML instruction replaced so we must run it here:
    sep #$30
    lda.b $13 ; sta $2100

    // jumps to the final 'pla' opcode and 'rti' afterwards
    jml nmiPostReturn
