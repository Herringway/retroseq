///
module retroseq.nspc.extract;

import retroseq.ape;
import retroseq.nspc.nspc2;
import retroseq.nspc.common;
import retroseq.nspc.song;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.bitmanip;
import std.format;
import std.range;

import siryul;


struct SongMetadata {
	string album;
	TrackMetadata[] tracks;
	TagPair[] tags(size_t songID) const @safe pure {
		with (songID < tracks.length ? tracks[songID] : TrackMetadata.init) {
			return [
				TagPair("album", album),
				TagPair("title", title),
				TagPair("artist", artist),
			];
		}
	}
}

struct TrackMetadata {
	string title;
	string artist;
}

align(1) struct PackPointer {
	align(1):
	ubyte bank;
	ushort addr;
	uint full() const @safe pure {
		return addr + ((cast(uint)bank) << 16);
	}
}
align(1) static struct PackPointerLH {
	align(1):
	ushort addr;
	ubyte bank;
	uint full() const @safe pure {
		return addr + ((cast(uint)bank) << 16);
	}
}

struct ROMFile {
	string title;
	const ubyte[] data;
}


const(ubyte)[] extractROM(const(ubyte)[] data) @safe pure {
	static ROMFile readROM(const(ubyte)[] data) {
		immutable headerOffsets = [
			0x7FB0: false, //lorom
			0xFFB0: false, //hirom
			0x81B0: true, //lorom + copier header
			0x101B0: true, //hirom + copier header
		];
		foreach (offset, stripHeader; headerOffsets) {
			const ushort checksum = (cast(const(ushort)[])data[offset + 44 .. offset + 46])[0];
			const ushort checksumComplement = (cast(const(ushort)[])data[offset + 46 .. offset + 48])[0];
			if ((checksum ^ checksumComplement) == 0xFFFF) {
				return ROMFile((cast(const(char)[])data[offset + 16 .. offset + 37]).idup, data[stripHeader ? 0x200 : 0 .. $]);
			}
		}
		return ROMFile.init;
	}
	const rom = readROM(data);
	NSPC2Writer writer;
	if (rom.title == "KIRBY SUPER DELUXE   ") {
		extractKSS(writer, rom.data);
	} else if (rom.title == "Kirby's Dream Course ") {
		extractKDC(writer, rom.data);
	} else if (rom.title == "KIRBY'S DREAM LAND 3 ") {
		extractKDL3(writer, rom.data);
	} else if (rom.title == "EARTH BOUND          ") {
		extractEarthbound(writer, rom.data, false, 0x4F947, 0x4F70A);
	} else if (rom.title == "MOTHER-2             ") {
		extractEarthbound(writer, rom.data, true, 0x4CCE2, 0x4CAA5);
	} else if (rom.title == "01 95.03.27          ") {
		extractEarthbound(writer, rom.data, false, 0x4FBD4, 0x4F997);
	} else if (rom.title == "SUPER MARIOWORLD     ") {
		extractSMW(writer, rom.data);
	} else if (rom.title == "PILOTWINGS           ") {
		extractPilotWings(writer, rom.data);
	} else if (rom.title == "F-ZERO               ") {
		extractFZ(writer, rom.data);
	} else if (rom.title == "THE LEGEND OF ZELDA  ") {
		extractZ3(writer, rom.data);
	} else if (rom.title == "SUPER MARIO ALL_STARS") {
		extractSMAS(writer, rom.data);
	} else if (rom.title == "Super Metroid        ") {
		extractSMET(writer, rom.data);
	} else if (rom.title == "YOSHI'S ISLAND       ") {
		extractYI(writer, rom.data);
	} else if (rom.title == "PARODIUS             ") {
		extractParodius(writer, rom.data);
	} else {
		throw new Exception(format!"I don't know what '%s' is."(rom.title));
	}
	Appender!(ubyte[]) buffer;
	writer.toBytes(buffer);
	return buffer.data;
}

