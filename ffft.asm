.feature c_comments
.feature org_per_seg

/*
 * Original code copyright 2023 Justin Olbrantz (Quantam)
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

.include "build.inc"
.include "mmc3regs.inc"
.include "bhop.inc"

 /*
	ORIGINAL SOUND DESIGN

	Final Fantasy takes a very ad-hoc approach to its sound and music. While it has a minimum viable music engine, only combat has a proper SFX engine. Out of combat, SFX are a mixture of "fanfares" (short music pieces that are used like sound effects) and direct register writes, which usually have only a single time step and rely on hardware envelope and/or sweep. Music uses the square 1, square 2, and triangle channels, while SFX use the square 2 and noise channels.
	
	The square 2 channel is multiplexed via Square2SfxFrames; when a SFX begins, this variable will be set to the length of the SFX and the music engine will not touch the square 2 channel during this time. As the music engine cannot use the noise channel there is no multiplexing mechanism and an analog of Square2SfxFrames only exists for battle SFX and even then only for the SFX engine to track its own execution, not communicate to the music engine.
	
	PRINCIPLE OF OPERATION
	
	FamiTracker playback is actually the easiest part of an FT conversion; with a handful of decisions about where to place code and data, bhop just does its thing once per frame. The "hard part" of the conversion is the glue code that interfaces with the game, especially the game's sound effects. bhop has an API for releasing channels for external use, but the glue code must keep bhop in sync with the game's SFX and music to ensure that the right code is using the hardware at any time. Additionally, the glue code must receive play track commands from the game, translate them to the right track, and report the status to the game loop.
	
	The combination of FF's ad-hoc approach to sound effects, very small amount of free ROM space, and intended integration into the FF Randomizer necessitate significant structural and functional differences from other FT conversions. 
	
	Rather than relocating portions of the game code to new banks to make room for code patches of different sizes in different banks, ffft goes to great lengths to not alter the size of code in other banks, only making patches in situ, in the space used by the unpatched code. This is accomplished in large part by introducing trigger variables that intercept writes to game variables or hardware registers and perform some action in the new ffft code. The most important of these are NoiseCtrl1, NoisePeriodHi, and SilenceMusicAndSfx, which capture register writes regarding the noise channel to implement an analog of Square2SfxFrames for the noise channel; additionally, FanfareMusicState allows for BGM to be paused during a fanfare and then resumed, provided the music and fanfare use different music engines. Note that ffft only patches SFX that can overlap with music; SFX that only play when music is stopped are not patched and will not work correctly if they become used with music, without additional changes.
	
	Additionally, instead of placing the hub code for the sound system in the common bank and calling other banks as appropriate, ffft places this code in the hi native sound bank that contains the music engine code at $a000. This code loads the new ffft bank at $8000 and calls into it as necessary. When this code needs to access FT track data the corresponding track is loaded at $a000, and the hi native sound bank is reloaded before returning to it. This is a lot more work than previous conversions, but eliminates the need to make major patches to the common bank that is highly patched by the randomizer.
*/

; Size of an MMC3 bank that FF is converted to
BANK_SIZE = $2000

; Length of the native music table
NUM_NAT_TRACKS = $18

; MMC1 bank number of the sound bank
NAT_SOUND_BANK = $d
; MMC3 bank numbers of the sound bank. The lo bank contains the music data and various non-music stuff, while the hi bank contains the music code.
NAT_SOUND_BANK_LO = NAT_SOUND_BANK * 2
NAT_SOUND_BANK_HI = NAT_SOUND_BANK_LO + 1

; MMC3 bank number of the FT code bank that will be loaded at $8000
.define FT_CODE_BANK_LO <.bank(TrackMapTable)

; Mesen names for hardware registers
Sq0Duty_4000 := $4000
Sq0Sweep_4001 := $4001
Sq0Timer_4002 := $4002
Sq0Length_4003 := $4003
Sq1Duty_4004 := $4004
Sq1Sweep_4005 := $4005
Sq1Timer_4006 := $4006
Sq1Length_4007 := $4007
TrgLinear_4008 := $4008
TrgTimer_400A := $400a
TrgLength_400B := $400b
NoiseVolume_400C := $400c
NoisePeriod_400E := $400e
NoiseLength_400F := $400f
DmcFreq_4010 := $4010
DmcCounter_4011 := $4011
DmcAddress_4012 := $4012
DmcLength_4013 := $4013
SpriteDma_4014 := $4014
ApuStatus_4015 := $4015

