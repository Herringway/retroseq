///
module retroseq.nspc.song;

import std.algorithm.comparison : among, max, min;
import std.algorithm.sorting : sort;
import std.algorithm.searching;
import std.conv : to;
import std.exception : enforce;
import std.experimental.logger;
import std.format : format;
import std.range : only;

import retroseq.ape;
import retroseq.nspc.common;
import retroseq.nspc.samples;
import retroseq.nspc.sequence;
import retroseq.nspc.nspc1;
import retroseq.nspc.nspc2;
import retroseq.utility;

private enum maxInstruments = 128; ///
private enum maxSampleCount = 128; ///

///
enum PhraseType {
	pattern, ///
	jumpLimited, ///
	jump, ///
	end, ///
	fastForwardOn, ///
	fastForwardOff, ///
}

///
struct Phrase {
	PhraseType type; ///
	ushort id; ///
	ushort jumpTimes; ///
	void toString(S)(ref S sink) const {
		import std.format : formattedWrite;
		final switch (type) {
			case PhraseType.pattern:
				sink.formattedWrite!"Play pattern %04X"(id);
				break;
			case PhraseType.jumpLimited:
				sink.formattedWrite!"Jump to phrase %s %s times"(id, jumpTimes);
				break;
			case PhraseType.jump:
				sink.formattedWrite!"Jump to phrase %s"(id);
				break;
			case PhraseType.end:
				sink.formattedWrite!"End of song"();
				break;
			case PhraseType.fastForwardOn:
				sink.formattedWrite!"Fast forward on"();
				break;
			case PhraseType.fastForwardOff:
				sink.formattedWrite!"Fast forward off"();
				break;
		}
	}
}

///
struct Track {
	const(Command)[] data; ///
}

