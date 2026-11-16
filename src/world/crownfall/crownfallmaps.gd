# crownfallmaps.gd - CROWNFALL's world (0.162.0): the seven kingdoms, every map
# as rows of letters, and the story. Data only; crownfallrun.gd plays it.
#
# THE STORY (the owner: "because they are elemental bricks I was thinking
# damage plagued the lands when the mysterious portals opened the monsters
# built kingdoms and castles", and of the two ideas put together, "sounds
# good"): when the portals opened, each land's element broke and spread. The
# monsters quarried the plagued ground into stone and built seven kingdoms of
# it, and each kingdom's ruler wears one of the Crowned Beholder's seven
# crowns. Every brick broken frees the ground it was cut from; every citadel
# taken takes a crown.
#
# A MAP IS ROWS OF LETTERS, COLS (32) wide and at most ROWS_MOST (18) deep -
# a brick a letter, so a new one costs minutes; the owner: "make the maps
# bigger", "dense maps with designs in the bricks" - most are pictures. The
# letters:
#   .  nothing
#   l a w i e f d   a brick of a land: light, wind (air), water, ice, earth,
#                   fire, dark - one hit (earth two), breaking its land's way
#   S  stone - three hits, cracking
#   I  iron - never breaks; the shape of the place
#   M  mirror - never breaks, and bends the ball as it throws it back (light)
#   T  TNT - goes off, and sets off what is near
#   ?  a bonus brick - always drops a bonus
#   B  blight - one hit, but it grows back into the empty cells beside it
#   H  the core - every H together is one brick, six hits
#   R  a boss's hall - empty; the map's boss walks it
# AND THE NEW ONES (the owner: "add more variety in bricks ... we can mix
# elements in bricks if needed for more effects maybe even changing brick
# types has to be hard"):
#   1-7  a mixed brick - two lands, its reaction set off when it breaks:
#        1 steam (fire, ice), 2 firestorm (fire, wind), 3 glacier (water,
#        ice), 4 storm (water, wind), 5 magma (earth, fire), 6 blizzard (ice,
#        wind), 7 eclipse (light, dark)
#   C  crystal - splits the ball that breaks it
#   U  bumper - never breaks; kicks the ball off its middle, faster
#   O  portal - never breaks; in one, out of its pair (pairs in reading order;
#      one left over is a wall)
#   K  key, L lock - a lock never breaks until every key is broken; then
#      every lock shatters (locks never count to clear the map)
#   G  gold - two hits, a shower of score
#   N  rune - breaks only while it is lit, a while in every few seconds
#   Z  shell - the blow that would break it hardens it into stone instead
#   X  prism - turns through every land; breaks as the one it shows
#   Y  mimic - becomes what breaks beside it
#   p  plague-stone - two hits; the blight turns land bricks beside it into it
#   <  drifter - light bricks that slide along their row into the room beside
#      them
# Every map's rows are COLS letters - the suite checks. A name longer than
# the right panel's room (about 11 letters) gives a `short` one.
#
# THE KINGDOMS go from gentlest to deepest, as the Big Field's wings do. Each
# will have MAPS_A_KINGDOM (25) maps (the owner: "the last brick breaker game
# i played had like 200 maps"), every BOSS_EVERY-th (5th) a boss's
# (`boss`, crownfallboss.gd: its kind, the monster it is drawn from, its
# minion and name) - the 25th its citadel, the ruler wearing the crown. Only
# kingdoms `made` are played; the rest show on the kingdom map as coming, and
# a made kingdom's maps not drawn yet show as dim slots.
extends RefCounted

const COLS := 32
const ROWS_MOST := 18
# A BIG MAP (the owner: "we can even make the map bigger in some"): BIG_COLS
# wide and up to BIG_ROWS_MOST deep, its bricks smaller to fit the arena.
const BIG_COLS := 48
const BIG_ROWS_MOST := 28
const MAPS_A_KINGDOM := 25
const BOSS_EVERY := 5
const STRETCHES := 5
# Each stretch's boss, by kind (crownfallboss.gd KINDS), named where a map is
# not built yet (the run's ladder of five).
const BOSS_SLOTS := ["The Slime King", "The Sprite", "The Sniper", "The Bush Mage", "The Ruler"]

const KINGDOMS := [
	{"id": "light", "name": "The Kingdom of Light", "land": "light", "made": true,
		"trick": "Mirrors bend the ball - aim off them."},
	{"id": "wind", "name": "The Kingdom of Wind", "land": "wind", "made": false,
		"trick": "Bricks that drift, and gusts that curve the ball."},
	{"id": "water", "name": "The Kingdom of Water", "land": "water", "made": false,
		"trick": "A tide that rebuilds what you leave too long."},
	{"id": "ice", "name": "The Kingdom of Ice", "land": "ice", "made": false,
		"trick": "Frost that takes two hits, and icicles that fall."},
	{"id": "earth", "name": "The Kingdom of Earth", "land": "earth", "made": false,
		"trick": "Break a pillar's foot and all above it falls."},
	{"id": "fire", "name": "The Kingdom of Fire", "land": "fire", "made": false,
		"trick": "TNT that chains, and fire that spreads."},
	{"id": "dark", "name": "The Kingdom of Dark", "land": "dark", "made": false,
		"trick": "Bricks unseen until your light finds them."},
]