PpuControl_2000 := $2000
PpuMask_2001 := $2001
PpuStatus_2002 := $2002
OamAddr_2003 := $2003
PpuScroll_2005 := $2005
PpuAddr_2006 := $2006
PpuData_2007 := $2007

Ctrl1_4016 := $4016
Ctrl2_FrameCtr_4017 := $4017

; Default base address for FTMs. This is only for backward compatibility with versions of makeftrom that don't support multiple FTMs per bank.
FTM_BASE_ADDR := $a000

; Current music states for MusicState
NOT_PLAYING = 0
PLAYING_NAT = 1
PLAYING_FT = 2

; Value of FtTrackToPlay indicating no track to play (though only the MSB matters)
NO_FT_TRACK_TO_PLAY = $ff
; Resume the previously playing FT track before it was paused by a native fanfare
RESUME_FT_TRACK = $7f

; Sentinel value for register shadow variables
HI_FREQ_NOT_SET = $fc

MAX_TRACKS = $40 ; Actually $3f, but pad it out

; 0-based track number that will be translated through the encounter music table. The exact meaning actually depends on where in the code it is referenced. Prior to translation it causes translation to occur. But it is also the default track for encounters, and after translation it is a real, playable track. This allows individual encounter tracks to be specified while also allowing a global default to be easily changed.
BATTLE_PSEUDO_TRACK = $f

/*
	Native music engine state variable that serves as both commands to the engine and status from it. Commands have one of the following forms:
		80: Stop playback. This may either be issued by the game or by the music engine itself when the end of track command is encountered in music data.
		01nn nnnn: Play track n - 1. In ffft, game writes to this variable cause the current track to be stopped and will not be resumed after a fanfare. If the previous track was not stopped (played through FanfareMusicState), commands to play the previous track will resume it rather than restarting it.
	Statuses have one of the following forms:
		81: Playback has stopped. Some parts of the game watch for this value to know when fanfares have finished.
		00nn nnnn: The native engine is in the process of starting track n - 1. This is a quirk of how the engine initializes 1 channel per frame when starting a track.
		0: Music is playing
*/
NatMusicState := $4b

; Current battle formation number used to translate the battle music
CurForm := $6a

; The number of remaining frames the current SFX will be using the square 2 channel
Square2SfxFrames := $7e

; Global frame counter
FrameCtr := $f0

; Shadow of NatMusicState that responds only to play track commands, for implementing pause and continue. Game commands to play a fanfare that should (if possible) resume the prior music after completion are redirected here. Preserves the track number to potentially be resumed afteward.
FanfareMusicState := $f3

; Size remaining in current battle SFX data, or 0 if none. This is used to determine when the noise channel is no longer in use as the frame counter never actually reaches 0.
NoiseBattleSfxLeft := $6da0

; Buffer used to render "The End", used to relocate it to a more convenient location
TheEndBuff := $7800

; The original FF PlayTrack function
PlayNatTrack := $b003

; Macros to get ROM file offsets from banks/offsets
.define SRC_OFFS(bank, offs) ((BANK_SIZE * (bank)) + (offs) + $10)
.define SRC_BOFFS(bank) SRC_OFFS (bank), 0

; Macros to include ROM data
.macro inc_bank_part bank_idx, offs, size
	.incbin SRC_ROM, SRC_OFFS bank_idx, offs, size
.endmacro

.macro inc_bank_range bank_idx, start_offs, end_offs
	.incbin SRC_ROM, SRC_OFFS (bank_idx), (start_offs), (end_offs) - (start_offs)
.endmacro

.macro inc_banks start_bank, end_bank, new_start_bank
	.ifnblank new_start_bank
	tgt_bank .set (new_start_bank)
	.else
	tgt_bank .set (start_bank)
	.endif

	.repeat (end_bank) - (start_bank), bank_idx
	.segment .sprintf("BANK%X", bank_idx + tgt_bank)
	;.out .sprintf("BANK%X", bank_idx + tgt_bank)
	.incbin SRC_ROM, SRC_BOFFS bank_idx + (start_bank), BANK_SIZE
	.endrepeat