void extractEarthbound(ref NSPC2Writer writer,const scope ubyte[] data, bool m2packPointers, size_t packPointerTable, size_t packTableOffset) @safe pure {
	static immutable metadata = import("eb.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum NUM_SONGS = 0xBF;
	enum NUM_PACKS = 0xA9;
	auto packs = (cast(const(PackPointer)[])(data[packPointerTable .. packPointerTable + NUM_PACKS * PackPointer.sizeof]))
		.map!(x => parsePacks(data[x.full + (m2packPointers ? 0x220000 : -0xC00000) .. $]));
	enum SONG_POINTER_TABLE = 0x294A;
	auto bgmPacks = cast(const(ubyte[3])[])data[packTableOffset .. packTableOffset + (ubyte[3]).sizeof * NUM_SONGS];
	auto songPointers = cast(const(ushort)[])packs[1][2].data[SONG_POINTER_TABLE .. SONG_POINTER_TABLE + ushort.sizeof * NUM_SONGS];
	uint[][ulong] packMap;
	uint packIDBase;
	foreach (idx, packSet; packs.enumerate) {
		packMap[idx] = iota(packIDBase, packIDBase + cast(uint)packSet.length).array;
		packIDBase += packSet.length;
		writer.packs ~= packSet;
	}
	foreach (idx, songPacks; bgmPacks) {
		uint[] packList;
		NSPC2SubSong subSong;
		auto tags = metadata.tags(idx);
		subSong.songBase = songPointers[idx];
		subSong.instrumentBase = 0x6E00;
		subSong.sampleBase = 0x6C00;
		subSong.packList = cast(uint)idx;
		tags ~= TagPair("_variant", "standard");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.hal1]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.hal1]);
		if (songPacks[2] == 0xFF) {
			packList ~= packMap[1];
		}
		foreach (pack; songPacks) {
			if (pack == 0xFF) {
				continue;
			}
			packList ~= packMap[pack];
		}
		writer.subSongs ~= subSong;
		writer.tags ~= tags;
		writer.packLists ~= packList;
	}
}

void extractKDC(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("kdc.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	const sequencePackPointerTable = cast(const(uint)[])data[0x3745 .. 0x3745 + 33 * uint.sizeof];
	const samplePackPointerTable = cast(const(uint)[])data[0x372D .. 0x372D + 3 * uint.sizeof];
	const instrumentPackPointerTable = cast(const(uint)[])data[0x373B .. 0x373B + 2 * uint.sizeof];
	foreach (pack; samplePackPointerTable) {
		writer.packs ~= parsePacks(data[lorom80ToPC(pack) .. $]);
	}
	foreach (pack; instrumentPackPointerTable) {
		writer.packs ~= parsePacks(data[lorom80ToPC(pack) .. $]);
	}
	uint packCount = cast(uint)writer.packs.length;
	auto basePacks = iota(0, packCount).array;
	foreach (idx, sequencePackPointer; sequencePackPointerTable) {
		const seqPack = parsePacks(data[lorom80ToPC(sequencePackPointer) .. $]);
		auto packs = basePacks ~ iota(packCount, packCount + cast(uint)seqPack.length).array;
		packCount += seqPack.length;
		NSPC2SubSong subSong;
		auto tags = metadata.tags(idx);
		subSong.songBase = 0x6502;
		subSong.sampleBase = 0x400;
		subSong.instrumentBase = 0x600;
		subSong.packList = cast(uint)idx;
		writer.packs ~= seqPack;
		tags ~= TagPair("_variant", "standard");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.hal3]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.hal3]);
		writer.tags ~= tags;
		writer.subSongs ~= subSong;
		writer.packLists ~= packs;
	}
}

uint loromToPC(uint addr) @safe pure {
	if (addr < 0x400000) {
		return (((addr & 0x7FFFFF) >> 1) & 0xFF8000) + (addr & 0x7FFF);
	} else {
		return addr - 0x400000;
	}
}
@safe unittest {
	assert(loromToPC(0x97EDA8) == 0x57EDA8);
}

