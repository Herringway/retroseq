import retroseq.m4a;
import retroseq.nspc;
import retroseq.organya;
import retroseq.piyopiyo;
import retroseq.pxtone;
import retroseq.sseq;
import retroseq.wav;

import core.time;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.array;
import std.conv;
import std.exception;
import std.digest : toHexString;
import std.file;
import std.format;
import std.getopt;
import std.logger;
import std.mmfile;
import std.path;
import std.stdio;
import std.string;
import std.sumtype;
import std.typecons;
import std.utf;

import bindbc.loader;
import bindbc.sdl;
import libgamefs.nintendo.ds.nds;

extern(C) int kbhit();
extern(C) int getch();

void m4aScan(const(ubyte)[] music, out uint songTable, out uint mode) @safe {
	static bool matchesM4ASongNumStartSignature(const(ubyte)[] data) => ((data[20] & 0xBF) == 0x89) && (data[21 .. 28] == [ 0x18, 0x0A, 0x68, 0x01, 0x68, 0x10, 0x1C ]) && ((data[43] & 0xFE) == 0x08);
	static bool matchesM4ASoundInitSignature(const(ubyte)[] data) => (data[0 .. 2] == [0x70, 0xB5]) && (data[3 .. 11] == [ 0x48, 0x02, 0x21, 0x49, 0x42, 0x08, 0x40, 0x13 ]);
	static bool matchesM4ASoundInitSignatureOld(const(ubyte)[] data) => (data[0 .. 2] == [0xF0, 0xB5]) && (data[7 .. 15] == [ 0x48, 0x02, 0x21, 0x49, 0x42, 0x08, 0x40, 0x17 ]);
    uint pos = 0;
    bool foundM4ASongNumStart;
    bool foundM4ASoundInit;
    void useM4ASoundInitAt(uint location) {
		tracef("Found mode at %08X", location);
    	mode = (cast(const(uint)[])music[location .. location + 4])[0];
    	foundM4ASoundInit = true;
		tracef("Mode %08X", mode);
    }
    while (pos < (music.length - 35)) {
    	if (matchesM4ASoundInitSignature(music[pos .. $])) {
			tracef("Found m4aSoundInit at %08X", pos);
    		useM4ASoundInitAt(pos + 0x1E + 2 + (music[pos + 0x1E]) * 4);
    	}
    	if (matchesM4ASoundInitSignatureOld(music[pos .. $])) {
			tracef("Found m4aSoundInit (old) at %08X", pos);
    		useM4ASoundInitAt(pos + 0x22 + 2 + (music[pos + 0x22]) * 4);
    	}
        if (matchesM4ASongNumStartSignature(music[pos .. $])) {
			tracef("Found m4aSongNumStart at %08X", pos);
			const loc = pos + 6 + 2 + (music[pos + 6]) * 4;
			tracef("Found songTable at %08X", loc);
    		songTable = (cast(const(uint)[])music[loc .. loc + 4])[0] & 0x7FFFFFF;
        	foundM4ASongNumStart = true;
			tracef("SongTable %08X", songTable);
            break;
        }
        pos += 4;
    }
    enforce(foundM4ASongNumStart, "Could not find song table");
    enforce(foundM4ASoundInit, "Could not find mode");
}