.endmacro

; Macro to verify that patches are made at the right place and do not overflow
.macro patch_segment name, size, start_addr, end_addr
	.segment .string(name)

	.import .ident(.sprintf("__%s_SIZE__", .string(name)))
	.assert .ident(.sprintf("__%s_SIZE__", .string(name))) <= (size), lderror, .sprintf("Segment '%s' exceeds size limit of $%x bytes", .string(name), (size))

	.ifnblank start_addr
	.import .ident(.sprintf("__%s_LOAD__", .string(name)))
	.assert .ident(.sprintf("__%s_LOAD__", .string(name))) = (start_addr), lderror, .sprintf("Segment '%s' was not loaded at the correct address %x", .string(name), (start_addr))
	.endif

	.ifnblank end_addr
	.assert (size) = (end_addr) + 1 - (start_addr), error, .sprintf("$%x + 1 - $%x != $%x", (end_addr), (start_addr), (size))
	.endif
.endmacro

; Randomizer variable to track the current bank to be restored after a far jump
CurBank := $60fc

.segment "ZEROPAGE": zeropage
	; Temporaries used by the sound engine but available outside it
	.org $4d
	
Temp0: .byte 0
Temp1: .byte 0

.segment "VARS"

.segment "HIVARS"
; Whether the Initialize function has run yet since reset
IsInitialized: .byte 0

; Shadow registers to intercept SFX writes to monitor SFX usage of the noise channel
NoiseCtrl1: .byte 0
NoisePeriodHi: .byte 0

; In some places where an infinite noise sound effect is interrupted (e.g. a battle on the ship) volume is not set to 0 but ApuStatus_4015 is cleared. If SilenceMusicAndSfx is set to 0, sets ApuStatus_4015 and stops the infinite SFX.
SilenceMusicAndSfx: .byte 0

; Mask of sound channels that were in use last frame. Used to determine what channels need to be muted/unmuted this frame.
PrevSfxChanMask: .byte 0

; Current and next states of music playback (FT, native, or neither)
MusicState: .byte 0
NextMusicState: .byte 0

; Banks used by the current music track
CurNatBank: .byte 0 ; Currently unused
CurFtBank: .byte 0

; FT bank, base address, and track to start, or high bit set if none
FtTrackToPlay: .byte 0
FtBankToPlay: .byte 0
FtAddrToPlay: .addr 0

; Current track playing in each engine, or the high bit set if none. Separate variables to allow for one track to be paused while the other engine plays a fanfare.
CurNatTrack: .byte 0
CurFtTrack: .byte 0

; Remaining frames the noise channel will be in use by SFX, or $ff for infinite. This must be calculated from NoiseCtrl1 and NoisePeriodHi as FF only provides this information for battle SFX. In most places the game ends SFX noise channel use by setting NoiseCtrl1 to $30 or 0, the latter probably a bug.
NoiseSfxFrames: .byte 0

; Switch to determine whether to build the full version or the FF randomizer version. FFR already expands the ROM size and changes the mapper, so some things are not necessary.
.ifndef FFR_BUILD
.define FFR_BUILD 0
.endif

.segment "HDR"
.incbin SRC_ROM, 0, $10

.if !FFR_BUILD

; Include the ROM banks so they can be patched
inc_banks 0, $1e
inc_banks $1e, $20, $3e

patch_segment PATCH_HDR_NUM_BANKS, 1
	.byte $20
	
patch_segment PATCH_HDR_MAPPER, 1
	.byte $43
	
.else

; Already converted. Just include all the banks.
inc_banks 0, $26
inc_banks $27, $40

.endif ; FFR_BUILD

; Patches to relocate The End buffer

patch_segment PATCH_CLEAR_END_BUFF, $12, $a4b6, $a4c7
	sta TheEndBuff, X
	sta TheEndBuff + $100, X
	sta TheEndBuff + $200, X
	sta TheEndBuff + $300, X
	sta TheEndBuff + $400, X
	sta TheEndBuff + $500, X
	
patch_segment PATCH_END_BUFF_ADDR, 2, $a565
	adc #(>TheEndBuff - 8)
	
