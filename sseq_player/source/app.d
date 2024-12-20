
import sseq;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.conv;
import std.digest : toHexString;
import std.experimental.logger;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.utf;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID;
import libgamefs.nintendo.ds.nds;

extern(C) int kbhit();
extern(C) int getch();

bool initAudio(SDL_AudioCallback fun, ubyte channels, uint sampleRate, void* userdata = null) {
	SDL_AudioDeviceID dev;
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
		stopped = true;
		player.Stop(true);
	}
	bool isPlaying() {
		return !stopped;
	}
}

void sampleFunction(ref SSEQPlayer player, short[2][] buffer) @safe {
	if (player.stopped) {
		return;
	}
	player.player.GenerateSamples(buffer);
}

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	try {
		sampleFunction(*cast(SSEQPlayer*)user, cast(short[2][])buf[0 .. bufSize]);
	} catch (Throwable e) {
		assumeWontThrow(writeln(e));
		(cast(SSEQPlayer*)user).stopped = true;
	}
}

int main(string[] args) {
	bool verbose;
	int sampleRate = 44100;
	Interpolation interpolation;

	auto help = getopt(args,
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
		data = NDS(cast(ubyte[])read(split[0])).fileSystem[split[2]].data;
	} else {
		data = cast(ubyte[])read(args[1]);
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
			infof("%s: %s", sseq.id, sseq.name);
		}
		return 0;
	}
	auto player = SSEQPlayer(data, args[2].to!uint);
	player.player.interpolation = interpolation;
	// Prepare to play music
	if (!initAudio(&_sampling_func, 2, sampleRate, &player)) {
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

	return 0;
}