bool initAudio(SDL_AudioStreamCallback fun, SDL_AudioFormat format, ubyte channels, uint sampleRate, void* userdata = null) {
	import bindbc.sdl;
	auto loadedSDL = loadSDL();
	enforce(loadedSDL != LoadMsg.noLibrary, "Missing library");
	//enforce(loadedSDL != LoadMsg.badLibrary, "Bad library");
	if (SDL_Init(SDL_INIT_AUDIO) == 0) {
		criticalf("SDL init failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	const spec = SDL_AudioSpec(format: format, channels: channels, freq: sampleRate);
	auto stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, fun, userdata);
	if (stream == null) {
		criticalf("SDL_OpenAudioDeviceStream failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	SDL_ResumeAudioDevice(SDL_GetAudioStreamDevice(stream));
	return true;
}

interface Player {
	void playNewSong(size_t song);
	void printSong(size_t song);
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe;
	bool isValid(size_t song);
	const(char)[] getSongLabel() const @safe;
	SDL_AudioFormat sampleFormat() const nothrow @safe;
	size_t getSongCount() const @safe;
	void listSongs() const @safe;
	void setSpeed(double) @safe;
	void seekTo(Duration) @safe;
	void enableLooping(bool) @safe;
	bool isPlaying() const @safe;
	void printSongInfo() const @safe;
	void disableChannel(uint channel) @safe;
}

class OrganyaPlayerClass : Player {
	OrganyaNoMixer player;
	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		player.initialize(sampleRate, interpolation);
		player.loadSong(createSong(file));
		player.playMusic();
	}
	size_t getSongCount() const @safe => 1;
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		player.fillBuffer(buffer);
		return buffer;
	}
	bool isValid(size_t song) => true;
	void printSong(size_t song) {
		foreach (idx, track; player.info.trackData) {
			if (track.waveNumber == 0) {
				continue;
			}
			writefln!"Track %s - Instrument %s"(idx, track.waveNumber);
		}
	}
	void playNewSong(size_t song) {}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_S16;
	void listSongs() const @safe {}
	void setSpeed(double) @safe {}
	void seekTo(Duration) @safe {}
	void enableLooping(bool) @safe => throw new Exception("Not supported");
	bool isPlaying() const @safe => true;
	void printSongInfo() const @safe {}
	void disableChannel(uint channel) @safe {}
	const(char)[] getSongLabel() const @safe => "";
}
class PiyoPiyoPlayerClass : Player {
	PiyoPiyoNoMixer player;
	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		player.initialize(sampleRate, interpolation);
		player.loadMusic(file);
		player.play();
	}
	size_t getSongCount() const @safe => 1;
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		player.fillBuffer(buffer);
		return buffer;
	}
	bool isValid(size_t song) => true;
	void printSong(size_t song) {}
	void playNewSong(size_t song) {}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_S16;
	void listSongs() const @safe {}
	void setSpeed(double) @safe {}
	void seekTo(Duration) @safe {}
	void enableLooping(bool) @safe => throw new Exception("Not supported");
	bool isPlaying() const @safe => true;
	void printSongInfo() const @safe {}
	void disableChannel(uint channel) @safe {}
	const(char)[] getSongLabel() const @safe => "";
}
class PxtonePlayerClass : Player {
	PxtnService pxtn;
	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		// pxtone initialization
		trace("Initializing pxtone");
		pxtn.initialize();
		trace("Setting quality");
		pxtn.setDestinationQuality(channels, sampleRate);

		trace("Loading ptcop");
		// Load file
		auto song = PxToneSong(cast(ubyte[])file);
		pxtn.load(song);

		trace("Preparing pxtone");
		// Prepare to play music

		pxtn.mooPreparation();
		//writefln!"file: %s"(filePath.baseName);
		writefln!"name: %s"(song.text.getNameBuf());
		writefln!"comment: %s"(song.text.getCommentBuf());