patch_segment PATCH_END_BUFF_ADDR2, 2, $a65f
	adc #(>TheEndBuff - 8)
	
; Patches to redirect play fanfare commands to FanfareMusicState

.macro patch_fanfare_sta segment
patch_segment segment, 2
	sta FanfareMusicState
.endmacro

patch_fanfare_sta PATCH_PLAY_FANFARE_54
patch_fanfare_sta PATCH_PLAY_FANFARE_54_3
patch_fanfare_sta PATCH_PLAY_FANFARE_55
patch_fanfare_sta PATCH_PLAY_FANFARE_56
patch_fanfare_sta PATCH_PLAY_FANFARE_57

patch_segment PATCH_PLAY_FANFARE_54_2, 2
	stx FanfareMusicState
	
patch_segment PATCH_PLAY_FANFARE_54_58, 2
	stx FanfareMusicState
	
patch_segment PATCH_UPD_SOUND, $48, $b099, $b0e0
.proc UpdateSound ; $2b bytes
	; Should be free to clobber everything
	; $f bytes

	; Determine how things will go this frame
	lda #SWITCH_BANK_8
	sta BankCtrlReg
	
	lda #FT_CODE_BANK_LO
	sta BankReg
	
	jsr UpdateSoundPart1
	bcc @SkipNative

@Native: ; 9 bytes
	; Update native music
	lda #NAT_SOUND_BANK_LO
	sta BankReg
	
	lda NatMusicState
	beq @UpdateNative
	
@PlayNative: ; 6 bytes
	; Start a new track. This path WILL NOT be taken for stop music or other states.
	jsr PlayNatTrack
	
	jmp @NativeCommon

@UpdateNative: ; 3 bytes
	; Stub to call the rest of this function as a function
	jsr UpdateNatSoundCont
	
@NativeCommon: ; 5 bytes
	lda #FT_CODE_BANK_LO
	sta BankReg
	
@SkipNative: ; 3 bytes
	; Do FT stuff once the final native state is known
	jmp UpdateSoundPart3
.endproc ; UpdateSound

	.res $1f
	
UpdateNatSoundCont: ; b0e1

.segment "FT_CODE_BANK"
; The track map table that maps game track numbers to engine, bank, and music track number
TrackMapTable:
	.repeat NUM_NAT_TRACKS, i
	.byte NAT_SOUND_BANK_LO, i
	.endrepeat
	
	.repeat MAX_TRACKS - NUM_NAT_TRACKS
	.byte NAT_SOUND_BANK_LO, NUM_NAT_TRACKS - 1
	.endrepeat
	
; FT module base addresses for each track
ModBaseAddrs:
	.repeat MAX_TRACKS
	.addr FTM_BASE_ADDR
	.endrepeat
	
; Track numbers for each battle encounter number
FormTrackIdcs: .res $100, $f
	
.proc Initialize
	lda #NOT_PLAYING
	sta MusicState
	sta NextMusicState
	
	lda #NAT_SOUND_BANK_LO
	sta CurNatBank
	lda #(FT_CODE_BANK_LO + 1)
	sta CurFtBank
	
	lda #NO_FT_TRACK_TO_PLAY
	sta FtTrackToPlay
	
	sta CurNatTrack
	sta CurFtTrack

	lda #$0
	sta FanfareMusicState
	
	sta Square2SfxFrames
	sta NoiseSfxFrames
	sta NoiseBattleSfxLeft
	sta PrevSfxChanMask
	
	lda #$30
	sta NoiseCtrl1

	lda #HI_FREQ_NOT_SET
	sta NoisePeriodHi
	sta SilenceMusicAndSfx
	
	lda #$ff
	sta IsInitialized
	
	rts
.endproc ; Initialize

.proc UpdateSoundPart1
/*	Possible outcomes:
	- Not carry: do not update native music
	- Carry and NatMusicState != 0: Call PlayNatTrack
	- Carry and NatMusicState == 0: Call UpdateNatSoundCont
*/
	; Initialize if necessary
	lda IsInitialized
	bne @Initialized
	
	jsr Initialize
	