///
struct Song {
	ushort songBase;
	ushort instrumentBase;
	ushort sampleBase;
	ushort customInstruments; /// addmusick only
	Phrase[] order; ///
	ushort[8][ushort] trackLists; ///
	Track[ushort] tracks; ///
	const(ubyte[8])[] firCoefficients = defaultFIRCoefficients; ///
	ubyte[8] releaseTable; ///
	/// Alternative release table to use when switch command is used (AMK)
	ubyte[8] altReleaseTable; ///
	ubyte[16] volumeTable; ///
	Variant variant; ///
	const(Instrument)[] instruments; ///
	Sample[128] samples; ///
	ubyte[256] percussionNotes; ///
	size_t percussionBase; ///
	byte masterVolume = 0x70; ///
	TagPair[] tags; ///
	ushort[13] noteFrequencyTable = [0x085F, 0x08DE, 0x0965, 0x09F4, 0x0A8C, 0x0B2C, 0x0BD6, 0x0C8B, 0x0D4A, 0x0E14, 0x0EEA, 0x0FCD, 0x10BE];
	const(Pack)[] packs; /// Original packs used for song
	///
	void loadPacks(scope const ubyte[] packData) pure @safe {
		packs ~= parsePacks(packData);
	}
	///
	void loadPacks(const Pack[] packs) pure @safe {
		this.packs ~= packs;
	}
	///
	void initializeInstruments(scope const ubyte[] buffer, ushort instrumentBase, ushort sampleBase) @safe {
		this.instrumentBase = instrumentBase;
		this.sampleBase = sampleBase;
		processInstruments(this, buffer);
	}
	///
	void loadNSPC(ushort[] phrases = []) @safe pure {
		ubyte[65536] buffer;
		foreach (pack; packs) {
			buffer[pack.address .. pack.address + pack.data.length] = pack.data;
		}
		debug(nspclogging) tracef("Loading NSPC - so: %X, i: %X, sa: %X, variant: %s", songBase, instrumentBase, sampleBase, variant);
		if (variant == Variant.addmusick) {
			altReleaseTable = releaseTables[0]; // AMK allows the 'default' release table to be used as well
		}
		processInstruments(this, buffer[]);
		order = phrases == null ? decompilePhrases(buffer[], songBase) : interpretPhrases(phrases, songBase);
		decompileSong(buffer[], this);
		debug(nspclogging) tracef("FIR coefficients: %s", firCoefficients);
	}
	///
	private void validatePhrases() @safe pure {
		import std.algorithm.comparison : among;
		bool endFound;
		foreach (phrase; order) {
			enforce!NSPCException(!endFound, "Phrases found after end of song");
			final switch (phrase.type) {
				case PhraseType.end:
					endFound = true;
					break;
				case PhraseType.fastForwardOn:
				case PhraseType.fastForwardOff:
					throw new NSPCException("Fast forward not yet supported");
				case PhraseType.jump:
				case PhraseType.jumpLimited:
					enforce!NSPCException(phrase.id < order.length, "Cannot jump past end of song");
					break;
				case PhraseType.pattern:
					break;
			}
		}
		enforce!NSPCException(order.length > 0, "No phrases loaded");
		enforce!NSPCException(order[$ - 1].type.among(PhraseType.end, PhraseType.jump), "Phrase list must have an end phrase");
	}
	///
	private void validateInstrument(size_t id) @safe pure {
		enforce!NSPCException(id < instruments.length, format!"Invalid instrument %s - Index out of bounds"(id));
		const idata = instruments[id];
		if (idata.sampleID < 0x7F) {
			enforce!NSPCException(samples[idata.sampleID].data.length > 0, format!"Invalid instrument %s - Sample %s has no valid data"(id, idata.sampleID));
			if (idata.tuning == 0) {
				debug(nspclogging) tracef("Suspicious instrument %s - no tuning (will be silent)", id);
			}
		}
	}
	///
	void validateTrack(scope const Track track, bool isSub, ref ubyte tmpPercussionBase) @safe pure {
		const(Command)[] data = track.data;
		bool endReached;
		while (data.length > 0) {
			const command = data[0];
			data = data[1 .. $];
			enforce!NSPCException(!endReached, "Track must end with terminator");
			final switch (command.type) {
				case VCMDClass.terminator:
					endReached = true;
					break;
				case VCMDClass.noteDuration:
					enforce!NSPCException(data.length > 0, "Track can not end with note-length code");
					break;
				case VCMDClass.percussion:
					validateInstrument(absoluteInstrumentID(command.instrument, tmpPercussionBase, true));
					break;
				case VCMDClass.special:
					enforce!NSPCException(command.special != VCMD.invalid, format!"Invalid code command %02X"(command.relative));

					switch(command.special) {
						case VCMD.instrument:
							validateInstrument(absoluteInstrumentID(command.parameters[0], tmpPercussionBase, false));
							break;
						case VCMD.subRoutine:
							ushort sub = read!ushort(command.parameters);
							enforce!NSPCException(sub in tracks, format!"Subroutine %d not present"(sub));
							enforce!NSPCException(command.parameters[2] != 0, "Subroutine loop count can not be 0");
							break;
						case VCMD.percussionBaseInstrumentRedefine:
							tmpPercussionBase = command.parameters[0];
							break;
						case VCMD.echoParameterSetup:
							enforce!NSPCException(firCoefficients.length > command.parameters[2], format!"FIR coefficient table %s out of range!"(command.parameters[2]));
							break;
						default: //nothing to validate
							break;
					}
					break;
				case VCMDClass.note: // nothing to validate here
				case VCMDClass.tie:
				case VCMDClass.rest:
					break;
			}
		}
	}
	///
	package size_t absoluteInstrumentID(size_t id, size_t base, bool percussion) const @safe pure nothrow {
		if (id >= percussionID(variant)) {
			percussion = true;
			id -= percussionID(variant);
		}
		if (percussion) {
			id += base;
		}
		return id;
	}
	///
	package ubyte defaultTempo() const @safe pure nothrow {
		if (variant == Variant.konami) {
			return 0x40;
		}
		if (variant == Variant.prototype) {
			return 0x36;
		}
		return 0x20;
	}
	// I hope these two never need to be changed
	///
	package ubyte masterVolumeL() const @safe pure nothrow {
		return masterVolume;
	}
	///
	package ubyte masterVolumeR() const @safe pure nothrow {
		return masterVolume;
	}
	///
	package bool defaultEnchantedReadahead() const @safe pure nothrow {
		return !variant.among(Variant.prototype, Variant.addmusick);
	}
	///
	package ubyte defaultEnabledChannels() const @safe pure nothrow {
		if (variant.among(Variant.prototype, Variant.addmusick)) {
			return 0b11011111;
		}
		return 0b11111111;
	}
	///
	void toString(S)(ref S sink) const {
		import std.format : formattedWrite;
		import std.range : put;
		void printSequence(Track track) {
			bool done;
			while((track.data.length > 0) && (!done)) {
				const command = track.data[0];
				sink.formattedWrite!"%x\n"(command);
				if (command.type == VCMDClass.terminator) {
					done = true;
				}
				track.data = track.data[1 .. $];
			}
		}
		sink.formattedWrite!"Phrases: %s\n"(order);
		foreach (id, trackList; trackLists) {
			sink.formattedWrite!"Pattern %04X\n"(id);
			foreach (trackID, track; trackList) {
				put(sink, "----------\n");
				sink.formattedWrite!"Track %s ($%04X)\n"(trackID, track);
				printSequence(tracks.get(track, Track.init));
			}
		}
		outer: foreach (subroutineID, subroutine; tracks) {
			foreach (trackList; trackLists) {
				if (trackList[].canFind(subroutineID)) {
					continue outer;
				}
			}
			put(sink, "----------\n");
			sink.formattedWrite!"Subroutine %04X\n"(subroutineID);
			printSequence(subroutine);
		}
	}
	///
	private void _tmp() const {
		import std.range : nullSink;
		auto n = nullSink;
		toString(n);
	}
	///
	const(Sample)[] getSamples() const pure @safe nothrow return {
		import std.algorithm.iteration : filter;
		import std.array : array;
		return samples[].filter!(x => x.isValid).array;
	}
	///
	void replaceSample(size_t index, short[] data, int newLoop) @safe pure nothrow {
		samples[index].data = data;
		samples[index].loopLength = newLoop;
	}
	///
	void replaceSample(size_t index, short[] data) @safe pure nothrow {
		replaceSample(index, data, samples[index].loopLength);
	}
	///
	bool isValid() const @safe pure nothrow {
		return trackLists.length != 0;
	}
}
///
private struct PrototypeInstrument {
	align(1):
	ubyte sampleID; ///
	ADSRGain adsrGain; ///
	ubyte tuning; ///
	///
	Instrument opCast(T: Instrument)() const {
		return Instrument(sampleID, adsrGain, tuning, 0);
	}
}
///
private struct PrototypePercussion {
	align(1):
	ubyte sampleID; ///
	ADSRGain adsrGain; ///
	ubyte tuning; ///
	ubyte note; ///
	///
	Instrument opCast(T: Instrument)() const {
		return Instrument(sampleID, adsrGain, tuning, 0);
	}
}

