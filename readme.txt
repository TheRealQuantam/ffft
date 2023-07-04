Final Fantasy FamiTracker Patch
v0.1

By Justin Olbrantz (Quantam)

The ffft patch adds FamiTracker Module playback support to Final Fantasy (US), both making it far easier to compose and import custom music for hacks and providing a more powerful sound engine. This engine is added on top of the original sound engine and the original tracks can be used as well.

Basic Features:
- Support for FamiTracker Modules as implemented by bhop (https://github.com/zeta0134/bhop commit df7fd4e)
	- Supports basic FT features including channel volume, instruments, volume/pitch/arpeggio/mode envelopes, true tempo, grooves, etc.
	- Supports effects 0 (arpeggio), 1/2 (pitch slide), 3 (portamento), 4 (vibrato), 7 (tremolo), A (volume slide), B (go to order), C (halt), D (go to row in next order), F (speed/tempo), G (note delay), P (fine pitch), Q/R (pitch slide to note), S (delayed cut), V (mode)
	- Supports all base (2A03) channels except DPCM
	- Does NOT support expansion chips, linear pitch mode, hi-pitch envelopes, or effects E (old-style volume), EE (toggle hardware envelope/length counter), E (length counter), H/I (hardware sweep), L (delayed release), M (delayed volume), S (set linear counter), T (delayed transpose)
- Expanded capacity
	- Upgrades ROM to MMC3
	- Increases PRG-ROM size to 512 KB, almost half of which is available for music
	- Increases maximum number of tracks from 24 to 63
- Additional features
	- Supports unique tracks for all battles
	- "Fanfares" (music used as sound effects) do not cause the background music to restart from the beginning if the two use different music engines
	- MMC3 provides a scanline interrupt that is available for derivative hacks

HOW IT WORKS

The fundamental problem a conversion such as ffft must solve is not what might be assumed; bhop handles the FT playback, so that isn't a major concern. The real trick is synchronizing access to the sound hardware so that, between FT music, native music, and native sound effects, exactly one (and the correct one) of those is using any sound channel at a given time. This is made considerably harder by the fact that FF is relatively unusual in lacking a global sound effect engine; while the battle system has a SFX engine, SFX outside battles are played ad-hoc, directly writing to the hardware from the functions where various things occur in the game. This requires a considerably different architecture (and considerably more duct tape) than other FT conversions.

To briefly summarize, ffft monitors a number of game variables, especially those relating to FF's own sharing of the square 2 channel between music engine and SFX, as well as writes to a number of hardware registers. From this it determines when tracks should be played and on what engine, as well as when SFX are playing so that FT playback can be silenced on those channels.

REQUIREMENTS

Final Fantasy (U).nes:
PRG-ROM CRC32 CEBD2A31 / MD5 24AE5EDF8375162F91A6846D3202E3D6
File CRC32 5C892F3B / MD5 D111FC7770E12F67474897AAAD834C0C

The ffft patch files are in xdelta3 format and require the xdelta3 tool from https://www.romhacking.net/utilities/928/ or http://xdelta.org/. After download the tool must be renamed to xdelta3.exe and put in the same directory as the patch files and ROM.

The makeftrom utility (https://github.com/TheRealQuantam/makeftrom) is used to import music. For most users it's best to simply download the executable form, which includes the Python environment and all the dependencies. Note that some of the ffft files (in particular the .ftcfg files) are required by makeftrom to produce ffft ROMs.

PATCHING

After assembling the ROM, xdelta3.exe, and the ffft files into a directory, simply drag and drop the ROM file onto patch.bat. This will produce ffft.nes and ffftdemo.nes. ffft.nes is the patched version of FF that will be used as the base of further hacking. ffftdemo.nes is a demo that replaces several tracks with assorted FT tracks.

COMPATIBILITY

Care must be taken when combining ffft with other, non-music changes.

The MMC3 mapper, like most other mappers, requires the common banks (addresses $c000-ffff) be the final banks in the ROM. As such, in addition to any specific changes, the ENTIRE 3c010-4000f file region (MMC1 bank f) has been relocated to 7c010-8000f (MMC3 banks 3e/3f). As such ANY other hack that modifies the 3c010-4000f region will not work when patched, as the patch is modifying the wrong location. However, many of these hacks should work correctly when manually applied to the proper new locations.

ffft makes the following RAM usage changes:

ffft uses the following ROM ranges that were previously free:

As well, ffft frees up the following ranges:

Finally, ffft substantially modifies the following ranges in a way that may break compatibility:

PRODUCING DERIVATIVE HACKS

ffft is intended to be incorporated into other, larger hacks. For exact details see license.txt, but in general all that's required is a credit in your hack's readme or wherever else the hack's credits are displayed (e.g. if your hack modifies the game's credits sequence to include the hack's creators, include an ffft credit as well). If you modify the ffft code, modifications to the ffft code (but NOT any of your code unrelated to ffft) must be released under the MPL or a compatible license (see license.txt for details).

Importing tracks is done through the aforementioned makeftrom utility, and is documented in the makeftrom manual. What is necessary is the FF-specific list of track names that can be assigned using makeftrom (track numbers are listed only for the benefit of hackers already familiar with the tracks, and only the names are needed to use makeftrom):
0: Prelude
1: OpeningTheme
2: EndTheme
3: MainTheme
4: SailingShip *
5: Airship *
6: Town
7: ConeriaCastl
8: GurguVolcano
9: MatoyasCave
a: Dungeon
b: TempleOfFiends
c: FloatingCastle
d: SeaShrine
e: Shop
f: Battle
10: MenuScreen
11: GameOver
12: Victory
13: Tent **
14: Lineup **
15: SaveJingle **
16: UsePotion **
17: TreasureChest **

Additionally, tracks $18-$3e are not used in FF but can be used for any purpose that may be added by a derivative hack.

* FF plays a persistent SFX for the entirety of ship sequences on the noise channel. As such it is highly recommended that replacement tracks for these uses not use the noise channel.

** These are what ffft calls "fanfares": short, SFX-like music tracks that interrupt the background momentarily; additionally, while not a true fanfare, Lineup is included in this set because it is a useful ability. When played properly (see Under the Hood), ffft supports pausing the background music while a fanfare is played and resuming it afterward rather than restarting it. This mechanism requires that the fanfare be a native FF track and the background music be an FT track to take advantage of the two engines using different memory regions; if both are FT tracks or native tracks, the background music will be restarted as in the original game.

ffft supports different music for each battle that can be specified with the (now poorly named) boss_track_map feature of makeftrom. The Battle track is in fact the default battle each encounter initially points to, which allows large numbers of encounters to be changed simply by changing the Battle track; but the boss_track_map feature overrides this for specific battles. Note that the boss_track_map feature is only used when FF itself requests track $f; assigning the Battle track to other uses in the track map (e.g. making a zone use the track for background music via track_map) will NOT cause boss_track_map translation.

Most of the encounter names are uninspired, e.g. Formation1A1 (read: formation 1a-1, which is why it immediately follows formation 19-1 and precedes formation 1b-1). These require knowledge of the different encounters and their numbers (see e.g. https://gamefaqs.gamespot.com/nes/522595-final-fantasy/faqs/59202). The full list:
Formation001
Formation011
Formation021
Formation031
Formation041
Formation051
Formation061
Formation071
Formation081
Formation091
Formation0A1
Formation0B1
Formation0C1
Formation0D1
Formation0E1
Formation0F1
Formation101
Formation111
Formation121
Formation131
Formation141
Formation151
Formation161
Formation171
Formation181
Formation191
Formation1A1
Formation1B1
Formation1C1
Formation1D1
Formation1E1
Formation1F1
Formation201
Formation211
Formation221
Formation231
Formation241
Formation251
Formation261
Formation271
Formation281
Formation291
Formation2A1
Formation2B1
Formation2C1
Formation2D1
Formation2E1
Formation2F1
Formation301
Formation311
Formation321
Formation331
Formation341
Formation351
Formation361
Formation371
Formation381
Formation391
Formation3A1
Formation3B1
Formation3C1
Formation3D1
Formation3E1
Formation3F1
Formation401
Formation411
Formation421
Formation431
Formation441
Formation451
Formation461
Formation471
Formation481
Formation491
Formation4A1
Formation4B1
Formation4C1
Formation4D1
Formation4E1
Formation4F1
Formation501
Formation511
Formation521
Formation531
Formation541
Formation551
Formation561
Formation571
Formation581
Formation591
Formation5A1
Formation5B1
Formation5C1
Formation5D1
Formation5E1
Formation5F1
Formation601
Formation611
Formation621
Formation631
Formation641
Formation651
Formation661
Formation671
Formation681
Formation691
Formation6A1
Formation6B1
Formation6C1
Formation6D1
Formation6E1
Formation6F1
Formation701
Formation711
Formation721
LichRefight
KaryRefight
KrakenRefight
TiamatRefight
Tiamat
Kraken
Kary
Lich
Chaos
Vampire
Astos
Bikke
Garland
Formation002
Formation012
Formation022
Formation032
Formation042
Formation052
Formation062
Formation072
Formation082
Formation092
Formation0A2
Formation0B2
Formation0C2
Formation0D2
Formation0E2
Formation0F2
Formation102
Formation112
Formation122
Formation132
Formation142
Formation152
Formation162
Formation172
Formation182
Formation192
Formation1A2
Formation1B2
Formation1C2
Formation1D2
Formation1E2
Formation1F2
Formation202
Formation212
Formation222
Formation232
Formation242
Formation252
Formation262
Formation272
Formation282
Formation292
Formation2A2
Formation2B2
Formation2C2
Formation2D2
Formation2E2
Formation2F2
Formation302
Formation312
Formation322
Formation332
Formation342
Formation352
Formation362
Formation372
Formation382
Formation392
Formation3A2
Formation3B2
Formation3C2
Formation3D2
Formation3E2
Formation3F2
Formation402
Formation412
Formation422
Formation432
Formation442
Formation452
Formation462
Formation472
Formation482
Formation492
Formation4A2
Formation4B2
Formation4C2
Formation4D2
Formation4E2
Formation4F2
Formation502
Formation512
Formation522
Formation532
Formation542
Formation552
Formation562
Formation572
Formation582
Formation592
Formation5A2
Formation5B2
Formation5C2
Formation5D2
Formation5E2
Formation5F2
Formation602
Formation612
Formation622
Formation632
Formation642
Formation652
Formation662
Formation672
Formation682
Formation692
Formation6A2
Formation6B2
Formation6C2
Formation6D2
Formation6E2
Formation6F2
Formation702
Formation712
Formation722
Formation732
Formation742
Formation752
Formation762
Formation772
Formation782
Formation792
Formation7A2
Formation7B2
Formation7C2
Formation7D2
Formation7E2
Formation7F2

Under the Hood

The ad-hoc nature of FF SFX necessarily exposes much more of the inner workings of ffft than previous FT conversions, and there are several mechanisms derivative hack-makers must be aware of.

1. Playing non-fanfare music tracks is no different than the base game.

This is accomplished via the music_track variable at $4b. When writing to it, it has one of the following values:
	80: Stop playing the current track. This will also clear the previously playing  track's state and prevent the track from being resumed after a fanfare.
	01nn nnnn: Play music track n - 1 (so $41-$7f). If the track number is the same as the previously playing track number and the previously playing track's state was saved before playing a fanfare, this will resume the track rather than restarting it.

When read (assuming a command wasn't previously written in the same frame), this variable has one of the following values (several other possibilities also exist, but they are transient states and should be ignored):
	81: Music playback has stopped, either because the track ended or a stop command was issued.
	00: Music is playing
	
2. ffft introduces a shadow copy of this variable at $f3 (internally called FanfareMusicState).

This variable responds only to play music commands (01nn nnnn), and plays the specified track as a fanfare, if possible preserving the state of the previously playing music.

To summarize, in order to play a fanfare and then resume the previous track the sequence of events is as follows:
	1. The background FT track x is started via music_state
	2. The fanfare native track is started via FanfareMusicState
	3. (Optionally) the fanfare is stopped with a stop command via music_state
	4. A start track command for track x is issued via music_state
	
3. Modifications to SFX played through the battle SFX system should work fine without any special consideration, as ffft watches the variables used by this system

4. Out of combat SFX that play over music must inform the music engine of their state

In the original game, the music engine uses only the square and triangle channels. SFX are allowed to use the square 2 and noise channels. For SFX that only play when music is stopped, e.g. screen transitions, no synchronization is done between SFX and music. However, SFX that play over music communicate with the music engine via sq2_sfx ($7e) which contains the number of frames the square 2 channel will be in use by SFX. The same must be done for any SFX added or modified in derivative hacks.

The noise channel is more troublesome, as FF allocates it exclusively to SFX and there is NO synchronization mechanism with the music engine. Thus ffft had to create one. This is accomplished by introducing shadows of 2 APU noise registers: NoiseCtrl1 ($6db3, which shadows $400c) and NoisePeriodHi ($6db4, which shadows $400f). All writes to these registers for out of battle noise SFX that can overlap music must be redirected to these shadow variables. For sounds that continue indefinitely (they do not terminate via the length counter) they must be manually stopped either by writing ---1 0000 (e.g. $30) to NoiseCtrl1 or writing 0 to SilenceMusicAndSfx ($6db5, which shadows $4015 but ONLY responds to writing 0).

5. ffft currently uses a kludge that tricks makeftrom into thinking it's a Capcom 2 game. This requires a c2_files section in the project file that MUST be empty, e.g. the following line:

c2_files: [],

BUGS

- Resuming a native background track from an FT fanfare doesn't really work at this time. It might be fixed later.

- Bugs or incomplete features may exist in bhop. The most noticeable known issue is that bhop does not currently implement pitch effects (e.g. pitch slide) on the noise channel. This can be worked around by using pitch or arpeggio envelopes instead.

CREDITS

Research, reverse-engineering, and programming: Justin Olbrantz (Quantam)

Thanks to the NesDev and FF Randomizer communities for the occasional piece of information or advice.