@Initialized:
	; Synchronize with the noise channel state
	jsr UpdateNoiseSfx
	
	; See if there's a music command. This must override fanfare as the randomizer can create unusual situations where both are set and the music should take precedence.
	lda NatMusicState
	asl A
	bcs @StopTrack
	bmi @PlayTrack
	
	; If there's a fanfare to play, propagate it to NatMusicState
	lda FanfareMusicState
	beq @Update
	
@IsFanfare:
	sta NatMusicState
	
	asl A
	bcs @StopTrack ; MSB set
	bmi @PlayTrack ; 2nd MSB set
	
@Update:
	; No new command, so just update
	lda MusicState
	cmp #PLAYING_FT
	beq @UpdateFt
	
	jmp @UpdateNative

@StopTrack:
	bne @StopDone ; Already stopped
	
	jsr StopTrack
	
@StopDone:
	clc ; Nothing further for the native engine to do
	
	rts
		
@PlayTrack:
	; Is it the battle track?
	cmp #((BATTLE_PSEUDO_TRACK + $41) * 2)
	bne @NotBattle
	
@IsBattle:
	; Translate the formation to track number
	ldx CurForm
	lda FormTrackIdcs, X
	
	jmp @PlayCommon
	
@NotBattle:
	; Get the table index from track number
	lsr A
	sec
	sbc #$41
	
@PlayCommon:
	; Look up the track in the track map
	pha
	
	asl A
	tax
	lda TrackMapTable, X
	bpl @NatTrack
	
@FtTrack:
	; MSB of the bank number indicates it's an FT track and its bank is NOTed
	eor #$ff
	sta FtBankToPlay
	
	pla
	
	; Is it being resumed after a fanfare?
	cmp CurFtTrack
	sta CurFtTrack
	bne @NewFtTrack
	
	lda MusicState
	cmp #PLAYING_FT
	beq @NewFtTrack
	
@ResumeFtTrack:
	lda #RESUME_FT_TRACK
	
	bne @PlayFtCommon
	
@NewFtTrack:
	; Look up the location of the track
	lda ModBaseAddrs, X
	sta FtAddrToPlay
	lda ModBaseAddrs + 1, X
	sta FtAddrToPlay + 1
	
	lda TrackMapTable + 1, X
	
@PlayFtCommon:
	sta FtTrackToPlay

	lda #PLAYING_FT
	sta NextMusicState

	ldx #$0
	stx NatMusicState

	lda FanfareMusicState
	stx FanfareMusicState
	bne @UpdateFt
	
@NotFtFanfare:
	; Clear native track number if not playing a fanfare
	dex
	stx CurNatTrack
	
@UpdateFt:
	; The native UpdateSound decrements the SFX frame counter. Replicate that here since it won't be executed this frame.
	lda Square2SfxFrames
	beq @NoSquare2Sfx
	
	dec Square2SfxFrames
	
@NoSquare2Sfx:
	; Check if the track has finished
	lda tempo
	bne @DoneWithFt
	ldx FtTrackToPlay
	inx
	beq @DoneWithFt
	
	; Non-looping track has finished
	jsr StopTrack
	
@DoneWithFt:
	clc ; It's playing an FT track now
	
	rts
	
@NatTrack:
	; If the MSB of the track number is set, the target track is none
	lda TrackMapTable + 1, X
	bpl @PlayNatTrack
	
	pla
	
	jmp @StopTrack

@PlayNatTrack:
	clc
	adc #$41
	sta NatMusicState
	
	lda #PLAYING_NAT
	sta NextMusicState
	
	pla
	
	; Is it being resumed after a fanfare?
	ldx #$0
	cmp CurNatTrack
	sta CurNatTrack
	bne @NewNatTrack
	
	lda MusicState
	cmp #PLAYING_NAT
	beq @NewNatTrack
	
@ResumeNatTrack:
	stx NatMusicState

@NewNatTrack:
	lda FanfareMusicState
	stx FanfareMusicState
	bne @UpdateNative
	
@NotNatFanfare:
	; Clear the current FT track if not a fanfare
	dex
	stx CurFtTrack
	
@UpdateNative:
	; Execute the part of PlayNatTrack that was relocated, and signal to execute the rest
	jsr MovedUpdateNatSound
	
	sec
	
	rts