uint lorom80ToPC(uint addr) @safe pure {
	return (((addr & 0x7FFFFF) >> 1) & 0xFF8000) + (addr & 0x7FFF);
}

@safe pure unittest {
	assert(lorom80ToPC(0x9B8000) == 0x0D8000);
	assert(lorom80ToPC(0x1B8000) == 0x0D8000);
}

void extractKSS(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("kss.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum PACK_POINTER_TABLE = 0x5703;
	enum InstrumentPackTable = 0x57E7;
	enum numSongs = 65;
	auto packTable = cast(const(PackPointerLH)[])(data[PACK_POINTER_TABLE .. PACK_POINTER_TABLE + (numSongs + 10) * PackPointerLH.sizeof]);
	auto sfxPacks = data[InstrumentPackTable .. InstrumentPackTable + numSongs];
	const progOffset = packTable[0].full - 0xC00000;
	const progPack = parsePacks(data[progOffset .. $]);
	writer.packs ~= progPack;
	uint[][] packMap;
	foreach (pack; packTable) {
		const packOffset = pack.full - 0xC00000;
		const packData = parsePacks(data[packOffset .. $]);
		packMap ~= iota(cast(uint)writer.packs.length, cast(uint)(writer.packs.length + packData.length)).array;
		writer.packs ~= packData;
	}
	auto basePacks = iota(0, cast(uint)progPack.length).array;
	foreach (song; 1 .. numSongs) {
		auto packs = basePacks ~ packMap[sfxPacks[song] + 1] ~ packMap[song + 10];
		NSPC2SubSong subSong;
		auto tags = metadata.tags(song - 1);
		subSong.songBase = writer.packs[packMap[song + 10][0]].address;
		subSong.sampleBase = 0x300;
		subSong.instrumentBase = 0x500;
		subSong.packList = cast(uint)(song - 1);
		tags ~= TagPair("_variant", "standard");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.hal2]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.hal2]);
		writer.tags ~= tags;
		writer.subSongs ~= subSong;
		writer.packLists ~= packs;
	}
}

