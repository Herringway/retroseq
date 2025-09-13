///
module nspcplay.nspc2;

import nspcplay.common;
import nspcplay.song;
import nspcplay.tags;
import retroseq.utility;

import std.algorithm.searching;
import std.exception;
import std.format;
import std.logger;

///
struct NSPC2PackHeader {
	align(1):
	RelativePointer!(ubyte, uint, 0) start;
	uint length;
	this(uint start, uint length) @safe pure {
		this.start = typeof(this.start)(start);
		this.length = length;
	}
	auto getData(const(ubyte)[] base) const => start.toAbsoluteArray(base, length);
}
///
struct NSPC2PackListHeader {
	align(1):
	RelativePointer!(uint, uint, 0) start;
	uint length;
	this(uint start, uint length) @safe pure {
		this.start = typeof(this.start)(start);
		this.length = length;
	}
	auto getData(const(ubyte)[] base) const => start.toAbsoluteArray(base, length);
}
///
struct NSPC2SubSong {
	align(1):
	ushort songBase;
	ushort instrumentBase;
	ushort sampleBase;
	uint packList;
}
///
struct NSPC2FileHeader {
	align(1):
	char[8] magic = "NSPC2RAD";
	uint songs;
	uint packLists;
	uint packHeadersStart;
	uint packs;
	uint packDataStart;
	uint tagStart;
	NSPC2SubSong[0] subSongs;
	bool isValid() const @safe pure {
		return magic == this.init.magic;
	}
}
Song[] loadNSPC2File(const(ubyte)[] data, ushort[] phrases = []) @safe {
	Song[] songs;
	enforce(data.length > NSPC2FileHeader.sizeof, "File too small");
	const header = read!NSPC2FileHeader(data);
	enforce(header.isValid(), "Invalid NSPC2 header");
	const subSongStart = header.subSongs.offsetof;
	const packListStart = subSongStart + header.songs * NSPC2SubSong.sizeof;
	const packListDataStart = packListStart + header.packLists * NSPC2PackListHeader.sizeof;
	const packStart = header.packHeadersStart;
	const packDataStart = header.packDataStart;
	auto subSongs = cast(const(NSPC2SubSong)[])(data[subSongStart .. packListStart]);
	auto packLists = cast(const(NSPC2PackListHeader)[])(data[packListStart .. packListDataStart]);
	auto packs = cast(const(NSPC2PackHeader)[])(data[packStart .. packDataStart]);
	auto tags = readTags(data);
	foreach (subSongID, subSong; subSongs) {
		debug(nspclogging) tracef("Loading subsong %s", subSongID);
		Song song;
		const songPackList = packLists[subSong.packList].getData(data[packListDataStart .. $]);
		foreach (pack; songPackList) {
			song.loadPacks(readPacks(packs[pack].getData(data[packDataStart .. $])));
		}
		song.songBase = subSong.songBase;
		song.instrumentBase = subSong.instrumentBase;
		song.sampleBase = subSong.sampleBase;
		foreach (tagPair; tags) {
			const songPrefix = format!"_T%X_"(subSongID);
			const thisSongPrefix = format!"_T%X_"(subSongID);
			if (tagPair.key.startsWith(songPrefix)) {
				if (tagPair.key.startsWith(thisSongPrefix)) {
					tagPair.key = tagPair.key[songPrefix.length .. $];
				} else {
					continue;
				}
			}
			handleSpecialTag(song, tagPair);
			song.tags ~= tagPair;
		}
		song.loadNSPC(phrases);
		songs ~= song;
	}
	return songs;
}
///
struct NSPC2Writer {
	const(uint[])[] packLists;
	const(NSPC2SubSong)[] subSongs; ///
	const(Pack)[] packs; ///
	const(TagPair)[][] tags; ///
	///
	void toBytes(W)(ref W writer) const {
		import std.bitmanip : nativeToLittleEndian;
		import std.range : put;
		NSPC2FileHeader header;
		header.songs = cast(uint)subSongs.length;
		header.packLists = cast(uint)packLists.length;
		uint packListOffset;
		NSPC2PackListHeader[] packListHeaders;
		foreach (packList; packLists) {
			assert(packList.length <= uint.max, "Invalid packlist length");
			packListHeaders ~= NSPC2PackListHeader(packListOffset, cast(uint)packList.length);
			packListOffset += packList.length * uint.sizeof;
		}
		uint packOffset;
		NSPC2PackHeader[] packHeaders;
		foreach (pack; packs) {
			assert(pack.data.length <= ushort.max, "Invalid pack size");
			const packLength = cast(uint)(pack.data.length + ushort.sizeof * 2);
			packHeaders ~= NSPC2PackHeader(packOffset, packLength);
			packOffset += packLength;
		}
		header.packs = cast(uint)packs.length;
		header.packHeadersStart = cast(uint)(NSPC2FileHeader.sizeof + NSPC2SubSong.sizeof * subSongs.length + NSPC2PackListHeader.sizeof * packLists.length + packListOffset);
		header.packDataStart = cast(uint)(header.packHeadersStart + packHeaders.length * NSPC2PackHeader.sizeof);
		foreach (pack; packs) {
			header.tagStart += pack.data.length + ushort.sizeof * 2;
		}
		put(writer, cast(ubyte[])cast(NSPC2FileHeader[1])header);
		put(writer, cast(ubyte[])subSongs);
		put(writer, cast(ubyte[])packListHeaders);
		foreach (packList; packLists) {
			put(writer, cast(const(ubyte)[])packList);
		}
		assert(packHeaders.length > 0, "No pack headers");
		put(writer, cast(ubyte[])packHeaders);
		foreach (pack; packs) {
			put(writer, nativeToLittleEndian(pack.size)[]);
			put(writer, nativeToLittleEndian(pack.address)[]);
			put(writer, pack.data);
		}
		const(TagPair)[] finalTags;
		uint[const(char)[]] matchingTagCount;
		bool[const(char)[]] matchingTagWritten;
		const(ubyte)[][const(char)[]] tagsToMatch;
		foreach (idx, tagSet; tags) {
			foreach (pair; tagSet) {
				if (pair.rawValue == tagsToMatch.require(pair.key, pair.rawValue)) {
					matchingTagCount.require(pair.key, 0)++;
				}
			}
		}
		foreach (idx, tagSet; tags) {
			foreach (TagPair pair; tagSet) {
				if (matchingTagCount[pair.key] != tags.length) {
					pair.key = format!"_T%X_%s"(idx, pair.key);
					finalTags ~= pair;
				}
			}
		}
		if (tags.length > 0) {
			foreach (pair; tags[0]) {
				if (matchingTagCount[pair.key] == tags.length) {
					finalTags ~= pair;
				}
			}
		}
		if (finalTags) {
			put(writer, tagsToBytes(finalTags));
		}
	}
}