.endproc ; UpdateSoundPart1

.proc StopTrack
	ldx #$ff
	lda MusicState
	cmp #PLAYING_FT
	beq @StopFt
	
@StopNat:
	; Special case: MovedUpdateNatSound should run to respond, but no further native code should run
	stx CurNatTrack
	
	jsr MovedUpdateNatSound
	
	bne @StopCommon
	
@StopFt:
	; Nothing special to do other than changing the state
	stx CurFtTrack
	
	lda #$81
	sta NatMusicState

@StopCommon:
	lda #$0
	sta FanfareMusicState
	
	lda #NOT_PLAYING
	sta NextMusicState

	rts
.endproc ; StopTrack

.proc MovedUpdateNatSound
	; Mostly relocated directly from the native engine to make space for patching
	lda NatMusicState
	bmi @NotPlaying

@Playing:
	bne @Done ; Need to start a new track but can't do that from here
	
@Update:
	; At return we'll be equivalent to b0e1
	lda $bf
	bmi @NoNewSquare1Note
	
	lda $bc
	ora #$70
	sta Sq0Duty_4000
	
	lda #$7f
	sta Sq0Sweep_4001
	
	lda $be
	sta Sq0Timer_4002
	
	lda $bf
	sta Sq0Length_4003
	
	lda #$80
	sta $bf
	
	rts
	
@NoNewSquare1Note:
	lda $bc
	ora #$70
	sta Sq0Duty_4000
	
	lda #$7f
	sta Sq0Sweep_4001
	
	rts
	
@NotPlaying:
	cmp #$80
	bne @Done
	
@MusicEnding:
	lda #$70
	sta Sq0Duty_4000
	sta Sq1Duty_4004
	; sta NoiseVolume_400C
	
	lda #$80
	sta TrgLinear_4008
	
	inc NatMusicState
	
@Done:
	rts
.endproc ; MovedUpdateNatSound

.proc UpdateSoundPart3
SfxChanMask := Temp0

	; Is there a new FT track to play?
	lda FtTrackToPlay
	bmi @NoNewTrack
	
@PlayFt:
	; Switch to the right bank and initialize the track if not resuming after fanfare
	ldx #SWITCH_BANK_A
	stx BankCtrlReg
	
	ldx FtBankToPlay
	stx CurFtBank
	stx BankReg
	
	cmp #RESUME_FT_TRACK
	beq @ResumeFt
	
	; Load the module address into y:x
	ldx FtAddrToPlay
	ldy FtAddrToPlay + 1
	
	jsr bhop_init
	
	; bhop does not remember released channels between tracks, so make sure we'll correctly detect channels that need to be released later
	lda #$0
	sta PrevSfxChanMask
	
@ResumeFt:
	lda #NO_FT_TRACK_TO_PLAY
	sta FtBankToPlay
	sta FtTrackToPlay
	
@NoNewTrack:
	; TODO: Watch for end of native track and update NatMusicState
	
	ldx MusicState
	lda NextMusicState
	sta MusicState
	
	cmp #PLAYING_FT
	beq @CheckSfxChans
	
	; No FT track playing. Mute all channels.
	lda #$f
	sta SfxChanMask

	bne @CheckMuteUmmutes

@CheckSfxChans:	
	; Build the mask of channels to mute/unmute
	lda #$0
	sta SfxChanMask
	
	lda NoiseSfxFrames
	ora NoiseBattleSfxLeft
	beq @CheckSquare2
	
@NoiseInUse:
	sec
	rol SfxChanMask ; Noise
	
@CheckSquare2:
	asl SfxChanMask ; Triangle
	
	lda Square2SfxFrames
	adc #$ff ; Carry is clear from asl
	rol SfxChanMask ; Square 2
	asl SfxChanMask ; Square 1
	
@CheckMuteUmmutes:
	; If necessary mute/unmute bhop channels for SFX
	lda SfxChanMask

	cmp PrevSfxChanMask
	beq @ChanMaskChecked

@MuteUnmuteChans:
	; Any to mute?
	lda PrevSfxChanMask
	eor #$f
	and SfxChanMask
	beq @NoNewMutes
	
	jsr bhop_mute_channels
	