const MAPS := [
	{"kingdom": "light", "name": "Gilded Gate", "line": "The first wall: a gate between two towers, its bars iron.",
		"rows": [
			"S.S.S......................S.S.S",
			"SllllS....................SllllS",
			"SllllS....................SllllS",
			"SlwwlS.l.l.l.l.ll.l.l.l.l.SlwwlS",
			"SlwwlSSSSSSSSSSSSSSSSSSSSSSlwwlS",
			"SDlllSllallllDllllDllllallSlllDS",
			"S?lllSllallll?llll?llllallSlll?S",
			"SllllSllallllllllllllllallSllllS",
			"SlwwlSllallSSSSSSSSSSllallSlwwlS",
			"SlwwlSllalSSllllllllSSlallSlwwlS",
			"SllllSllalS.I..II..I.SlallSllllS",
			"Slll?SllalS.I..II..I.SlallS?lllS",
			"SllllSllllS.I..II..I.SllllSllllS",
			"SlwwlSllllS.I..II..I.SllllSlwwlS",
			"SlwwlSllllS.I..II..I.SllllSlwwlS",
			"SllllSllllS.I..II..I.SllllSllllS",
			"eeeeeeeeeeS.I..II..I.Seeeeeeeeee",
			"eeeeeeeeeeS.I..II..I.Seeeeeeeeee",
		]},
	{"kingdom": "light", "name": "Sundial", "line": "A sun of light, its rays of fire - they burn each other. Mind the blight.",
		"rows": [
			".ffffffaaaaaaaaffaaaaaaaaffffff.",
			"afffffffaaaaaaaeeaaaaaaafffffffa",
			"aaaffffffaaaaaeDDeaaaaaffffffaaa",
			"aaaaafffffaaael??leaaafffffaaaaa",
			"aaaaaaaffffaeelllleeaffffaaaaaaa",
			"aaaaaaaaafffelllMllefffaaaaaaaaa",
			"fffaaaaaaaafellMlllefaaaaaaaafff",
			"ffffffffaaaaeDMlllDeaaaaffffffff",
			"fffffffffffae?lMMl?eafffffffffff",
			"fffffffffffae?llll?eafffffffffff",
			"ffffffffaaaaelllllleaaaaffffffff",
			"fffaaaaaaaafellllllefaaaaaaaafff",
			"aaaaaaaaafffellllllefffaaaaaaaaa",
			"aaaaaaaffffaeelllleeaffffaaaaaaa",
			"aaaaafffffaaael??leaaafffffaaaaa",
			"aaaffffffaaaaaeeeeaaaaaffffffaaa",
			"afffffffaaaBBBBeeBBBBaaafffffffa",
			".ffffffaaBBBBBBffBBBBBBaaffffff.",
		]},
	{"kingdom": "light", "name": "Cathedral", "line": "A rose window of every land round a core of plague. Blight in the crypt.",
		"rows": [
			"............SfffdddS............",
			"...........SffffddddS...........",
			".........SSSffffddddSSS.........",
			".........SlSffffddddSlS.........",
			".......SSSlaafffdddlllSSS.......",
			".......SlSlaaaDSSDllllSlS.......",
			".....SSSlSlaaaaHHlllllSlSSS.....",
			".eee.SlSlSSaaaaHHlllSSSlSlS.eee.",
			".eee.SlSlSlaaaDllDllSlSlSlS.eee.",
			"eeeeMSlSlSlaaaiSSwllSlSlSlSMeeee",
			"eeee.SlSlSlaaiiiwwwlSlSlSlS.eeee",
			"eeee.SlSlSlSiiiiwwwwSlSlSlS.eeee",
			"eeee.Sl?wSwwiiiiwwwwwwS?wlS.eeee",
			"eeee.SlwwSwwiiiiwwwwwwSwwlS.eeee",
			"eeee.SlwwSwwSiiiwwwSwwSwwlS.eeee",
			"eeee.SlwwSwwlSiiwwSlwwSwwlS.eeee",
			"eeee.SlwwSwwllSSSSllwwSwwlS.eeee",
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
		]},
	{"kingdom": "light", "name": "Lantern Spire", "short": "The Spire", "line": "Up the spire to the lantern. Iron rails on either side.",
		"rows": [
			"...............SS...............",
			"..............?DD?..............",
			".............M????M.............",
			"..............????..............",
			".a..........MS????SM..........a.",
			"aaa..........SSSSSS..........aaa",
			"aaa.........SSSSSSSS.........aaa",
			"aaa.........SllllllS.........aaa",
			"aaa.II.II.IISllllllSII.II.II.aaa",
			"aaa...ee...fSlwwwwlSf...ee...aaa",
			"aaa..eeee..TSlwwwwlST..eeee..aaa",
			"aaa.eeeeee.fSllllllSf.eeeeee.aaa",
			"aaaSllllllSISllllllSISllllllSaaa",
			"aaaSllllDlS.SlwwwwlS.SlDllllSaaa",
			"aaaSlwwl?lS.SlwwwwlS.Sl?lwwlSaaa",
			"aaaSlwwlllS.SllllllS.SlllwwlSaaa",
			"aaaSllllllS.SllllllS.SllllllSaaa",
			"BBBSllllllS.SSSSSSSS.SllllllSBBB",
		]},
	{"kingdom": "light", "name": "The Slime King's Hall", "short": "The King's Hall", "line": "Strike him and he splits - his young plant the blight.",
		"boss": {"kind": "slimeking", "enemy": "lightslimelarge", "minion": "lightslime", "name": "The Slime King"},
		"rows": [
			"........SSRRRRRRRRRRRRSS........",
			"........SSRRRRRRRRRRRRSS........",
			"........SSRRRRRRRRRRRRSS........",
			"........SSRRRRRRRRRRRRSS........",
			"........SDSSIIIIIIIISSDS........",
			"........SSSSSSSSSSSSSSSS........",
			".........lililddddlilil.........",
			"........ilildddlldddlili........",
			"........ilildllDDlldllli........",
			"........illdlll??llldlli........",
			".......llldlllllllllldlll.......",
			".......llldlllllllllldlll.......",
			".......lllllllaaaalllllll.......",
			"......llldlllallllallldlll......",
			"......llldlllllllllllldlll......",
			".B.B..llldllallllllalldlll..B.B.",
			"eeeee.llllllallllllallllll.eeeee",
			"eeeee.llllllllllllllllllll.eeeee",
		]},
	{"kingdom": "light", "name": "The Crystal Orchard", "short": "The Orchard", "line": "Crystals split the ball. Prism fruit turn through every land.",
		"rows": [
			".............aD??DC.............",
			".....Ca......aCaaCa......aC.....",
			"....CaaC....aCaaCaaC....aCaa....",
			"...CaaCaa...CaaCaaCa...aCaaCa...",
			"...aaCaaC...aaDaaDaa...CaaCaa...",
			"...aCaaCa...aCXaCaaC...aaCaaC...",
			"...CXaCaa...CaaCaaCa...aXaaCa...",
			"...aaCaaC...aaCaaXaa...CaaCaa...",
			"...aCaaXa...aCaaCaaC...aaCaXC...",
			"...CaaCaa....aaCaaC....aCaaCa...",
			"....aCaa.....aCaaCa.....aaCa....",
			".....aa.......aaCa.......Ca.....",
			".....ee........Ca........ee.....",
			".....ee...CC...ee...CC...ee.....",
			".....ee...CC...ee...CC...ee.....",
			"eeeeeeeeeeCCeeeeeeeeCCeeeeeeeeee",
			"eeBeeeeeBeeeeBeeeeBeeeeBeeeeeBee",
			"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
		]},
	{"kingdom": "light", "name": "Bumper Court", "short": "The Court", "line": "Bumpers kick the ball faster. Mix the stripes - fire, ice, water, wind.",
		"rows": [
			"ffiiwwaaffiiwwD??Dwwiiffaawwiiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"ffiiwwaUUfiiwwaaaawwiifUUawwiiff",
			"ffiiwwaUUfiiwwaaaawwiifUUawwiiff",
			"ffiiwwaaffiiwwaUUawwiiffaawwiiff",
			"ffiiwwaaffiiwwaUUawwiiffaawwiiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"ffii........................iiff",
			"ffii........<<<<<<<<........iiff",
			"ffii........................iiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"ffii........................iiff",
			"ffii........<<<<<<<<........iiff",
			"ffii........................iiff",
			"ffiiwwaaffiiwwaaaawwiiffaawwiiff",
			"IfiiIwaaIfiiIwaaaawIiifIaawIiifI",
		]},
	{"kingdom": "light", "name": "The Mixing Well", "short": "The Well", "line": "Every brick in the well is two lands. Runes only break while lit.",
		"rows": [
			"ifififilllDNllllllllNDlllwawawaw",
			"fifififlllNNllll7lllNNlllawawawa",
			"ifififilllNllllllllllNlllwawawaw",
			"fifififlllNllll7lllllNlllawawawa",
			"ifififillDlll4llllllllDllwawawaw",
			"fifififllNlllllll7llllNllawawawa",
			"ifififillNllll4lllllllNllwawawaw",
			"fifififllNllllllll7lllNllawawawa",
			"ifififillNllllllllllllNllwawawaw",
			"fififif..SSSSSSSSSSSSSS..awawawa",
			"ifififi...S1111111111S...wawawaw",
			"fififif...S2222222222S...awawawa",
			"ifififi...S3333333333S...wawawaw",
			"fififif...S4444444444S...awawawa",
			"ifififi....S55555555S....wawawaw",
			"fififif.....S666666S.....awawawa",
			"ifififi......S7777S......wawawaw",
			"fififif....IIffffffII....awawawa",
		]},
	{"kingdom": "light", "name": "Keys of the Keep", "short": "The Keep", "line": "Four keys open the vault. Shells harden; mimics copy; portals go round.",
		"rows": [
			"................................",
			"................................",
			".....SZSS.......................",
			"....SZSSSZ......................",
			"....ZSSSZS......................",
			"...ZSS..SSS.....................",
			"...SS.ll.SZ.....?.......?.......",
			"...SDKlDKZSSSSSSSSSSSSSSSSSSSSSS",
			"...SZllllSSlllYlllYlllYlllYlllOl",
			"...ZSDllDSSlOlllllllllllllllllll",
			"...SSKllKSZSSSSSSSSSSSSSSSSSSSSS",
			"...SS.ll.ZS.........SLLS..SLLS..",
			"...SZS..ZSS.........SDGS..SGGS..",
			"....SSSZSS..........SGGS..SDGS..",
			"....SSZSSS..........SSSS..SGGS..",
			".....ZSSS.................SGGS..",
			"..........................SSSS..",
		]},
	{"kingdom": "light", "name": "The Sprite's Spire", "short": "Sprite's Spire", "line": "The Sprite darts and blinks about its hall. Portals on the walls.",
		"boss": {"kind": "sprite", "enemy": "lightsprite", "name": "The Sprite"},
		"rows": [
			"laaaaaaRRRRXDRRaaRRDXRRRRaaaaaal",
			"llaaaaaaRRRRXRRaaRRXRRRRaaaaaall",
			"lllaaaaaaRRRXXRaaRXXRRRaaaaaalll",
			"lllSSaaaaaRRXXRaaRXXRRaaaaaSSlll",
			"lllSSSDaaaIIIXIaaIXIIIaaaDSSSlll",
			"lllllllaaaallXllllXllaaaalllllll",
			"OllllllllaaallXllXllaaallllllllO",
			"llllllllllaaalXSSXlaaallllllllll",
			"lDlllllllllaalSCCSlaalllllllllDl",
			"X?XXlllllllllaCCCCalllllllllXX?X",
			"XXXXXXXXXllllSCCCCSllllXXXXXXXXX",
			"XXXXXXXXXXXXXSCCCCSXXXXXXXXXXXXX",
			"OXXXXXXXXXXXXSCCCCSXXXXXXXXXXXXO",
			"XXXXXXXXXllllSCCCCSllllXXXXXXXXX",
			"XXXXlllllllllaCCCCalllllllllXXXX",
			"lllllllllllaalSCCSlaalllllllllll",
			"llllllllllaaalXSSXlaaallllllllll",
			"lllllllllaaallXllXllaaalllllllll",
		]},
	{"kingdom": "light", "name": "Runes of Dawn", "short": "The Runes", "line": "A circle of runes - strike them while they burn.",
		"rows": [
			"................................",
			"................................",
			".........SSSSSS..SSSSSS.........",
			".........SS..SSllSS..SS.........",
			".........SD.lSS..SSl.DS.........",
			".........SNllSN..NSllNS.........",
			".SSSSSS..SSl.SS..SS.lSS..SSSSSS.",
			".SS..SS..SS..SSaaSS..SS..SS..SS.",
			".SS..SS..NS..NS..SN..SN..SS..SS.",
			".SN..SN..SS.aSS..SSa.SS..NS..NS.",
			".SS..SS..SSa.SS..SS.aSS..SS..SS.",
			".SS..SS.lSNa.SDX?DS.aNSl.SS..SS.",
			".NS..NS.lSS..SSSSSS..SSl.SN..SN.",
			".SS..SS.lSS..SSNNSS..SSl.SS..SS.",
			".SS..SS.lNS..NSSSSN..SNl.SS..SS.",
			".SS..SS.lSS..SSSSSS..SSl.SS..SS.",
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		]},
	{"kingdom": "light", "name": "Shellback Bridge", "short": "The Bridge", "line": "A great shellback crosses the river. Its shell hardens.",
		"rows": [
			"................................",
			"...............??...............",
			"..............dDDd..............",
			"..........dddeeeeeeddd..........",
			".........deeZeeeZeeeZed.........",
			".......ddeDeeeeeeeeeeDedd.......",
			".......deeZeeeZeeeZeeeZed.......",
			"......ddeeeeeeeeeeeeeeeedd......",
			"......ddZeeeZeeeZeeeZeeedd.aa...",
			".......deeeeeeeeeeeeeeeed..ad...",
			".......ddeZeeeZeeeZeeeZdd..aa...",
			".....e...deeeeeeeeeeeed....aa...",
			"....e...eedddeeeZeeddee.........",
			"........ee....dddd...ee.........",
			"wwwwwwwweewwwwwwwwwwweewwwwwwwww",
			"w.wwww.weew.wwww.wwwweewww.wwww.",
			"wwwwwwpwwwwwwwwwwpwwwwwwwwpwwwww",
			"www.wwww.wwww.wwww.wwww.wwww.www",
		]},
	{"kingdom": "light", "name": "The Prism Window", "short": "The Window", "line": "Glass of every land, prisms at the joins, a core behind runes.",
		"rows": [
			"SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS",
			"SlllaaSawwwwSiiieeSeffffSdddllSlaaaaSwwwiiSieeee",
			"SlllaaSawwwwSiiieeSeffSSSSddllSlaaaaSwwwiiSieeee",
			"SiiXeeSefXffSddXllSlaSSllSSXiiSieXeeSffXddSdlXll",
			"SiiieeSeffffSdddllSlSwwwaaaSiiSieeeeSfffddSdllll",
			"SiiieeSeffffSdddllSSwwwwaaaaSiSieeeeSfffddSdllll",
			"SdddllSlaaaaSwwwiiSSlwwwaaalSdSdllllSaaawwSwiiii",
			"SSSSSSSSSSSSSSSSSSSflwwwaaaliSSSSSSSSSSSSSSSSSSS",
			"SdddllSlaaaaSwwwiiSflwwwaaaliSSdllllSaaawwSwiiii",
			"SwwwiiSieeeeSfffddSfflwwaaliiSSwiiiiSeeeffSfdddd",
			"SwwXiiSieXeeSffXddffffwNNaiiiiSwiXiiSeeXffSfdXdd",
			"SwwwiiSieeeeSfffddffffNNNNiiiiSwiiiiSeeeffSfdddd",
			"SfffddSdllllSaaawSffffD..DiiiiSfddddSlllaaSawwww",
			"SfffddSdllllSaaawSlllf.HH.illlSfddddSlllaaSawwww",
			"SSSSSSSSSSSSSSSSSSllli.HH.flllSSSSSSSSSSSSSSSSSS",
			"SaaawwSwiiiiSeeefSiiiiD..DffffSawwwwSiiieeSeffff",
			"SaaawwSwiiiiSeeeffiiiiNNNNffffSawwwwSiiieeSeffff",
			"SaaXwwSwiXiiSeeXffiiiiaNNwffffSawXwwSiiXeeSefXff",
			"SeeeffSfddddSlllaaSiilaawwlffSSeffffSdddllSlaaaa",
			"SeeeffSfddddSlllaaSilaaawwwlfSSeffffSdddllSlaaaa",
			"SeeeffSfddddSlllaaSilaaawwwlfSSeffffSdddllSlaaaa",
			"SSSSSSSSSSSSSSSSSSSSlaaawwwlSSSSSSSSSSSSSSSSSSSS",
			"SlllaaSawwwwSiiieeSSaaaawwwwSlSlaaaaSwwwiiSieeee",
			"SlllaaSawwwwSiiieeSeSaaawwwSllSlaaaaSwwwiiSieeee",
			"SiiXeeSefXffSddXllSlaSSllSSXiiSieXeeSffXddSdlXll",
			"SiiieeSeffffSdddllSlaaSSSSwwiiSieeeeSfffddSdllll",
			"SiiieeSeffffSdddllSlaaaaSwwwiiSieeeeSfffddSdllll",
			"SdddllSlaaaaSwwwiiSieeeeSfffddSdllllSaaawwSwiiii",
		]},
	{"kingdom": "light", "name": "Mimic Market", "short": "The Market", "line": "Not every ware is what it seems.",
		"rows": [
			"................................",
			"..SSSS....SSSS....SSSS....SSSS..",
			".flflflDSwlwlwlDDflflflSDwlwlwl.",
			".flflfl?lwlwlwl?lflflfl?lwlwlwl.",
			".flflfl..wlwlwl..flflfl..wlwlwl.",
			".S....S..S....S..S....S..S....S.",
			".S....S..S....S..S....S..S....S.",
			".S....S..S....S..S....S..S....S.",
			".SYGYCS..SCYGYS..SYCYGS..SGYCYS.",
			".SeeeeS..SeeeeS..SeeeeS..SeeeeS.",
			".SeeeeS..SeeeeS..SeeeeS..SeeeeS.",
			".eeeeee..eeeeee..eeeeee..eeeeee.",
			".eeeeee..eeeeee..eeeeee..eeeeee.",
			"................................",
			"................................",
			"SSSS.SSSS.SSSS.SSSS.SSSS.SSSS.SS",
			"l.llll.llll.llll.llll.llll.llll.",
		]},
	{"kingdom": "light", "name": "The Watchtower", "short": "Watchtower", "line": "The Sniper fires down a column - see the line, get out of it.",
		"boss": {"kind": "sniper", "enemy": "lightbushsniper", "name": "The Sniper"},
		"rows": [
			".........SSRRRRRRRRRRSS.........",
			".........SSRRRRRRRRRRSS.........",
			".........SSRRRRRRRRRRSS.........",
			".........SSRRRRRRRRRRSS.........",
			".........SDSSIIIIIISSDS.........",
			".........SlDllllllllDlS.........",
			"..<<<....SlNlNlNlNlNllS....<<<..",
			".........MllllllllllllM.........",
			".........SllllllllllllS.........",
			".........SSSSSSSSSSSSSS.........",
			"..<<<....SllllllllllllS....<<<..",
			".........MllllllllllllM.........",
			".........SllllllllllllS.........",
			".........SSSSSSSSSSSSSS.........",
			"..<<<....SllllllllllllS....<<<..",
			".........MlllllDDlllllM.........",
			".........Slllll??lllllS.........",
			".........SllllllllllllS.........",
		]},
	{"kingdom": "light", "name": "Drifting Docks", "short": "The Docks", "line": "Boats drift the lanes. Gold on the quay.",
		"rows": [
			"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
			"....<<<<<<<<....................",
			".....<<<<<<.....................",
			"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
			"..................<<<<<<<<......",
			"...................<<<<<<.......",
			"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
			"....<<<<<<<<....................",
			".....<<<<<<.....................",
			"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
			"..................<<<<<<<<......",
			"...................<<<<<<.......",
			"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
			"....<<<<<<<<....................",
			".....<<<<<<.....................",
			"DweewDwwwweewwwwwwwwweewwwDwweeD",
			"GeeeeGeeeeGeeeeGeeeeGeeeeGeeeeGe",
			"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
		]},
	{"kingdom": "light", "name": "The Plague Garden", "short": "The Garden", "line": "Flowers in a garden gone to plague. It spreads.",
		"rows": [
			"paaaaaaaaaaaapaaaaaaaallllpaaaaaaaaaaaapaaaaaaaa",
			"aaaaffaffaaaaaaaaaaapallllaaaaaaapaaaaaddaddaapa",
			"apaafffffaaaaapaaaaaallllllpaaaaaaaaaaadddddaaaa",
			"aaaaffGffaaaaaaaaaaaall??llaaaaaaapaaaaddGddaaap",
			"aapffGGGffaaaaapaaaaall??llapaaaaaaaaaddGGGddaaa",
			"aaaffGDGffaaaaaaaaaaall??llaaaaaaaapaaddGDGddaaa",
			"aaaffGGGffaaaaaapaaaallllllaapaaaaaaaaddGGGddaaa",
			"aaaaffGffapaaaaaaaaaaallllaaaaaaaaaapaaddGddaaaa",
			"aaaafffffaaaaaaaapaaaallllaaaapaaaaaaaadddddaaaa",
			"aaaaffeffaapllallaaaaaaepaaaaaaffaffapaddeddaaaa",
			"aaaaapeaaaaalllllapaaaaeaaaaaaafffffaaaaaeaapaaa",
			"aaaaaaeaaaaall?llaaaaaaeapaaaaaffGffaapaaeaaaaaa",
			"aaaaaaeaaaall???llapaaaeaaaaaaffGGGffaaaaeaaapaa",
			"paaaaaeaaaall???llaaaaaeaapaaaffGDGffaapaeaaaaaa",
			"aaaaaaepaaall???llaapaaeaaaaaaffGGGffaaaaeaaaapa",
			"apaaaaeaaaaall?llaaaaaaeaaapaaaffGffaaaapeaaaaaa",
			"aaaaddeddaaalllllaaaapaeaaaaaaafffffaaallellaaap",
			"aapadddddaaallellaaaaaaeaaaapaaffeffaaalllllaaaa",
			"aaaaddGddpaaaaeaaaaaaapeaaaaaaaaaeapaaall?llaaaa",
			"aaaddGGGddaaaaeapaaaaaaeaaaaapaaaeaaaall???llaaa",
			"aaaddGDGddpaaaeaaaaaaaaeaaaaaaaaaeaapall???llaaa",
			"aaaddGGGddaaaaeaapaaaaaeaaaaaapaaeaaaall???llaaa",
			"aaaaddGddaapaaeaaaaaaaaepaaaaaaaaeaaapall?llaaaa",
			"aaaadddddaaaaaeaaapaaaaeaaaaaaapaeaaaaalllllpaaa",
			"aaaaddeddaaapaeaaaaaaaaeapaaaaaaaeaaaapllellaaaa",
			"aaaaaaeaaaaaaaeaaaapaaaeaaaaaaaapeaaaaaaaeaaapaa",
			"pppppppppppppppppppppppppppppppppppppppppppppppp",
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
		]},
	{"kingdom": "light", "name": "The Gold Vault", "short": "The Vault", "line": "Six keys hold the great door. Gold behind its bars.",
		"rows": [
			"...............ZS...............",
			".............SZSSZS.............",
			".............ZGGSGS.............",
			"..SDS.......ZGGGSDGS.......SDS..",
			"..SKSSSSSSS.SSDGSGSS.SSSSSSSKS..",
			"..SSS......SGSSGSSSGS......SSS..",
			"...........SDGSGSSGDS...........",
			"SDS........ZGGSLLSGGZ........SDS",
			"SKS........SSSSLLSSSS........SKS",
			"SlS........SGGGLLGGGS........SlS",
			"SSS........ZGDSLLSDGZ........SSS",
			"...........SGGSGSSGGS...........",
			"..SDS......SGSSGSSSGS......SDS..",
			"..SKSSSSSSS.SSDGSGSS.SSSSSSSKS..",
			"..SSS.......SGGGSDGZ.......SSS..",
			".............SGGSGZ.............",
			".............SZSSZS.............",
			"...............SZ...............",
		]},
	{"kingdom": "light", "name": "The Storm Bell", "short": "Storm Bell", "line": "A bell of storms. Ring it.",
		"rows": [
			"....SS....................SS....",
			"....SSSSSSSSSSSSSSSSSSSSSSSS....",
			"...wwS.........SS.........Sww...",
			"..wDww.......SaaaaS.......wwDw..",
			"..w?ww.......SaaaaS.......ww?w..",
			"..wwww......SaaaaaaS......wwww..",
			"..wwww......S444444S......wwww..",
			"..wwww.....SaaaaaaaaS.....wwww..",
			"...ww......SaaaaaaaaS......ww...",
			"....4.....SaaaaaaaaaaS.....4....",
			"...4......S4444444444S......4...",
			"....4....SaaaaaaaaaaaaS....4....",
			"...4...SDaaaaaaaaaaaaaaDS...4...",
			"....4.SSTSSTTSSTTSSTTSSTSS.4....",
			"...4........................4...",
			"....4..........UU..........4....",
		]},
	{"kingdom": "light", "name": "The Overgrown Throne", "short": "The Throne", "line": "The Bush Mage rebuilds his walls and hides behind wards.",
		"boss": {"kind": "mage", "enemy": "lightbushmage", "name": "The Bush Mage"},
		"rows": [
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			"aaDaaaaaaaaaaaaaaaaaaaaaaaaaaDaa",
			"aa?aaaaaaaaaaaaaaaaaaaaaaaaaa?aa",
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			".aa.aa.aa.aa.aa.aa.aa.aa.aa.aa.a",
			"..a..SSSSSSSSSSSSSSSSSSSSSS..a..",
			".....SSRRRRRRRRRRRRRRRRRRSS.....",
			".....SSRRRRRRRRRRRRRRRRRRSS.....",
			".....SSRRRRRRRRRRRRRRRRRRSS.....",
			".....SSRRRRRRRRRRRRRRRRRRSS.....",
			".....SDSSIIIIIIIIIIIIIISSDS.....",
			"...eeaeeeaeSSDSSSSDSSeeeaeeea...",
			"...eaeeeaeeSSGGGGGGSSeeaeeeae...",
			"...eeaeeeaeSSGGDGGGSSeeeaeeea...",
			"...eaeeeaeeSSGGGGGGSSeeaeeeae...",
			"...eeaeeeaeSSSSSSSSSSeeeaeeea...",
			"...eaeeeaSSSSSSSSSSSSSSaeeeae...",
			"....B.B.B.B.B.B.B.B.B.B.B.B.....",
		]},
	{"kingdom": "light", "name": "Steam Baths", "line": "Fire and ice tiles round pools of steam.",
		"rows": [
			"....1..1.....1....1.....1..1....",
			"....D.1.......1...1.....1...1...",
			"...1.1.........1.1.......1...1..",
			"..1..1.........11.........1..1..",
			"..1...1.......1.1.........1.1...",
			"..1....1.....1..1.........11....",
			"...1...1.....1...1.......1.1....",
			"....1..1.....1....1.....1..1....",
			"....1.1.......1...1.....1...1...",
			".S......S......??1.....S......S.",
			".SiiiiiiS......DD......SiiiiiiS.",
			".SwwwwwwS...S......S...SwwwwwwS.",
			".SwwwwwwS...SiiiiiiS...SwwwwwwS.",
			".SSSSSSSS...SwwwwwwS...SSSSSSSS.",
			"..ffffff....SwwwwwwS....ffffff..",
			"............SSSSSSSS............",
			".............ffffff.............",
			"ffffffffffffffffffffffffffffffff",
		]},
	{"kingdom": "light", "name": "The Eclipse Temple", "short": "The Temple", "line": "The sun and the moon, ringed with eclipse.",
		"rows": [
			"dddddddddddddddDddd77dlllld77dddDddddddddddddddd",
			"dddDdddddddddddCddd7dllllddd7dddddddddddddddDddd",
			"dddCdddddddddddddd77lllldddd77dddCdddddddddddddd",
			"dddddddddddddddddd7dllllddddd7ddddddddddCddddddd",
			"dddddddddddddddddd7lllllddddd7dddddddddddddddddd",
			"dddddddddddddddddd7lllldddddd7dddddddddddddddddd",
			"dddddddddCddddddd7dllllddddddd7ddddddddddddddddd",
			"ddddddddddddddddd7dllllddddddd7ddddddddddddddddd",
			"ddddddddddddddddd7lllllddddddd7ddddddddddddddddd",
			"ddddddddddddddddd7lllllddddddd7dddddddddddddCddd",
			"ddddddddddddddddd7lllllddddddd7ddddddddddddddddd",
			"ddddddddddddddddd7lllllddddddd7ddddddddddddddddd",
			"dddddCddddddddddd7dllllldddddd7ddddddddddddddddd",
			"ddddddddddddddddd7dllllldddddd7ddddddCdddddddddd",
			"dddddddddddddddddd7lllllddddd7dddddddddddddddddd",
			"dddddddddddCdddddd7lllllldddd7ddddddddddddCddddd",
			"dddddddddddddddddd7dllllllddd7dddddddddddddddddd",
			"dddddddddddddddddd77llllllll77dddddddddddddddddd",
			"ddddddddddddddddddd7dlllllld7ddddddddddddddddddd",
			"ddddSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSdddd",
			"dddddSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSddddd",
			"ddddddSSNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNSSdddddd",
			"dddddddSSSSSSSSSSSSSSS....SSSSSSSSSSSSSSSddddddd",
			"ddddddddSSSSSSSSSSSSSS.GG.SSSSSSSSSSSSSSdddddddd",
			"dddddddddSSSSSeeeeeeee.GG.eeeeeeeeSSSSSddddddddd",
			"ddddddddddSSSSeeeeeeee.DG.eeeeeeeeSSSSdddddddddd",
			"dddddddddddSSSSSSSSSSS.GG.SSSSSSSSSSSddddddddddd",
			"ddddddddddddSSSSSSSSSS.GG.SSSSSSSSSSdddddddddddd",
		]},
	{"kingdom": "light", "name": "The Portal Maze", "short": "The Maze", "line": "Iron walls, and portals that go round them.",
		"rows": [
			"...............II...............",
			".............IllllI.............",
			"............IllllllI............",
			"..........OllllllllllO..........",
			"........lllllIllllIlllll........",
			"......IllllIllllllllIllllI......",
			"....IIlllIllllIIIIllllIlllII....",
			"...IlllIIllllIlDDlIllllIIlllI...",
			".IllllIllllllll?XllllllllIllllI.",
			".IllllIllllllllX?llllllllIllllI.",
			"...IlllIIllllIllllIllllIIlllI...",
			"....IIlllIllllIIIIllllIlllII....",
			"......IllllIllllllllIllllI......",
			"........lllllIllllIlllll........",
			"..........OllllllllllO..........",
			"............IllllllI............",
			".............IllllI.............",
			"...............II...............",
		]},
	{"kingdom": "light", "name": "The Last Wall", "short": "Last Wall", "line": "Every brick there is, one band after another.",
		"rows": [
			"SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS",
			"SlllllllSlllllllSlllllllSlllllllSlllllllSlllllll",
			"S5555555S5555555S5555555S5555555S5555555S5555555",
			"SaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaa",
			"SNNNNNNNSNNNNNNNSNNNNNNNSNNNNNNNSNNNNNNNSNNNNNNN",
			"SwwwwwwwSwwwwwwwSwwwwwwwSwwwwwwwSwwwwwwwSwwwwwww",
			"S6666666S6666666S6666666S6666666S6666666S6666666",
			"SeeeeeeeSeeeeeeeSeeeeeeeSeeeeeeeSeeeeeeeSeeeeeee",
			"SZZZZZZZSZZZZZZZSZZZZZZZSZZZZZZZSZZZZZZZSZZZZZZZ",
			"SfffCfffSfffCfffSfffCfffSfffCfffSfffCfffSfffCfff",
			"S2222222S2222222S2222222S2222222S2222222S2222222",
			"SiiiiiiiSiiiiiiiSiiiiiiiSiiiiiiiSiiiiiiiSiiiiiii",
			"SGGGDGGGSGGGDGGGSGGGDGGGSGGGDGGGSGGGDGGGSGGGDGGG",
			"SdddddddSdddddddSdddddddSdddddddSdddddddSddddddd",
			"S3333333S3333333S3333333S3333333S3333333S3333333",
			"SlllClllSlllClllSlllClllSlllClllSlllClllSlllClll",
			"STTTTTTTSTTTTTTTSTTTTTTTSTTTTTTTSTTTTTTTSTTTTTTT",
			"SaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaaSaaaaaaa",
			"S4444444S4444444S4444444S4444444S4444444S4444444",
			"SwwwwwwwSwwwwwwwSwwwwwwwSwwwwwwwSwwwwwwwSwwwwwww",
			"SXXXXXXXSXXXXXXXSXXXXXXXSXXXXXXXSXXXXXXXSXXXXXXX",
			"SeeeeeeeSeeeeeeeSeeeeeeeSeeeeeeeSeeeeeeeSeeeeeee",
			"S111U111S111U111S111U111S111U111S111U111S111U111",
			"SiiiiiiiSiiiiiiiSiiiiiiiSiiiiiiiSiiiiiiiSiiiiiii",
			"SYYYYYYYSYYYYYYYSYYYYYYYSYYYYYYYSYYYYYYYSYYYYYYY",
			"SfffffffSfffffffSfffffffSfffffffSfffffffSfffffff",
			"S7777777S7777777S7777777S7777777S7777777S7777777",
			"SBBBBBBBSBBBBBBBSBBBBBBBSBBBBBBBSBBBBBBBSBBBBBBB",
		]},
	{"kingdom": "light", "name": "Citadel of Dawn", "short": "The Citadel", "line": "The Dawn Warden holds the crown. Four keys open the citadel.",
		"boss": {"kind": "ruler", "enemy": "lightboss", "minion": "lightslime", "name": "The Dawn Warden", "crown": true},
		"rows": [
			"SSSSSSSRRRRRRRRRRRRRRRRRRSSSSSSS",
			"SaaaSSSRRRRRRRRRRRRRRRRRRSSSaaaS",
			"SaaaSSSRRRRRRRRRRRRRRRRRRSSSaaaS",
			"SaDaSSSRRRRRRRRRRRRRRRRRRSSSaDaS",
			"SaKaSSSRRRRRRRRRRRRRRRRRRSSSaKaS",
			"SaaaSSDSSIIIIIIIIIIIIIISSDSSaaaS",
			"SaaaSLLLLLLLLLLLLLLLLLLLLLLSaaaS",
			"SaaaSllllllllllllllllllllllSaaaS",
			"SaaaSllllllGllllGllllGlllllSaaaS",
			"SaaaSllllllGGllGGGllGGlllllSaaaS",
			"SaaaSllllllGGGGGDGGGGGlllllSaaaS",
			"SaaaSllllllGGG?GGG?GGGlllllSaaaS",
			"SaaaSllllllGGGGGGGGGGGlllllSaaaS",
			"SaDaSllllllllllllllllllllllSaDaS",
			"SaKaSllllllllllllllllllllllSaKaS",
			"SaaaSSSSSSSSSNNNNNNSSSSSSSSSaaaS",
			"SaaaSSSSSSSSSNNNNNNSSSSSSSSSaaaS",
			"SSSSSSSSSSSSSNNNNNNSSSSSSSSSSSSS",
		]},
]

