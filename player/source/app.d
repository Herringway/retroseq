
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
	want.format = SDL_AudioFormat.AUDIO_S16;
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
	double secondsPerSample;
	double secondsIntoPlayback;
	double secondsUntilNextClock;
	bool stopped;
	this(ubyte[] file, uint id) {
		auto pFile = PseudoFile(file);

		sdat = SDAT(pFile);
		song = sdat.getSSEQ(pFile, id);
		player.sampleRate = 44100;
		player.Setup(song.sseq);
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

	auto help = getopt(args,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
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
	auto file = cast(ubyte[])read(args[1]);

	// initialization

	info("Loading SSEQ file");

	auto data = cast(ubyte[])read(args[1]);
	if (args.length == 2) {
		auto pFile = PseudoFile(file);
		auto sdat = SDAT(pFile);
		foreach (sseq; sdat.sseqs) {
			infof("%s: %s", sseq.id, sseq.name);
		}
		return 0;
	}
	auto player = SSEQPlayer(data, args[2].to!uint);
	// Prepare to play music
	if (!initAudio(&_sampling_func, 2, sampleRate, &player)) {
		return 1;
	}
	info("SDL audio init success");

	infof("Now playing %s", player.song.sseq.filename);

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
