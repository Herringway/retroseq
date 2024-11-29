import m4a;
import m4a.m4a;
import m4a.sound_mixer;

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

void scan(const ubyte[] music, int tablesToSkip, out uint songTable, out uint mode) @safe {
	uint pos = 0;
	uint temp;
	while(pos < (music.length - 35)){
		if((music[pos + 0] & 0xBF) == 0x89
		&& music[pos + 1 .. pos + 8] == [ 0x18, 0x0A, 0x68, 0x01, 0x68, 0x10, 0x1C]
		&& (music[pos + 23] & 0xFE) == 0x08) {
			if (tablesToSkip-- == 0) {
				break;
			}
		}
		pos += 4;
	}
	if(music[pos - 61] == 0x03 && music[pos - 57] == 0x04) {
		temp = (cast(const(uint)[])music[pos - 48 .. pos - 44])[0];
		debug tracef("found mode val at %08X: %08X", pos - 48 + 0x8000000, temp);
	}else{
		temp = (cast(const(uint)[])music[pos - 64 .. pos - 60])[0];
		debug tracef("found mode val at %08X: %08X", pos - 64 + 0x8000000, temp);
	}
	mode = temp;
	tracef("Found signature at %08X", pos);
	pos = (music[pos + 23] << 24) | (music[pos + 22] << 16) | (music[pos + 21] << 8) | music[pos + 20];
	pos &= 0x7FFFFFF;
	songTable = pos;
}

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
	want.format = AUDIO_F32;
	want.channels = channels;
	want.samples = cast(ushort)((sampleRate / 60.0) + 0.5);
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

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	static bool done;
	if (done) {
		return;
	}
	try {
		RunMixerFrame(*cast(M4APlayer*)user, cast(float[2][])buf[0 .. bufSize]);
	} catch (Throwable e) {
		assumeWontThrow(writeln(e));
		done = true;
	}
}
int main(string[] args) {
	int sampleRate = 48000;
	uint songTableAddress;
	uint m4aMode;
	string m4aModeOverride;
	const(ubyte)[] music;
	int tablesToSkip = 0;
	bool verbose;
	auto help = getopt(args,
		"t|table", "Song Table ID (0 by default)", &tablesToSkip,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
		"m|mode", "Override mode value", &m4aModeOverride,
		"v|verbose", "Print more verbose information", &verbose,
	);
	if (help.helpWanted || (args.length < 3)) {
		defaultGetoptPrinter("SSEQ player", help.options);
		return 1;
	}
	if (verbose) {
		(cast()sharedLog).logLevel = LogLevel.trace;
	}

	auto filename = args[1];
	auto song = args[2].to!int;
	if (args.length > 3) {
		songTableAddress = args[3].to!uint(16);
	}
	music = cast(const(ubyte)[])read(filename);

	if(songTableAddress >= music.length || songTableAddress == 0) {
		scan(music, tablesToSkip, songTableAddress, m4aMode);
	}
	if (m4aModeOverride != "") {
		m4aMode = m4aModeOverride.to!uint(16);
	}
	if (songTableAddress == 0) {
		stderr.writeln("No song table found");
		return 2;
	}
	infof("songTableAddress: 0x%x (%d)", songTableAddress, songTableAddress);
	infof("Mode: %d", m4aMode);
	infof("Max Channels: %d", (m4aMode >> 8) & 0xF);
	infof("Volume: %d", (m4aMode >> 12) & 0xF);
	infof("Original Rate: %.2fhz", getOrigSampleRate(cast(ubyte)(((m4aMode >> 16) & 0xF) - 1)) * 59.727678571);
	M4APlayer player;
	player.initialize(sampleRate, music, songTableAddress, m4aMode);
	player.songNumStart(cast(ushort)song);

	// Prepare to play music
	if (!initAudio(&_sampling_func, 2, sampleRate, &player)) {
		return 1;
	}
	info("SDL audio init success");

	writeln("Press enter to exit");
	while(true) {
		if (kbhit()) {
			if (getch() == 224) {
				const arrow = getch();
				if (arrow == 72) {
					song++;
				} else if (arrow == 80) {
					song--;
				} else {
					break;
				}
				infof("Now playing %s", song);
				player.m4aSongNumStartOrChange(cast(ushort)song);
			} else {
				break;
			}
		}
	}

	return 0;
}
