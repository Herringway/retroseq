
import retroseq.sseq;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.conv;
import std.digest : toHexString;
import std.digest.md : md5Of;
import std.experimental.logger;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.mmfile;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.utf;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID, SDL_LockAudioDevice, SDL_UnlockAudioDevice;
import libgamefs.nintendo.ds.nds;

import retroseq.wav;
import retroseq.utility;

extern(C) int kbhit();
extern(C) int getch();

SDL_AudioDeviceID dev;
bool sdlInitialized;
bool initAudio(SDL_AudioCallback fun, ubyte channels, uint sampleRate, void* userdata = null) {
	import bindbc.sdl;

	enforce(loadSDL() == sdlSupport);
	if (SDL_Init(SDL_INIT_AUDIO) != 0) {
		criticalf("SDL init failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	SDL_AudioSpec want, have;
	want.freq = sampleRate;
	want.format = AUDIO_S16;
	want.channels = channels;
	want.samples = 512;
	want.callback = fun;
	want.userdata = userdata;
	dev = SDL_OpenAudioDevice(null, 0, &want, &have, 0);
	if (dev == 0) {
		criticalf("SDL_OpenAudioDevice failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	SDL_PauseAudioDevice(dev, 0);
	sdlInitialized = true;
	return true;
}

struct SSEQPlayer {
	Player player;
	SDAT sdat;
	Song song;
	bool stopped;
	this(const(ubyte)[] file, uint id) {
		sdat = SDAT(file);
		song = sdat.getSSEQ(id);
		player.sampleRate = 44100;
		player.Setup(song);
		player.Timer();
	}
	void stop() {
		if (sdlInitialized) {
			SDL_LockAudioDevice(dev);
		}
		stopped = true;
		player.Stop(true);
		if (sdlInitialized) {
			SDL_UnlockAudioDevice(dev);
		}
	}
	bool isPlaying() {
		if (stopped) {
			return false;
		}
		if (!player.isPlaying) {
			stop();
			return false;
		}
		return true;
	}
}

short[2][] sampleFunction(ref SSEQPlayer player, short[2][] buffer) @safe {
	scope(failure) {
		player.stopped = true;
	}
	if (player.stopped) {
		return [];
	}
	player.player.fillBuffer(buffer);
	return buffer;
}

int main(string[] args) {
	bool verbose;
	string outputFile;
	int sampleRate = 44100;
	Interpolation interpolation;

	auto help = getopt(args,
		"o|output-file", "Writes to output file instead", &outputFile,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
		"i|interpolation", "Interpolation method", &interpolation,
		"v|verbose", "Print more verbose information", &verbose,
	);
	if (help.helpWanted || (args.length < 2)) {
		defaultGetoptPrinter("SSEQ player", help.options);
		return 1;
	}
	if (verbose) {
		(cast()sharedLog).logLevel = LogLevel.trace;
	}

	auto filePath = args[1];
	const(ubyte)[] data;
	tracef("Reading file %s", filePath);
	if (auto split = filePath.findSplit("|")) {
		auto file = cast(const(ubyte)[])(new MmFile(split[0])[]);
		data = NDS(file).fileSystem[split[2]].data;
	} else {
		data = cast(const(ubyte)[])(new MmFile(args[1])[]);
		if (data[0xC0 .. 0xD0] == [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A, 0x84, 0xE4, 0x09, 0xAD]) {
			tracef("Detected NDS ROM, searching for SDAT...");
			auto rom = NDS(data);
			data = [];
			foreach (file; rom.fileSystem) {
				if (file.data.startsWith("SDAT")) {
					tracef("Found %s", file.filename);
					data = file.data;
					break;
				}
			}
			enforce(data, "No SDAT found");
		}
	}

	// initialization

	info("Loading SSEQ file");

	if (args.length == 2) {
		auto sdat = SDAT(data);
		foreach (sseq; sdat.sseqs) {
			if (verbose) {
				writefln!"%s: %s (SSEQ: %s, SBNK: %s, SWAVs: [%(%s, %)])"(sseq.id, sseq.name, toHexString(md5Of(sseq.sseqData)), toHexString(md5Of(sseq.sbnkData)), sseq.swarData[].filter!(x => x != []).map!(x => toHexString(md5Of(x))));
			} else {
				writefln!"%s: %s"(sseq.id, sseq.name);
			}
		}
		return 0;
	}
	auto player = SSEQPlayer(data, args[2].to!uint);
	player.player.interpolation = interpolation;
	// Prepare to play music
	if (outputFile != "") {
		player.player.maxLoops = 1;
		short[2][] samples;
		while (player.isPlaying) {
			short[2][4096] buffer;
			samples ~= player.sampleFunction(buffer[]);
		}
		dumpWav(samples, sampleRate, 2, outputFile);

	} else {
		if (!initAudio(&sdlSampleFunctionWrapper!sampleFunction, 2, sampleRate, &player)) {
			return 1;
		}
		info("SDL audio init success");

		infof("Now playing %s", player.song.sseq.filename);
		infof("Sequence: %s, Bank: %s, wave archives: %s", player.song.sseq.filename, player.song.sbnk.filename, player.song.swar[].filter!(x => !!x).map!(x => x.filename));

		writeln("Press enter to exit");
		while(true) {
			if (kbhit()) {
				getch(); //make sure the key press is actually consumed
				break;
			}
			if (!player.isPlaying) {
				break;
			}
		}
		player.stop();
	}
	return 0;
}