@NoNewMutes:
	; Any to unmute?
	lda SfxChanMask
	eor #$f
	and PrevSfxChanMask
	beq @NoNewUnmutes
	
	jsr bhop_unmute_channels
	
@NoNewUnmutes:
	lda SfxChanMask
	sta PrevSfxChanMask
	
@ChanMaskChecked:
	; Is FT playing?
	lda MusicState
	cmp #PLAYING_FT
	bne @Done
	
@PlayingFt:
	; Update it for this frame
	lda #SWITCH_BANK_A
	sta BankCtrlReg
	lda CurFtBank
	sta BankReg	

	jsr bhop_play
	
@Done:
	; Must return very carefully: Use SwitchBank as a trampoline to return to the caller of UpdateSound, which may be in the sound bank for some mini-games
	lda #NAT_SOUND_BANK
	jmp SwitchBank
.endproc ; UpdateSoundPart3

.proc UpdateNoiseSfx
NumFrames := Temp0

	; Was the noise channel stopped via ApuStatus_4015?
	lda SilenceMusicAndSfx
	bne @CheckSfxFrames
	
@SilenceMusicAndSfx:
	; Yes
	sta ApuStatus_4015
	sta NoiseSfxFrames
	
	lda #HI_FREQ_NOT_SET
	sta SilenceMusicAndSfx
	
	beq @ClearVars
	
@CheckSfxFrames:
	; No. Are we even playing a SFX? Decrement the frame counter if relevant.
	lda NoiseSfxFrames
	beq @CheckForStart
	cmp #$ff
	beq @CheckForMute
	
	dec NoiseSfxFrames
	
@CheckForMute:
	; Mute the channel if volume is set to 0 or a value of 0 is written. 0 is not technically immediate silence, but it's sometimes uses as such by the game.
	lda NoiseCtrl1
	tax
	beq @MuteNoise ; 0
	
	eor #$10
	and #$1f
	bne @NoMute ; ---0 xxxx or ---1 xxxx (x > 0)
	
@MuteNoise:
	lda #$30
	sta NoiseVolume_400C
	
	lda #$0
	sta NoiseSfxFrames
	
	beq @ClearVars
	
@NoMute:
	stx NoiseVolume_400C
	
@CheckForStart:
	; Was a new SFX started?
	lda NoisePeriodHi
	cmp #HI_FREQ_NOT_SET
	beq @Done

	sta NoiseLength_400F

	; Does it play forever, or will the envelope or length counter cause it to stop?
	lda NoiseCtrl1
	and #$20
	beq @CheckLength
	
	lda #$ff
	bne @SaveLength
	
@CheckLength:
	; Check the length counter
	lda NoisePeriodHi
	lsr A
	lsr A
	lsr A
	tax
	
	lda @LenCtrFrames, X
	sta NumFrames
	
	; If it's using hardware envelope, check the envelope length
	lda NoiseCtrl1
	and #$10
	bne @UseLenCtr
	
	lda NoiseCtrl1
	and #$f
	tax
	lda @EnvFrames, X
	cmp NumFrames
	bcc @SaveLength
	
@UseLenCtr:
	lda NumFrames
	
@SaveLength:
	sta NoiseSfxFrames
	
@ClearVars:
	lda #HI_FREQ_NOT_SET
	sta NoisePeriodHi
	
@Done:
	rts
	
; Number of frames till silence for each envelope value
@EnvFrames:
	.repeat 16, i
	.byte 15 * (i + 1) / 4
	.endrepeat

; Number of frames till silence for each length counter value
@LenCtrFrames:
	.byte 5, 127, 10, 1, 20, 2, 40, 3, 80, 4
	.byte 30, 5, 7, 6, 13, 7
	.byte 6, 8, 12, 9, 24, 10, 48, 11
	.byte 96, 12, 36, 13, 8, 14, 16, 15
.endproc ; UpdateNoiseSfx

; Patches to redirect noise SFX register writes

patch_segment PATCH_SHIP_SFX, $26, $c117, $c13c
.scope
	bne @ShipSFX
	
@AirshipSFX:
	lda #$38
	sta NoiseCtrl1
	
	lda FrameCtr
	asl A
	jmp @PlaySFX
	