void extractSMW(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("smw.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum firCoefficientsTable = 0x70DB1;
	const progOffset = 0x70000;
	const sfxOffset = 0x78000;
	const seq1Offset = 0x718B1;
	const seq2Offset = 0x72ED6;
	const seq3Offset = 0x1E400;
	const parsedProg = parsePacks(data[progOffset .. $]);
	const parsedSfx = parsePacks(data[sfxOffset .. $]);
	const parsedSeq1 = parsePacks(data[seq1Offset .. $]);
	const parsedSeq2 = parsePacks(data[seq2Offset .. $]);
	const parsedSeq3 = parsePacks(data[seq3Offset .. $]);
	writer.packs = parsedProg ~ parsedSfx ~ parsedSeq1 ~ parsedSeq2 ~ parsedSeq3;
	auto basePacks = iota(0, cast(uint)(parsedProg.length + parsedSfx.length)).array;
	auto packLists = [
		basePacks,
		basePacks,
		basePacks,
		basePacks ~ iota(cast(uint)(basePacks.length), cast(uint)(basePacks.length + parsedSeq1.length)).array,
		basePacks ~ iota(cast(uint)(basePacks.length + parsedSeq1.length), cast(uint)(basePacks.length + parsedSeq1.length + parsedSeq2.length)).array,
		basePacks ~ iota(cast(uint)(basePacks.length + parsedSeq1.length + parsedSeq2.length), cast(uint)(basePacks.length + parsedSeq1.length + parsedSeq2.length + parsedSeq3.length)).array,
	];
	enum tableBase = 0x135E;
	const ubyte[8][] firCoefficients = cast(const(ubyte[8])[])(data[firCoefficientsTable .. firCoefficientsTable + 2 * 8]);
	size_t songID;
	ushort[1] percussionBase = [ushort(0x5FA5)];
	foreach (bank, pack; chain(parsedProg, parsedSeq1, parsedSeq2, parsedSeq3).enumerate) {
		if (bank == 3) {
			continue;
		}
		auto packs = packLists[bank];
		if (pack.address == 0x1360) {
			ushort currentOffset = tableBase;
			ushort lowest = ushort.max;
			foreach (idx, songAddr; cast(const(ushort)[])pack.data[0 .. 255 * 2]) {
				currentOffset += 2;
				if (lowest <= currentOffset) {
					break;
				}
				NSPC2SubSong subSong;
				subSong.songBase = songAddr;
				subSong.sampleBase = 0x8000;
				subSong.instrumentBase = 0x5F46;
				subSong.packList = cast(uint)songID;
				auto tags = metadata.tags(songID++);
				tags ~= TagPair("_variant", "prototype");
				tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])firCoefficients);
				tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendoProto]);
				tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendoProto]);
				tags ~= TagPair("_percussionBase", cast(ubyte[])percussionBase);
				writer.tags ~= tags;
				writer.subSongs ~= subSong;
				writer.packLists ~= packs;
				lowest = min(songAddr, lowest);
			}
		}
	}
}
void extractPilotWings(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("pilotwings.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum firCoefficientTableOffset = 0x1636;
	enum songTableOffset = 0x1680;
	const progOffset = 0x60000;
	const samplesOffset = 0x28000;
	enum songs = 21;
	const packs = parsePacks(data[progOffset .. $]);
	const samplePacks = parsePacks(data[samplesOffset .. $]);
	writer.packs = packs ~ samplePacks;
	writer.packLists ~= iota(0, cast(uint)writer.packs.length).array;
	const ubyte[8][] firCoefficients = cast(const(ubyte[8])[])(packs[0].data[firCoefficientTableOffset - packs[0].address .. firCoefficientTableOffset - packs[0].address + 8 * 2]);
	ushort[1] percussionBase = [ushort(0x16E6)];
	foreach (song; 0 .. songs) {
		NSPC2SubSong subSong;
		ushort addr = (cast(const(ushort)[])(packs[2].data[songTableOffset - packs[2].address .. songTableOffset - packs[2].address + songs * 2]))[song];
		subSong.songBase = addr;
		subSong.sampleBase = 0x8000;
		subSong.instrumentBase = 0x16AA;
		subSong.packList = 0;
		auto tags = metadata.tags(song);
		tags ~= TagPair("_variant", "prototype");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])firCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
		tags ~= TagPair("_percussionBase", cast(ubyte[])percussionBase);
		writer.tags ~= tags;
		writer.subSongs ~= subSong;
	}
}