		debug foreach (voice; 0 .. pxtn.woiceNum()) {
			import std.algorithm : map;
			import std.range : iota;
			auto woice = pxtn.woiceGet(voice);
			writefln!"Voice %d \"%s\": %s - %s"(voice, woice.getNameBuf(), woice.getType(), iota(woice.getVoiceNum()).map!(x => woice.getVoice(x).type));
		}
	}
	size_t getSongCount() const @safe => 1;
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		pxtn.moo(cast(short[])buffer);
		return buffer;
	}
	bool isValid(size_t song) => true;
	void printSong(size_t song) {}
	void playNewSong(size_t song) {}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_S16;
	void listSongs() const @safe {}
	void setSpeed(double) @safe {}
	void seekTo(Duration) @safe {}
	void enableLooping(bool) @safe => throw new Exception("Not supported");
	bool isPlaying() const @safe => true;
	void printSongInfo() const @safe {}
	void disableChannel(uint channel) @safe {}
	const(char)[] getSongLabel() const @safe => "";
}
class NSPCPlayerClass : Player {
	NSPCPlayer nspc;
	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		this(loadNSPCFile(file, []), channels, sampleRate, interpolation);
	}
	this(const(retroseq.nspc.song.Song)[] songs, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		nspc = NSPCPlayer(sampleRate);
		trace("Loading NSPC file");
		// Load files
		//ushort[] phrases;
		//foreach (phrasePortion; phraseString.splitter(",")) {
		//	phrases ~= phrasePortion.to!ushort(16);
		//}
		nspc.loadSongs(songs);

		//nspc.interpolation = interpolation;
		//if (replaceSamples != "") {
		//	foreach(idx, sample; song.getSamples) {
		//		const glob = format!"%s.brr.wav"(sample.hash.toHexString);
		//		auto matched = dirEntries(replaceSamples, glob, SpanMode.shallow);
		//		if (!matched.empty) {
					//int newLoop;
					//uint loopEnd;
					//short[] newSample;
					//auto data = cast(ubyte[])read(matched.front.name);
					//auto riffFile = RIFFFile(data);
					//bool validated;
					//bool downMix;
					//foreach (chunk; riffFile.chunks) {
					//	if (chunk.fourCC == "fmt ") {
					//		const wavHeader = readWaveHeader(chunk.data);
					//		if (wavHeader.channels == 2) {
					//			downMix = true;
					//		} else if (wavHeader.channels == 1) {
					//		} else {
					//			errorf("Sample must be mono or stereo!");
					//			continue;
					//		}
					//		if (wavHeader.bitsPerSample != 16){
					//			errorf("Sample must be 16-bit!");
					//			continue;
					//		}
					//		validated = true;
					//	}
					//	if (chunk.fourCC == "smpl") {
					//		auto smpl = readSampleChunk(chunk.data);
					//		foreach (loop; smpl.loops) {
					//			if (loop.type != 0) {
					//				warningf("Ignoring unsupported loop type %s", loop.type);
					//				continue;
					//			}
					//			newLoop = loop.end - loop.start;
					//			loopEnd = loop.end;
					//		}
					//	}
					//	if (chunk.fourCC == "data") {
					//		newSample = cast(short[])chunk.data;
					//		if (downMix) {
					//			const old = newSample;
					//			newSample = newSample[0 .. $ / 2];
					//			foreach (sampleIndex, chanSamples; old.chunks(2).enumerate) {
					//				newSample[sampleIndex] = cast(short)((chanSamples[0] + chanSamples[1]) / 2);
					//			}
					//		}
					//	}
					//}
					//if (!validated) {
					//	infof("Skipping invalid sample %s", matched.front.name);
					//	continue;
					//}
					//if ((newLoop != 0) && (loopEnd != newSample.length)) {
					//	warningf("Loop end (%s) != sample count (%s), unexpected results may occur!", loopEnd, newSample.length);
					//}
					//infof("Replacing sample with %s", matched.front.name);
					//song.replaceSample(idx, newSample, newLoop);
		//		}
		//	}
		//}
	}
	size_t getSongCount() const @safe => nspc.loadedSongs.length;
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		return nspc.fillBuffer(buffer);
	}
	bool isValid(size_t song) => true;
	void printSong(size_t songID) {
		writeln("Instruments:");
		const song = nspc.loadedSongs[songID];
		foreach (idx, instrument; song.instruments) {
			if ((instrument.sampleID < song.samples.length) && song.samples[instrument.sampleID].isValid && (instrument.tuning != 0)) {
				const sample = song.samples[instrument.sampleID];
				writef!"%s (%s) - Sample: %s (%s, samples: %s, "(idx, ((song.percussionBase > 0) && (idx > song.percussionBase)) ? "Percussion" : "Standard", instrument.sampleID, sample.hash.toHexString, sample.data.length);
				if (sample.loopLength) {
					writef!"Loop: %s-%s"(sample.loopLength, sample.data.length);
				} else {
					write("No loop");
				}
				writefln!"), ADSR/Gain: %s, tuning: %s"(instrument.adsrGain, instrument.tuning);
			}
		}
		writeln("Sequence:");
		writeln(song);
	}
	void playNewSong(size_t idx) {
		nspc.changeTrack(idx);
		nspc.play();
	}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_S16;
	void listSongs() const @safe {
		foreach (idx, song; nspc.loadedSongs) {
			if (song.tags) {
				const(char)[] album;
				const(char)[] title;
				auto albumTag = song.tags.find!(x => x.key == "album")();
				if (!albumTag.empty) {
					album = albumTag.front.str;
				}
				auto titleTag = song.tags.find!(x => x.key == "title")();
				if (!titleTag.empty) {
					title = titleTag.front.str;
				}
				infof("%s: %s - %s", idx, album, title);
			}
		}
	}
	void setSpeed(double value) @safe {
		nspc.setSpeed(cast(ushort)(500 * value));
	}
	void seekTo(Duration duration) @safe {
		//nspc.seek(duration, SeekStyle.relative);
	}
	void enableLooping(bool enabled) @safe {
		nspc.looping = enabled;
	}
	bool isPlaying() const @safe => nspc.isPlaying;
	void printSongInfo() const @safe {
		writefln!"Variant: %s"(nspc.currentSong.variant);
		writefln!"Sequence: %04X"(nspc.currentSong.songBase);
		writefln!"Instruments: %04X"(nspc.currentSong.instrumentBase);
		writefln!"Samples: %04X"(nspc.currentSong.sampleBase);
		if (nspc.currentSong.customInstruments) {
			writefln!"Custom Instruments: %04X"(nspc.currentSong.customInstruments);
		}
		writeln("Packs used:");
		foreach (pack; nspc.currentSong.packs) {
			writefln!"\t%04X: %s bytes"(pack.address, pack.data.length);
		}
		writefln!"Current phrase: %s"(nspc.currentSong.order[nspc.state.phraseCounter]);
		foreach (idx, channel; nspc.state.channels) {
			writefln!"Channel %s: Instrument %s, %s"(idx, channel.instrument, ["Disabled", "Enabled"][channel.enabled]);

		}
	}
	void disableChannel(uint channel) @safe {
		nspc.setChannelEnabled(cast(ubyte)channel, false);
	}
	const(char)[] getSongLabel() const @safe {
		if (nspc.currentSong.tags) {
			const(char)[] album;
			const(char)[] title;
			auto albumTag = nspc.currentSong.tags.find!(x => x.key == "album")();
			if (!albumTag.empty) {
				album = albumTag.front.str;
			}
			auto titleTag = nspc.currentSong.tags.find!(x => x.key == "title")();
			if (!titleTag.empty) {
				title = titleTag.front.str;
			}
			return format!"%s - %s"(album, title);
		}
		return "";
	}
}
class M4APlayerClass : Player {
	M4APlayer m4a;
	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		uint songTableAddress;
		uint m4aMode;
		m4aScan(file, songTableAddress, m4aMode);
		m4a.initialize(sampleRate, file, songTableAddress, m4aMode);
	}
	size_t getSongCount() const @safe {
		size_t lastValid;
		foreach (track, _; m4a.songTable[0 .. min($, 0xFFFF)]) {
			if (m4a.isValidSong(cast(ushort)track)) {
				lastValid = track;
			}
		}
		return lastValid;
	}
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		try {
			m4a.fillBuffer(cast(float[2][])buffer);
		} catch (Exception e) {
			debug infof("UNHANDLED EXCEPTION: %s", e);
			assert(0);
		}
		return buffer;
	}
	bool isValid(size_t song) {
		return m4a.isValidSong(cast(ushort)song);
	}
	void printSong(size_t song) {}
	void playNewSong(size_t song) {
		m4a.m4aSongNumStartOrChange(cast(ushort)song);
	}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_F32;
	void listSongs() const @safe {
		infof("%s unnamed songs.", getSongCount());
	}
	void setSpeed(double value) @safe {
		m4a.m4aMPlayTempoControl(cast(ushort)(value * 256));
	}
	void seekTo(Duration duration) @safe {}
	void enableLooping(bool enabled) @safe {
		if (enabled) {
			m4a.loops.nullify();
		} else {
			m4a.loops = 0;
			m4a.endFadeSpeed = 30;
		}
	}
	bool isPlaying() const @safe => !m4a.paused;
	void printSongInfo() const @safe {
		writefln!"Song table: 0x%x"(m4a.songTableOffset);
		writefln!"Max channels: %d"(m4a.soundInfo.numChans);
		writefln!"Volume: %.1f%%"((m4a.soundInfo.masterVol / 15.0) * 100.0);
		writefln!"Original sample rate: %.2fhz"(getOrigSampleRate(m4a.soundInfo.freq) * 59.727678571);
		foreach (idx, channel; m4a.soundInfo.allChannels) {
			if (!channel.isActive) {
				continue;
			}
			writef!"Track %s "(idx);
			if (channel.type.cgbType == 0) {
				writefln!"(directsound)"();
			} else {
				writefln!"(gb %s)"(["pulse 1", "pulse 2", "wave", "noise"][channel.type.cgbType - 1]);
			}
		}
	}
	void disableChannel(uint channel) @safe {}
	const(char)[] getSongLabel() const @safe => "";
}
class SSEQPlayerClass : Player {
	retroseq.sseq.player.Player player;
	SDAT sdat;
	retroseq.sseq.sdat.Song song;
	bool stopped;