@ShipSFX:
	lda FrameCtr
	bpl @NotNegative
	
	eor #$ff
	
@NotNegative:
	lsr A
	lsr A
	lsr A
	lsr A
	ora #$30
	sta NoiseCtrl1
	
	lda #$a
	
@PlaySFX:
	sta NoisePeriod_400E
	lda #$0
	sta NoisePeriodHi
.endscope

patch_segment PATCH_STOP_SHIP_SFX, 3, $c184
	sta NoiseCtrl1
	
patch_segment PATCH_STOP_SHIP_SFX2, 3, $c1a0
	sta NoiseCtrl1
	
patch_segment PATCH_STOP_SHIP_SFX3, 3, $c645
	sta NoiseCtrl1

patch_segment PATCH_SILENCE_MUSIC_AND_SFX, 3, $c1ce
	sta SilenceMusicAndSfx
	
patch_segment PATCH_MAP_TILE_DAMAGE_SFX, $f, $c7e7, $c7f5
	lda #$f
	sta NoiseCtrl1
	lda #$d
	sta NoisePeriod_400E
	lda #$0
	sta NoisePeriodHi
	
patch_segment PATCH_DOOR_SFX, $f, $cf1e, $cf2c
	lda #$c
	sta NoiseCtrl1
	lda #$d
	sta NoisePeriod_400E
	lda #$30
	sta NoisePeriodHi
	
patch_segment PATCH_SHIP_STOP_SFX4, 3, $e1dd
	sta NoiseCtrl1
	
patch_segment PATCH_SHIP_SFX2, $f, $e215, $e223
	lda #$38
	sta NoiseCtrl1
	lda FrameCtr
	sta NoisePeriod_400E
	lda #$0
	sta NoisePeriodHi
	
patch_segment PATCH_SWITCH_BANK, $2b, $fe03, $fe2d
.proc SwitchBank ; $1c bytes
	; Compatibility with randomizer
	sta CurBank
	pha
	pla
	
	stx Temp0
	
	ldx #SWITCH_BANK_8
	stx BankCtrlReg
	asl A
	sta BankReg
	
	inx
	stx BankCtrlReg
	ora #$1
	sta BankReg
	
	ldx Temp0
	
	lda #$0 ; Per randomizer this must be 0 at return
	
	rts
.endproc ; SwitchBank

	.res $d

patch_segment PATCH_RESET_HDLR, $6e, $fe2e, $fe9b
; Relocate the reset handler to another bank to free up space
.proc ResetHdlr ; 16 bytes
	; Shut down interrupts
	sei
	
	ldx #$0
	stx PpuControl_2000
	
	stx IrqDisableReg
	
	; Setup stack so functions can be called
	dex
	txs
	
	lda #(<.bank(ResetHdlrCont) / 2)
	jsr SwitchBank
	
	jsr ResetHdlrCont
	
	; On with the show
	lda #$6
	jsr SwitchBank
	
	jmp $c000
.endproc ; ResetHdlr

	.res $53

.segment "RESET_HDLR_CONT"
.proc ResetHdlrCont
	; X is initially $ff
	
	inx ; X = 0
	
	stx $ff
	stx $fe
	
	lda #$6
	sta PpuMask_2001
	
	cld
	
	ldx #$2
	
@FrameLoop:
	bit PpuStatus_2002
	bpl @FrameLoop
	
	dex
	bne @FrameLoop
	
	; Fixed bank at $c000, vertical mirroring
	lda #MIRROR_VERTICAL
	sta MirrorReg
	
	lda #DISABLE_PRG_RAM_PROTECTION
	sta PrgRamProtectReg

	; Set up the CHR banks
	ldx #$5

@Loop:
	lda @ChrBankIdcs, X
	stx BankCtrlReg
	sta BankReg
	
	dex
	bpl @Loop
	
	stx $100

	inx
	stx Ctrl1_4016
	stx ApuStatus_4015
	stx DmcFreq_4010
	
	stx IsInitialized
	
	lda #$c0
	sta Ctrl2_FrameCtr_4017
	
	jsr $febe ; Is it possible to move febe to this bank to safe more space?
	
	rts
	
@ChrBankIdcs: .byte 0, 2, 4, 5, 6, 7
.endproc ; ResetHdlrCont

