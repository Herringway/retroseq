///
module nspcplay.nspc1;

import nspcplay.common;
import nspcplay.song;
import nspcplay.tags;

///
struct NSPCFileHeader {
	align(1):
	static union Extra {
		struct { // Variant.prototype, addmusick
			ushort percussionBase; ///
			ushort customInstruments; /// addmusick only
		}
		ubyte[19] reserved; ///
	}
	/// Which version of NSPC to use
	Variant variant;
	/// Base SPC address of the song's sequence data
	ushort songBase;
	/// Base SPC address of the instruments
	ushort instrumentBase;
	/// Base SPC address of the samples
	ushort sampleBase;
	/// Release table to use
	ReleaseTable releaseTable;
	/// Volume table to use
	VolumeTable volumeTable;
	/// Extra information for variants
	Extra extra;
	/// Number of FIR coefficient tables
	ubyte firCoefficientTableCount;
}

Song loadNSPC1File(const(ubyte)[] data, ushort[] phrases = []) @safe {
	Song song;
	ubyte[65536] buffer;
	auto header = read!NSPCFileHeader(data);
	const remaining = loadAllSubpacks(buffer[], data[NSPCFileHeader.sizeof .. $]);
	if (header.firCoefficientTableCount == 0) {
		song.firCoefficients = defaultFIRCoefficients;
	} else {
		song.firCoefficients = cast(const(ubyte[8])[])remaining[0 .. 8 * header.firCoefficientTableCount].dup;
	}
	song.tags = readTags(remaining[8 * header.firCoefficientTableCount .. $]);
	loadOldHeader(song, header);
	foreach (tagPair; song.tags) {
		handleSpecialTag(song, tagPair);
	}
	song.loadNSPC(buffer[]);
	return song;
}

void loadOldHeader(ref Song song, NSPCFileHeader header) @safe pure {
	song.variant = header.variant;
	song.instrumentBase = header.instrumentBase;
	song.songBase = header.songBase;
	song.sampleBase = header.sampleBase;
	assert(header.volumeTable < volumeTables.length, "Invalid volume table");
	assert(header.releaseTable < releaseTables.length, "Invalid release table");
	song.releaseTable = releaseTables[header.releaseTable];
	song.volumeTable = volumeTables[header.volumeTable];
	if (song.variant == Variant.prototype) {
		song.percussionBase = header.extra.percussionBase;
	}
	if (song.variant == Variant.addmusick) {
		song.percussionBase = header.extra.percussionBase;
		song.customInstruments = header.extra.customInstruments;
	}
}

///
struct NSPCWriter {
	private static immutable ubyte[] packTerminator = [0, 0]; ///
	NSPCFileHeader header; ///
	const(Pack)[] packs; ///
	const(ubyte[8])[] firCoefficients; ///
	const(TagPair)[] tags; ///
	///
	void toBytes(W)(ref W writer) const {
		import std.bitmanip : nativeToLittleEndian;
		import std.range : put;
		put(writer, (cast(const(ubyte)[NSPCFileHeader.sizeof])header)[]);
		foreach (pack; packs) {
			put(writer, nativeToLittleEndian(pack.size)[]);
			put(writer, nativeToLittleEndian(pack.address)[]);
			put(writer, pack.data);
		}
		put(writer, packTerminator);
		foreach (coeff; firCoefficients) {
			put(writer, coeff[]);
		}
		if (tags) {
			put(writer, tagsToBytes(tags));
		}
	}
}
@safe pure unittest {
	import std.array : Appender;
	static immutable ubyte[] pack1 = [1, 2, 3, 4, 5];
	static immutable ubyte[] pack2 = [5, 4, 3, 2, 1, 0];
	Appender!(ubyte[]) buffer;
	NSPCWriter writer;
	writer.packs ~= Pack(0x1234, pack1);
	writer.packs ~= Pack(0x5678, pack2);
	writer.header.songBase = 0x2345;
	writer.header.instrumentBase = 0x6789;
	writer.header.sampleBase = 0x0123;
	writer.toBytes(buffer);
	assert(buffer[] == [0x00, 0x00, 0x00, 0x00, 0x45, 0x23, 0x89, 0x67, 0x23, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x34, 0x12, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x78, 0x56, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00, 0x00, 0x00]);
}