	this(const(ubyte)[] file, ushort channels, uint sampleRate, InterpolationMethod interpolation) {
		sdat = SDAT(file);
		player.sampleRate = cast(ushort)sampleRate;
		//player.player.interpolation = interpolation;
	}
	size_t getSongCount() const @safe => sdat.sseqs.length;
	short[2][] fillBuffer(short[2][] buffer) nothrow @safe {
		if (stopped) {
			return [];
		}
		try {
			player.fillBuffer(buffer);
			return buffer;
		} catch (Exception) {
			assert(0);
		}
	}
	bool isValid(size_t song) {
		return sdat.isValid(cast(uint)song);
	}
	void printSong(size_t song) {}
	void playNewSong(size_t newSong) {
		play(cast(uint)newSong);
	}
	SDL_AudioFormat sampleFormat() const nothrow @safe => SDL_AUDIO_S16;
	void listSongs() const @trusted {
		foreach (sseq; sdat.sseqs) {
			infof("%s: %s", sseq.id, sseq.name);
		}
	}
	void setSpeed(double value) @safe {}
	void seekTo(Duration duration) @safe {}
	void enableLooping(bool enabled) @safe => throw new Exception("Not supported");
	bool isPlaying() const @safe => true;
	void printSongInfo() const @safe {
		writefln!"Now playing: %s, Bank: %s, wave archives: %s"(song.sseq.filename, song.sbnk.filename, song.swar[].filter!(x => !!x).map!(x => x.filename));
	}
	void play(uint id) {
		stop();
		song = sdat.getSSEQ(id);
		player.Setup(song);
		player.Timer();
		stopped = false;
	}
	void stop() {
		stopped = true;
		player.Stop(true);
	}
	bool isPlaying() {
		return !stopped;
	}
	void disableChannel(uint channel) @safe {}
	const(char)[] getSongLabel() const @safe => song.sseq.filename;
}