/// note style tables, from 6F80
immutable ubyte[8][] releaseTables = [
	[0x32, 0x65, 0x7F, 0x98, 0xB2, 0xCB, 0xE5, 0xFC],
	[0x33, 0x66, 0x7F, 0x99, 0xB2, 0xCC, 0xE5, 0xFC], // HAL (Earthbound)
	[0x65, 0x7F, 0x98, 0xB2, 0xCB, 0xE5, 0xF2, 0xFC], // HAL (Kirby Super Star)
	[0x66, 0x7F, 0x99, 0xB2, 0xCC, 0xE5, 0xF2, 0xFC], // HAL (Kirby's Dream Course)
	[0x7F, 0xA5, 0xB2, 0xBF, 0xCC, 0xD8, 0xE5, 0xFC], // Nintendo (Star Fox 2)
	[0x33, 0x66, 0x80, 0x99, 0xB3, 0xCC, 0xE6, 0xFF], // Nintendo (Prototype)
];
///
immutable ubyte[16][] volumeTables = [
	[0x19, 0x32, 0x4C, 0x65, 0x72, 0x7F, 0x8C, 0x98, 0xA5, 0xB2, 0xBF, 0xCB, 0xD8, 0xE5, 0xF2, 0xFC],
	[0x19, 0x33, 0x4C, 0x66, 0x72, 0x7F, 0x8C, 0x99, 0xA5, 0xB2, 0xBF, 0xCC, 0xD8, 0xE5, 0xF2, 0xFC], // HAL (Earthbound)
	[0x4C, 0x59, 0x6D, 0x7F, 0x87, 0x8E, 0x98, 0xA0, 0xA8, 0xB2, 0xBF, 0xCB, 0xD8, 0xE5, 0xF2, 0xFC], // HAL (Kirby Super Star)
	[0x59, 0x66, 0x72, 0x7F, 0x87, 0x8E, 0x99, 0xA0, 0xA8, 0xB2, 0xBF, 0xCC, 0xD8, 0xE5, 0xF2, 0xFC], // HAL (Kirby's Dream Course)
	[0x00, 0x33, 0x4C, 0x66, 0x72, 0x7F, 0x8C, 0x99, 0xA5, 0xB2, 0xBF, 0xCC, 0xD8, 0xE5, 0xF2, 0xFC], // Nintendo (Star Fox 2)
	[0x08, 0x12, 0x1B, 0x24, 0x2C, 0x35, 0x3E, 0x47, 0x51, 0x5A, 0x62, 0x6B, 0x7D, 0x8F, 0xA1, 0xB3], // Nintendo (Prototype)
];
///
immutable ubyte[8][] defaultFIRCoefficients = [
	[0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x58, 0xBF, 0xDB, 0xF0, 0xFE, 0x07, 0x0C, 0x0C],
	[0x0C, 0x21, 0x2B, 0x2B, 0x13, 0xFE, 0xF3, 0xF9],
	[0x34, 0x33, 0x00, 0xD9, 0xE5, 0x01, 0xFC, 0xEB],
];