void extractZ3(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("z3.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum progOffset = 0xC8000;
	enum songOffset2 = 0xD8000;
	enum songOffset3 = 0xD5380;
	const parsed = [parsePacks(data[progOffset .. $]), parsePacks(data[songOffset2 .. $]), parsePacks(data[songOffset3 .. $])];
	const songTable = cast(const(ushort)[])parsed[0][7].data[0 .. 27 * ushort.sizeof]; //bank 0's song table is a little shorter than the others...?
	const songTable2 = cast(const(ushort)[])parsed[1][0].data[0 .. 35 * ushort.sizeof];
	const songTable3 = cast(const(ushort)[])parsed[2][0].data[0 .. 35 * ushort.sizeof];
	uint songID;
	size_t trackNumber;
	writer.packLists = [
		iota(0, cast(uint)parsed[0].length).array,
		iota(0, cast(uint)(parsed[0].length + parsed[1].length)).array,
		iota(0, cast(uint)parsed[0].length).array ~ iota(cast(uint)(parsed[0].length + parsed[1].length), cast(uint)(parsed[0].length + parsed[1].length + parsed[2].length)).array,
	];
	foreach (p; parsed) {
		writer.packs ~= p;
	}
	foreach (p1, p2, p3; zip(songTable.chain(0.repeat(8)), songTable2, songTable3)) {
		foreach (idx, address; only(p1, p2, p3).enumerate) {
			if (address == 0) {
				continue;
			}
			NSPC2SubSong subSong;
			subSong.songBase = cast(ushort)address;
			subSong.sampleBase = 0x3C00;
			subSong.instrumentBase = 0x3D00;
			subSong.packList = cast(uint)idx;
			auto tags = metadata.tags(trackNumber++);
			tags ~= TagPair("_variant", "standard");
			tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
			tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
			tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
			writer.subSongs ~= subSong;
			writer.tags ~= tags;
		}
		songID++;
	}
}
void extractSMAS(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("smas.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum baseOffset = 0x3FC00;
	enum smb1SongOffset = 0xF8000;
	enum smb2SongOffset = 0xFC000;
	enum smb3SongOffset = 0x60000;
	enum sampleOffset = 0x58000;
	enum baseSongOffset = 0x1D9DCF; // is this really where this starts...? are there other packs before this?
	enum songTableOffset = 0xC000;
	const parsedBase = parsePacks(data[baseOffset .. $]);
	const parsedBaseSong = parsePacks(data[baseSongOffset .. $]);

	const parsedSMB1 = parsePacks(data[smb1SongOffset .. $]);
	const parsedSMB2 = parsePacks(data[smb2SongOffset .. $]);
	const parsedSMB3 = parsePacks(data[smb3SongOffset .. $]);
	const parsedSamples = parsePacks(data[sampleOffset .. $]);
	writer.packs = parsedBase ~ parsedBaseSong ~ parsedSamples ~ parsedSMB1 ~ parsedSMB2 ~ parsedSMB3;
	const extraSongData = [[], parsedSMB1, parsedSMB2, parsedSMB3];
	enum songCounts = [2, 21, 19, 24];
	auto packStart = cast(uint)(parsedBase.length + parsedBaseSong.length + parsedSamples.length);
	foreach (idx, extra; extraSongData) {
		const songTable = cast(const(ushort)[])(((idx == 0) ? parsedBaseSong[0] : extra[0]).data[0 .. songCounts[idx] * 2]);
		writer.packLists ~= iota(0, cast(uint)(parsedBase.length + parsedBaseSong.length + parsedSamples.length)).chain(iota(packStart, packStart + cast(uint)extra.length)).array;
		packStart += extra.length;
		foreach (song; 0 .. songCounts[idx]) {
			NSPC2SubSong subSong;
			subSong.songBase = cast(ushort)songTable[song];
			subSong.sampleBase = 0x3C00;
			subSong.instrumentBase = 0x3D00;
			subSong.packList = cast(uint)idx;
			auto tags = metadata.tags(song);
			tags ~= TagPair("_variant", "standard");
			tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
			tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
			tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
			writer.subSongs ~= subSong;
			writer.tags ~= tags;
		}
	}
}
void extractFZ(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("fzero.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum baseOffset = 0x8000;
	enum songTableOffset = 0x1FD8;
	const parsedBase = parsePacks(data[baseOffset .. $]);
	enum songCount = 17;
	const songTable = cast(const(ushort)[])(parsedBase[4].data[songTableOffset - parsedBase[4].address .. songTableOffset - parsedBase[4].address + songCount * 2]);
	writer.packs = parsedBase;
	writer.packLists ~= iota(0, cast(uint)writer.packs.length).array;
	foreach (song; 0 .. songCount) {
		NSPC2SubSong subSong;
		subSong.songBase = cast(ushort)songTable[song];
		subSong.sampleBase = 0x3C00;
		subSong.instrumentBase = 0x518;
		subSong.packList = 0;
		auto tags = metadata.tags(song);
		tags ~= TagPair("_variant", "fzero");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
		tags ~= TagPair("_masterVolume", "84");
		writer.tags ~= tags;
		writer.subSongs ~= subSong;
	}
}

void extractSMET(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("smet.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum songs = 25;
	enum packTableOffset = 0x7E7E1;
	const table = cast(const(PackPointerLH)[])(data[packTableOffset .. packTableOffset + songs * PackPointerLH.sizeof]);
	const first = parsePacks(data[lorom80ToPC(table[0].full) .. $]);
	const firCoefficients = cast(const(ubyte[8])[])(first[2].data[0x1E32 - 0x1500 .. 0x1E32 - 0x1500 + 8 * 11]); //there only seem to be 4, but songs are relying on an invalid 11th preset?
	writer.packs = first;
	uint[] basePacks = iota(0, cast(uint)writer.packs.length).array;
	uint songID = 0;
	foreach (idx, pack; table) {
		const packs = parsePacks(data[lorom80ToPC(pack.full) .. $]);
		auto packList = basePacks ~= iota(cast(uint)writer.packs.length, cast(uint)(writer.packs.length + packs.length)).array;
		writer.packLists ~= packList;
		writer.packs ~= packs;
		const(ushort)[] packSongs;
		foreach (sp; packs) {
			if (sp.address == 0x5820) { // initial pack contains 4 'always loaded' songs and one dynamic
				packSongs = cast(const(ushort)[])(sp.data[0 .. 14]);
				break;
			}
			if (sp.address == 0x5828) { // all other packs have a single dynamically loaded song
				const firstSong = (cast(const(ushort)[])(sp.data[0 .. 2]))[0];
				packSongs = cast(const(ushort)[])(sp.data[0 .. firstSong - 0x5828]);
				break;
			}
		}
		foreach (packSong; packSongs) {
			NSPC2SubSong subSong;
			subSong.songBase = packSong;
			subSong.sampleBase = 0x6D00;
			subSong.instrumentBase = 0x6C00;
			subSong.packList = cast(uint)(writer.packLists.length - 1);
			auto tags = metadata.tags(songID++);
			tags ~= TagPair("_variant", "standard");
			tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])firCoefficients);
			tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
			tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
			writer.tags ~= tags;
			writer.subSongs ~= subSong;
		}
	}
}

void extractYI(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("yi.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum tableBase = 0x4AC;
	enum packSets = 13;
	enum packs = 20;
	enum itemBlockTableSize = 19;
	enum trackPackCount = 20; // there are actually more than this - many entries include extra tracks
	enum extraSongs = 6;
	enum packTableOffset = tableBase + PackPointerLH.sizeof * packs;
	enum songTableOffset = packTableOffset + packSets * (ubyte[4]).sizeof + itemBlockTableSize;
	enum spcSongTableOffset;
	auto table = cast(const(PackPointerLH)[])(data[tableBase .. packTableOffset]);
	auto packTable = cast(const(ubyte[4])[])(data[packTableOffset .. packTableOffset + (ubyte[4]).sizeof * packSets]);
	auto songPackTable = cast(const(ubyte)[])(data[songTableOffset .. songTableOffset + ubyte.sizeof * trackPackCount]);
	uint[][] packMap;
	uint packOffset;
	foreach (i, packPtr; table) {
		auto foundPacks = parsePacks(data[loromToPC(packPtr.full) .. $]);
		packMap ~= iota(packOffset, packOffset + cast(uint)foundPacks.length).array;
		writer.packs ~= foundPacks;
		packOffset += foundPacks.length;
	}
	size_t songID;
	bool[ubyte[4]] seenSongs;
	foreach (idx, songPackIndex; songPackTable) {
		auto songPacks = packTable[songPackIndex / 4];
		if (seenSongs.get(songPacks, false)) {
			continue;
		}
		seenSongs[songPacks] = true;
		uint[] packList = packMap[14]; // 14 (title) includes the sound program and other important data
		const(ushort)[] subSongs;
		if (idx == 12) {
			packList ~= packMap[12]; // assumes sfx were already loaded
		}
		foreach (songPack; songPacks) {
			if (songPack == 0xFF) {
				continue;
			}
			const actualPackIndex = (songPack - 1) / PackPointerLH.sizeof;
			foreach (usedPack; packMap[actualPackIndex]) {
				const subPack = writer.packs[usedPack];
				if (subPack.address.among(0xFF90, 0xFFA0)) {
					subSongs ~= cast(const(ushort)[])subPack.data;
				}
			}
			packList ~= packMap[actualPackIndex];
		}
		foreach (subSongAddress; subSongs) {
			NSPC2SubSong subSong;
			subSong.songBase = subSongAddress;
			subSong.sampleBase = 0x3C00;
			subSong.instrumentBase = 0x3D00;
			subSong.packList = cast(uint)writer.packLists.length;
			auto tags = metadata.tags(songID++);
			tags ~= TagPair("_variant", "standard");
			tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
			tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.nintendo1]);
			tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.nintendo1]);
			writer.tags ~= tags;
			writer.subSongs ~= subSong;
		}
		writer.packLists ~= packList;
	}
}