__gshared bool playing = true;
extern (C) void _sampling_func(void* user, SDL_AudioStream* stream, int additional, int total) nothrow {
	ubyte[] buffer;
	static ubyte[0x10000] staticBuffer;
	if (!playing) {
		return;
	}
	if (additional > 0) {
		buffer = staticBuffer[0 .. additional];
	}
	try {
		auto payload = cast(Player)cast(void*)user;
		payload.fillBuffer(cast(short[2][])buffer);
	} catch (Throwable e) {
		debug errorf("%s", e);
		playing = false;
	}
	if (buffer.length) {
		SDL_PutAudioStreamData(stream, &buffer[0], cast(int)buffer.length);
	}
}

SongType detectType(string filename, const(ubyte)[] data) {
	if (filename.extension.among(".sfc", ".smc")) {
		return SongType.snes;
	}
	if (filename.extension == ".nspc") {
		return SongType.nspc;
	}
	if ((data.length > 33) && (data[0 .. 33] == "SNES-SPC700 Sound File Data v0.30")) {
		return SongType.spc;
	}
	if (PxToneSong.detect(cast(ubyte[])data)) {
		return SongType.pxtone;
	}
	if (data[0 .. 5]  == "Org-0") {
		return SongType.organya;
	}
	if (data[0 .. 3]  == "PMD") {
		return SongType.piyopiyo;
	}
	if (data[0 .. 8]  == NSPC2FileHeader.init.magic) {
		return SongType.nspc;
	}
	if ((data.length > 4) && (data[0 .. 4] == "SDAT")) {
		return SongType.sseq;
	}
	if (data[0xC0 .. 0xD0] == [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A, 0x84, 0xE4, 0x09, 0xAD]) {
		return SongType.nds;
	}
	if ((data.length > 228) && (data[4 .. 20] == [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A, 0x84, 0xE4, 0x09, 0xAD])) {
		return SongType.m4a;
	}
	throw new Exception("Unknown filetype!");
}