///
const(ubyte)[] readAllSubpacks(out Pack[] packs, return scope const(ubyte)[] pack) @safe pure {
	while (true) {
		if (pack.length == 0) {
			break;
		}
		const size = read!ushort(pack);
		if (size == 0) {
			break;
		}
		const base = read!ushort(pack, 2);
		const truncated = min(65535, base + size) - base;
		packs ~= Pack(base, pack[4 .. truncated + 4]);
		pack = pack[size + 4 .. $];
	}
	return pack[min($, 2) .. $];
}
Pack[] readPacks(return const(ubyte)[] data) @safe pure {
	Pack[] result;
	readAllSubpacks(result, data);
	return result;
}

/// Load an NSPC file
Song[] loadNSPCFile(const(ubyte)[] data, ushort[] phrases = []) @safe {
	try {
		return loadNSPC2File(data, phrases);
	} catch (Exception e) {
		try {
			return [loadNSPC1File(data, phrases)];
		} catch (Exception e2) {
			throw new NSPCException("Failed to load NSPC file");
		}
	}
}
package void handleSpecialTag(ref Song song, const TagPair pair) @safe pure {
	switch (pair.key) {
		case "_masterVolume":
			song.masterVolume = pair.str.to!byte;
			break;
		case "_volumeTable":
			song.volumeTable = pair.binary;
			break;
		case "_releaseTable":
			song.releaseTable = pair.binary;
			break;
		case "_firCoefficients":
			song.firCoefficients = (cast(const(ubyte[8])[])pair.binary);
			break;
		case "_pitchTable":
			song.noteFrequencyTable = (cast(const(ushort[13])[])pair.binary)[0];
			break;
		case "_variant":
			song.variant = pair.str.to!Variant;
			break;
		case "_percussionBase":
			song.percussionBase = pair.binary.read!ushort;
			break;
		default:
			break;
	}
}
///
private Phrase[] decompilePhrases(scope const(ubyte)[] data, ushort startAddress) @safe pure {
	// Get order length and repeat info (at this point, we don't know how
	// many patterns there are, so the pattern pointers aren't validated yet)
	const ushort[] wpO = cast(const(ushort)[]) data[startAddress .. $ -  ($ - startAddress) % 2];
	uint index;
	uint phraseCount;
	bool nextEnds;
	while (wpO[index] != 0) {
		if (wpO[index] < 0x100) {
			if (wpO[index] >= 0x80) {
				nextEnds = true;
			}
			index++;
		}
		if (nextEnds) {
			break;
		}
		phraseCount++;
		index++;
	}
	//enforce!NSPCException(phraseCount > 0, "No phrases in song");
	return interpretPhrases(wpO[0 .. index + 1], startAddress);
}
///
private Phrase[] interpretPhrases(const scope ushort[] addresses, ushort startAddress) @safe pure {
	ushort phraseID(ushort address) {
		ushort id;
		const offset = (address - startAddress) >> 1;
		uint o;
		bool skip;
		while ((o < offset) && (addresses[o] != 0)) {
			if (addresses[o] < 0x80) {
				skip = true;
			} else if ((addresses[o] > 0x81) && (addresses[o] < 0x100)) {
				skip = true;
			}
			if (!skip) {
				id++;
			} else {
				skip = false;
			}
			o++;
		}
		return id;
	}
	Phrase[] newPhrases;
	newPhrases.reserve(addresses.length);
	for (size_t idx = 0; idx < addresses.length; idx++) {
		Phrase newPhrase;
		if (addresses[idx] == 0) {
			newPhrase.type = PhraseType.end;
		} else if (addresses[idx] == 0x80) {
			newPhrase.type = PhraseType.fastForwardOn;
		} else if (addresses[idx] == 0x81) {
			newPhrase.type = PhraseType.fastForwardOff;
		} else if (addresses[idx] < 0x80) {
			newPhrase.type = PhraseType.jumpLimited;
			newPhrase.jumpTimes = addresses[idx];
			idx++;
			newPhrase.id = phraseID(addresses[idx]);
		} else if ((addresses[idx] > 0x81) && (addresses[idx] < 0x100)) {
			newPhrase.type = PhraseType.jump;
			idx++;
			newPhrase.id = phraseID(addresses[idx]);
		} else {
			newPhrase.type = PhraseType.pattern;
			newPhrase.id = addresses[idx];
		}
		newPhrases ~= newPhrase;
	}
	return newPhrases;
}
///
private void decompileSong(scope const(ubyte)[] data, ref Song song) @safe pure {
	immutable copyData = data.idup;

	debug(nspclogging) tracef("Phrases: %(%s, %)", song.order);
	song.validatePhrases();

	song.trackLists = null;
	song.tracks = null;

	ubyte tmpPercussionBase;
	foreach (phrase; song.order) {
		if (phrase.type != PhraseType.pattern) {
			continue;
		}
		song.trackLists.require(phrase.id, (cast(const(ushort[8])[])(data[phrase.id .. phrase.id + 8 * ushort.sizeof]))[0]);
	}
	foreach (trackList; song.trackLists) {
		foreach (idx, trackAddress; trackList) {
			if (trackAddress == 0) {
				continue;
			}
			debug(nspclogging) tracef("Decompiling track at %04X", trackAddress);
			song.tracks[trackAddress] = decompileTrack(copyData, trackAddress, song, tmpPercussionBase, true);
		}
	}
}
Track decompileTrack(immutable(ubyte)[] data, Variant variant) @safe pure {
	Track track;
	while (true) {
		size_t length;
		const command = readCommand(variant, data, length);
		track.data ~= command;
		data = data[length .. $];
		if (command.type == VCMDClass.terminator) {
			break;
		}
	}
	return track;
}
///
private Track decompileTrack(immutable(ubyte)[] data, ushort start, ref Song song, ref ubyte tmpPercussionBase, bool recurse) @safe pure {
	auto track = decompileTrack(data[start .. $], song.variant);
	foreach (command; track.data) {
		if (command.special == VCMD.subRoutine) { //decompile subroutines too
			enforce!NSPCException(recurse, "Subroutines can't call subroutines!");
			ushort subPtr = read!ushort(command.parameters);

			song.tracks.require(subPtr, decompileTrack(data, subPtr, song, tmpPercussionBase, false));
		}
		if (command.special == VCMD.amkRemoteCommand) { //also decompile 'remotes'
			ushort subPtr = read!ushort(command.parameters);
			song.tracks.require(subPtr, decompileTrack(data, subPtr, song, tmpPercussionBase, false));
		}
	}
	song.validateTrack(track, false, tmpPercussionBase);
	return track;
}
///
private void processInstruments(ref Song song, scope const ubyte[] buffer) @safe pure {
	decodeSamples(song, buffer, cast(const(ushort[2])[])(buffer[song.sampleBase .. song.sampleBase + maxSampleCount * 4]));
	song.instruments = [];
	song.instruments.reserve(maxInstruments);
	if (song.variant == Variant.prototype) {
		size_t instrumentCount = maxInstruments;
		if (song.instrumentBase < song.percussionBase) {
			instrumentCount = min(instrumentCount, (song.percussionBase - song.instrumentBase) / PrototypeInstrument.sizeof);
		}
		foreach (idx, instrument; cast(const(PrototypeInstrument)[])(buffer[song.instrumentBase .. song.instrumentBase + instrumentCount * PrototypeInstrument.sizeof])) {
			song.instruments ~= cast(Instrument)instrument;
		}
		foreach (idx, percussion; cast(const(PrototypePercussion)[])(buffer[song.percussionBase .. song.percussionBase + maxInstruments * PrototypePercussion.sizeof])) {
			song.instruments ~= cast(Instrument)percussion;
			song.percussionNotes[idx] = cast(ubyte)(percussion.note - 0x80);
		}
		song.percussionBase = instrumentCount;
	} else if (song.variant == Variant.addmusick) {
		song.instruments ~= cast(const(Instrument)[])(buffer[song.instrumentBase .. song.instrumentBase + 19 * Instrument.sizeof]);
		song.instruments.length = 30; //custom instruments start at 30
		song.instruments ~= cast(const(Instrument)[])(buffer[song.customInstruments .. song.customInstruments + (maxInstruments - 19) * Instrument.sizeof]);
		song.percussionNotes = 0x24;
	} else {
		song.instruments ~= cast(const(Instrument)[])(buffer[song.instrumentBase .. song.instrumentBase + maxInstruments * Instrument.sizeof]);
		song.percussionNotes = 0x24;
	}
	debug(nspclogging) foreach (idx, instrument; song.instruments) {
		 if ((instrument.sampleID < song.samples.length) && song.samples[instrument.sampleID].isValid && (instrument.tuning != 0)) {
			tracef("%s (%s) - %s", idx, ((song.percussionBase > 0) && (idx > song.percussionBase)) ? "Percussion" : "Standard", instrument);
		}
	}
}
///
private void decodeSamples(ref Song song, scope const ubyte[] buffer, const scope ushort[2][] ptrtable) nothrow @safe pure {
	foreach (idx, ref sample; song.samples) {
		const start = ptrtable[idx][0];
		const loop = ptrtable[idx][1];
		if (start == 0 || start == 0xffff) {
			continue;
		}
		try {
			sample = decodeSample(buffer, start, loop);
			debug(nspclogging) {
				import std.digest : toHexString;
				tracef("Sample %s: %s (Loop: %s)", idx, sample.hash.toHexString, sample.loopLength);
			}
		} catch (Exception e) {
			debug(nspclogging) tracef("Couldn't load sample %d: %s", idx, e.msg);
		}
	}
}

///
struct Pack {
	ushort size; ///
	ushort address; ///
	const(ubyte)[] data; ///
	///
	this(ushort address, const(ubyte)[] data) @safe pure {
		this.address = address;
		this.data = data;
		assert(data.length <= ushort.max + 1, format!"%s exceeds maximum size of 65536!"(data.length));
		this.size = cast(ushort)data.length;
	}
}

///
const(Pack)[] parsePacks(const(ubyte)[] input) @safe pure {
	const(Pack)[] result;
	size_t offset = 0;
	while (offset < input.length) {
		Pack pack;
		auto size = (cast(const(ushort)[])(input[offset .. offset + 2]))[0];
		if ((size == 0) || (size == 0xFFFF)) {
			break;
		}
		auto spcOffset = (cast(const(ushort)[])(input[offset + 2 .. offset + 4]))[0];
		pack.size = size;
		pack.address = spcOffset;
		pack.data = input[offset + 4 .. offset + size + 4];
		result ~= pack;
		offset += size + 4;
	}
	return result;
}