void extractKDL3(ref NSPC2Writer writer, const scope ubyte[] data) @safe pure {
	static immutable metadata = import("kdl3.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum songs = 44;
	const packs1 = parsePacks(data[0xE0000 .. $]);
	const packs2 = parsePacks(data[0xEA0EF .. $]);
	enum songTableOffset = 0x5EAF;
	enum pack2TableOffset = 0x5F69;
	enum extraPackTableOffset = 0x10CA2D;
	const table = cast(const(PackPointerLH)[])(data[songTableOffset .. songTableOffset + songs * PackPointerLH.sizeof]);
	const table2 = cast(const(PackPointerLH)[])(data[pack2TableOffset .. pack2TableOffset + 11 * PackPointerLH.sizeof]);
	const extraPackTable = data[extraPackTableOffset .. extraPackTableOffset + songs * ubyte.sizeof];
	writer.packs ~= packs1;
	writer.packs ~= packs2;
	auto basePacks = iota(0, cast(uint)writer.packs.length).array;
	size_t idx;
	const pack2Base = cast(uint)writer.packs.length;
	uint[][] extraPacks;
	foreach (pack2Pointer; table2) {
		if (pack2Pointer.full == 0) {
			extraPacks.length++;
		} else {
			const packs = parsePacks(data[pack2Pointer.full - 0xC00000 .. $]);
			extraPacks ~= iota(cast(uint)writer.packs.length, cast(uint)(writer.packs.length + packs.length)).array;
			writer.packs ~= packs;
		}
	}
	foreach (realTrack, sequencePackPointer; table) {
		auto packs = basePacks;
		const extraPack = (extraPackTable[realTrack] & 0x7F);
		packs ~= extraPacks[extraPack];
		if (sequencePackPointer.full != 0) {
			packs ~= cast(uint)writer.packs.length;
			writer.packs ~= parsePacks(data[sequencePackPointer.full - 0xC00000 .. $]);
		}
		ushort songBase;
		foreach (songPack; packs.map!(x => writer.packs[x])) {
			enum songTableEntry = 0x32FE + 0x76 * 2; // always song 0x76
			if ((songPack.address <= songTableEntry) && (songTableEntry <= songPack.address + songPack.size)) {
				const offset = songTableEntry - songPack.address;
				songBase = (cast(const(ushort)[])songPack.data[offset .. offset + ushort.sizeof])[0];
			}
		}
		NSPC2SubSong subSong;
		auto tags = metadata.tags(idx);
		subSong.songBase = songBase;
		subSong.sampleBase = 0x300;
		subSong.instrumentBase = 0x500;
		subSong.packList = cast(uint)idx;
		tags ~= TagPair("_variant", "standard");
		tags ~= TagPair("_firCoefficients", cast(const(ubyte)[])defaultFIRCoefficients);
		tags ~= TagPair("_volumeTable", volumeTables[VolumeTable.hal2]);
		tags ~= TagPair("_releaseTable", releaseTables[ReleaseTable.hal2]);
		writer.tags ~= tags;
		writer.subSongs ~= subSong;
		writer.packLists ~= packs;
		idx++;
	}
}