enum SongType {
	pxtone,
	piyopiyo,
	organya,
	snes,
	nspc,
	spc,
	sseq,
	nds,
	m4a,
}
__gshared int midiChannel = 0;

const(retroseq.nspc.song.Song)[] snesToNSPC2(const(ubyte)[] data) @safe pure {
	return loadNSPC2File(extractROM(data));
}


int main(string[] args) {
	enum channels = 2;
	bool verbose;
	int sampleRate = 48000;
	double speed = 1.0;
	string outfile;
	string replaceSamples;
	bool listSongs;
	bool dumpBRRFiles;
	string phraseString;
	uint[] disabledChannels;
	//Interpolation interpolation;
	InterpolationMethod interpolation;
	uint midiDevice = uint.max;
	auto help = getopt(args,
		"d|disable-channels", "Disables channels", &disabledChannels,
		//"m|mididevice", "Opens a midi device for input", &midiDevice,
		//"q|midichannel", "MIDI channel offset for midi device", &midiChannel,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
		//"i|interpolation", "Sets interpolation (linear, gaussian, sinc, cubic)", &interpolation,
		//"b|brrdump", "Dumps BRR samples used", &dumpBRRFiles,
		"o|outfile", "Dumps output to file", &outfile,
		//"r|replacesamples", "Replaces built-in samples with samples found in directory", &replaceSamples,
		"v|verbose", "Print more verbose information", &verbose,
		//"z|phrases", "Override phrase list with custom one", &phraseString,
		"s|speed", "Sets playback speed (500 is default)", &speed,
		"l|list", "List songs in file", &listSongs
	);
	if ((args.length < 2) || help.helpWanted) {
		defaultGetoptPrinter("Retroseq player (organya, piyopiyo, pxtone, NSPC, SSEQ, M4A)", help.options);
		return 1;
	}
	if (verbose) {
		(cast()sharedLog).logLevel = LogLevel.trace;
	}
	tracef("Loading file");

	auto filePath = args[1];
	scope fileHandle = new MmFile(args[1]);
	auto file = cast(const(ubyte)[])fileHandle[];
	Nullable!uint subSong;
	if (args.length == 3) {
		subSong = args[2].to!uint;
	}

	Player player;
	auto type = detectType(filePath, file);
	infof("Detected type: %s", type);

	size_t playingSong = subSong.get(0);

	final switch (type) {
		case SongType.pxtone:
			player = new PxtonePlayerClass(file, channels, sampleRate, interpolation);
			break;
		case SongType.piyopiyo:
			player = new PiyoPiyoPlayerClass(file, channels, sampleRate, interpolation);
			break;
		case SongType.organya:
			player = new OrganyaPlayerClass(file, channels, sampleRate, interpolation);
			break;
		case SongType.snes:
			player = new NSPCPlayerClass(snesToNSPC2(file), channels, sampleRate, interpolation);
			break;
		case SongType.spc:
			player = new NSPCPlayerClass([loadSPCFile(file)], channels, sampleRate, interpolation);
			break;
		case SongType.nspc:
			player = new NSPCPlayerClass(file, channels, sampleRate, interpolation);
			break;
		case SongType.nds:
			auto rom = NDS(file);
			file = [];
			foreach (romfile; rom.fileSystem) {
				if (romfile.data.startsWith("SDAT")) {
					tracef("Found %s", romfile.filename);
					file = romfile.data;
					break;
				}
			}
			if (!file.length) {
				errorf("No songs found");
				return 1;
			}
			goto case;
		case SongType.sseq:
			player = new SSEQPlayerClass(file, channels, sampleRate, interpolation);
			break;
		case SongType.m4a:
			player = new M4APlayerClass(file, channels, sampleRate, interpolation);
			break;
	}
	player.setSpeed(speed);
	size_t songCount = player.getSongCount();
	if (listSongs) {
		player.listSongs();
		return 0;
	}
	if (songCount < 1) {
		stderr.writeln("No songs loaded");
		return 1;
	}
	if (outfile != "") {
		player.playNewSong(playingSong);
		foreach (channel; disabledChannels) {
			player.disableChannel(channel);
		}
		player.enableLooping(false);
		if (player.sampleFormat() == SDL_AUDIO_S16) {
			short[2][] samples;
			while (player.isPlaying) {
				short[2][4096] buffer;
				samples ~= player.fillBuffer(buffer[]);
			}
			dumpWav(samples, sampleRate, 2, outfile);
		} else {
			float[2][] samplesTmp;
			while (player.isPlaying) {
				float[2][4096] buffer;
				samplesTmp ~= cast(float[2][])player.fillBuffer(cast(short[2][])buffer[]);
			}
			short[2][] samples = samplesTmp.map!(x => cast(short[2])[cast(short)(x[0] * short.max), cast(short)(x[1] * short.max)]).array;
			dumpWav(samples, sampleRate, 2, outfile);
		}
		return 0;
	}
	bool playingNewSong = true;
	if (!initAudio(&_sampling_func, player.sampleFormat, channels, sampleRate, cast(void*)player)) {
		return 1;
	}
	trace("SDL audio init success");

	writeln("Arrow keys to play different subsong, I to print song info, P to print song, anything else to exit");
	static size_t findNearestSong(Player player, size_t initial, size_t songCount, bool increasing) {
		auto result = initial;
		bool hitLimit;
		while(!player.isValid(result)) {
			result += increasing ? 1 : -1;
			if ((result >= songCount) || (result == 0)) {
				if (hitLimit) {
					infof("Could not find a valid song");
					break;
				}
				hitLimit = true;
				increasing = !increasing;
			}
		}
		return result;
	}
	playingSong = findNearestSong(player, playingSong, songCount, true);
	playLoop: while(true) {
		if (playingNewSong) {
			player.playNewSong(playingSong);
			const songLabel = player.getSongLabel();
			infof("Now playing song %s/%s%s%s", playingSong + 1, songCount, songLabel.length ? " - " : "", songLabel);
			foreach (channel; disabledChannels) {
				player.disableChannel(channel);
			}
			playingNewSong = false;
		}
		const c = getch();
		switch(c) {
			case 224: // arrow key
				const arrow = getch();
				const currentSong = playingSong;
				bool increasing;
				if (arrow == 72) { // up
					playingSong++;
					increasing = true;
				} else if (arrow == 75) { // left
					playingSong -= min(playingSong, 10);
				} else if (arrow == 77) { // right
					playingSong += 10;
					increasing = true;
				} else if (arrow == 80) { // down
					playingSong--;
				} else {
					break;
				}
				playingSong = findNearestSong(player, playingSong, songCount, increasing);
				playingSong = min(playingSong, songCount - 1);
				playingNewSong = currentSong != playingSong;
				break;
			case 112: // p
				player.printSong(playingSong);
				break;
			case 105: // i
				player.printSongInfo();
				break;
			case 61:
			case 45:
			default:
				tracef("key %s pressed, exiting", c);
				break playLoop;
		}
	}

	return 0;
}