# Told the first time a character opens Crownfall (the screen's tell_story()).
const STORY := [
	"When the mysterious portals opened, a plague came through with them. Each land's element broke, and spread.",
	"The monsters did not run from the damage. They quarried it, and built kingdoms of plague-stone.",
	"Seven kingdoms rose, and every ruler wears one of the Crowned Beholder's seven crowns.",
	"Every brick you break frees the ground it was cut from.",
	"Break the walls. Heal the land. Take the crowns.",
]


static func made_count() -> int:
	"""How many maps there are to play, in order."""
	return MAPS.size()


static func short_name(index: int) -> String:
	"""A map's name where room is short (the right panel): its own `short`,
	or its name."""
	var m: Dictionary = MAPS[clampi(index, 0, MAPS.size() - 1)]
	return str(m.get("short", m["name"]))


static func kingdom_of(index: int) -> Dictionary:
	"""The kingdom map `index` belongs to."""
	var id: String = str(MAPS[clampi(index, 0, MAPS.size() - 1)]["kingdom"])
	for k in KINGDOMS:
		if k["id"] == id:
			return k
	return {}


static func in_kingdom(index: int) -> int:
	"""Which of its kingdom's maps `index` is, from 0."""
	var id: String = str(MAPS[index]["kingdom"])
	var n: int = 0
	for i in index:
		if str(MAPS[i]["kingdom"]) == id:
			n += 1
	return n


static func maps_of(kingdom_id: String) -> Array:
	"""The indices of a kingdom's maps, in order."""
	var out: Array = []
	for i in MAPS.size():
		if str(MAPS[i]["kingdom"]) == kingdom_id:
			out.append(i)
	return out
