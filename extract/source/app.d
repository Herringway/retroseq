import std;
import std.experimental.logger;

import nspcplay;
import siryul;

struct SongMetadata {
	string album;
	TrackMetadata[] tracks;
	TagPair[] tags(size_t songID) const {
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
	uint full() const {
		return addr + ((cast(uint)bank) << 16);
	}
}
align(1) static struct PackPointerLH {
	align(1):
	ushort addr;
	ubyte bank;
	uint full() const {
		return addr + ((cast(uint)bank) << 16);
	}
}

int main(string[] args) {
	const rom = readROM(args[1]);
	NSPC2Writer writer;
	if (rom.title == "KIRBY SUPER DELUXE   ") {
		extractKSS(writer, rom.data);
	} else if (rom.title == "Kirby's Dream Course ") {
		extractKDC(writer, rom.data);
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
	} else {
		writefln!"I don't know what '%s' is."(rom.title);
		return 1;
	}
	Appender!(ubyte[]) buffer;
	writer.toBytes(buffer);
	infof("Validating...");
	const loadedSong = loadNSPCFile(buffer.data);
	infof("Writing %s", args[2]);
	File(args[2], "w").rawWrite(buffer.data);
	return 0;
}

struct ROMFile {
	string title;
	const ubyte[] data;
}

ROMFile readROM(string path) {
	const rom = cast(ubyte[])std.file.read(path);
	immutable headerOffsets = [
		0x7FB0: false, //lorom
		0xFFB0: false, //hirom
		0x81B0: true, //lorom + copier header
		0x101B0: true, //hirom + copier header
	];
	foreach (offset, stripHeader; headerOffsets) {
		const ushort checksum = (cast(const(ushort)[])rom[offset + 44 .. offset + 46])[0];
		const ushort checksumComplement = (cast(const(ushort)[])rom[offset + 46 .. offset + 48])[0];
		if ((checksum ^ checksumComplement) == 0xFFFF) {
			return ROMFile((cast(char[])rom[offset + 16 .. offset + 37]).idup, rom[stripHeader ? 0x200 : 0 .. $]);
		}
	}
	return ROMFile.init;
}

void extractEarthbound(ref NSPC2Writer writer,const scope ubyte[] data, bool m2packPointers, size_t packPointerTable, size_t packTableOffset) {
	static immutable metadata = import("eb.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum NUM_SONGS = 0xBF;
	enum NUM_PACKS = 0xA9;
	auto packs = (cast(PackPointer[])(data[packPointerTable .. packPointerTable + NUM_PACKS * PackPointer.sizeof]))
		.map!(x => parsePacks(data[x.full + (m2packPointers ? 0x220000 : -0xC00000) .. $]));
	enum SONG_POINTER_TABLE = 0x294A;
	auto bgmPacks = cast(ubyte[3][])data[packTableOffset .. packTableOffset + (ubyte[3]).sizeof * NUM_SONGS];
	auto songPointers = cast(ushort[])packs[1][2].data[SONG_POINTER_TABLE .. SONG_POINTER_TABLE + ushort.sizeof * NUM_SONGS];
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

void extractKDC(ref NSPC2Writer writer, const scope ubyte[] data) {
	static immutable metadata = import("kdc.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	const sequencePackPointerTable = cast(uint[])data[0x3745 .. 0x3745 + 33 * uint.sizeof];
	const samplePackPointerTable = cast(uint[])data[0x372D .. 0x372D + 3 * uint.sizeof];
	const instrumentPackPointerTable = cast(uint[])data[0x373B .. 0x373B + 2 * uint.sizeof];
	foreach (pack; samplePackPointerTable) {
		writer.packs ~= parsePacks(data[loromToPC(pack) .. $]);
	}
	foreach (pack; instrumentPackPointerTable) {
		writer.packs ~= parsePacks(data[loromToPC(pack) .. $]);
	}
	uint packCount = cast(uint)writer.packs.length;
	auto basePacks = iota(0, packCount).array;
	foreach (idx, sequencePackPointer; sequencePackPointerTable) {
		const seqPack = parsePacks(data[loromToPC(sequencePackPointer) .. $]);
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
	return (((addr & 0x7FFFFF) >> 1) & 0xFF8000) + (addr & 0x7FFF);
}

@safe unittest {
	assert(loromToPC(0x97EDA8) == 0xBEDA8);
}

void extractKSS(ref NSPC2Writer writer, const scope ubyte[] data) {
	static immutable metadata = import("kss.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum PACK_POINTER_TABLE = 0x5703;
	enum InstrumentPackTable = 0x57E7;
	enum numSongs = 65;
	auto packTable = cast(PackPointerLH[])(data[PACK_POINTER_TABLE .. PACK_POINTER_TABLE + (numSongs + 10) * PackPointerLH.sizeof]);
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

void extractSMW(ref NSPC2Writer writer, const scope ubyte[] data) {
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
void extractPilotWings(ref NSPC2Writer writer, const scope ubyte[] data) {
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

void extractZ3(ref NSPC2Writer writer, const scope ubyte[] data) {
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
void extractSMAS(ref NSPC2Writer writer, const scope ubyte[] data) {
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
		const songTable = cast(ushort[])(((idx == 0) ? parsedBaseSong[0] : extra[0]).data[0 .. songCounts[idx] * 2]);
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
void extractFZ(ref NSPC2Writer writer, const scope ubyte[] data) {
	static immutable metadata = import("fzero.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum baseOffset = 0x8000;
	enum songTableOffset = 0x1FD8;
	const parsedBase = parsePacks(data[baseOffset .. $]);
	enum songCount = 17;
	const songTable = cast(ushort[])(parsedBase[4].data[songTableOffset - parsedBase[4].address .. songTableOffset - parsedBase[4].address + songCount * 2]);
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

void extractSMET(ref NSPC2Writer writer, const scope ubyte[] data) {
	static immutable metadata = import("smet.json").fromString!(SongMetadata, JSON, DeSiryulize.optionalByDefault);
	enum songs = 25;
	enum packTableOffset = 0x7E7E1;
	const table = cast(const(PackPointerLH)[])(data[packTableOffset .. packTableOffset + songs * PackPointerLH.sizeof]);
	debug infof("%s", table);
	const first = parsePacks(data[loromToPC(table[0].full) .. $]);
	const firCoefficients = cast(const(ubyte[8])[])(first[2].data[0x1E32 - 0x1500 .. 0x1E32 - 0x1500 + 8 * 11]); //there only seem to be 4, but songs are relying on an invalid 11th preset?
	writer.packs = first;
	uint[] basePacks = iota(0, cast(uint)writer.packs.length).array;
	uint songID = 0;
	foreach (idx, pack; table) {
		const packs = parsePacks(data[loromToPC(pack.full) .. $]);
		auto packList = basePacks ~= iota(cast(uint)writer.packs.length, cast(uint)(writer.packs.length + packs.length)).array;
		writer.packLists ~= packList;
		writer.packs ~= packs;
		const(ushort)[] packSongs;
		uint packSongIndex;
		foreach (sp; packs) {
			if (sp.address == 0x5820) { // initial pack contains 4 'always loaded' songs and one dynamic
				packSongs = cast(const(ushort)[])(sp.data[0 .. 14]);
				packSongIndex = 0;
				break;
			}
			if (sp.address == 0x5828) { // all other packs have a single dynamically loaded song
				const firstSong = (cast(const(ushort)[])(sp.data[0 .. 2]))[0];
				packSongs = cast(const(ushort)[])(sp.data[0 .. firstSong - 0x5828]);
				packSongIndex = 4;
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
