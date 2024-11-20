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

void scan(int tablesToSkip, out uint songTable, out uint mode) @safe {
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
        temp = (cast(uint[])music[pos - 48 .. pos - 44])[0];
    }else{
        temp = (cast(uint[])music[pos - 64 .. pos - 60])[0];
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

//void sampleFunction(ref SSEQPlayer player, short[2][] buffer) @safe {
//	if (player.stopped) {
//		return;
//	}
//	player.player.GenerateSamples(buffer);
//}

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	try {
		RunMixerFrame(cast(M4APlayer*)user, cast(float[2][])buf[0 .. bufSize]);
	} catch (Throwable e) {
		assumeWontThrow(writeln(e));
	}
}
uint songTableAddress;
ubyte[] music;
uint m4aMode;
int main(string[] args) {
	int sampleRate = 48000;
	int tablesToSkip = 0;
	bool verbose;
	auto help = getopt(args,
		"t|table", "Song Table ID (0 by default)", &tablesToSkip,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
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
	music = cast(ubyte[])read(filename);

	if(songTableAddress >= music.length || songTableAddress == 0) {
	    scan(tablesToSkip, songTableAddress, m4aMode);
	}
	if (songTableAddress == 0) {
		stderr.writeln("No song table found");
		return 2;
	}
	infof("songTableAddress: 0x%x (%d)", songTableAddress, songTableAddress);
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
	//Interpolation interpolation;

	//// initialization

	//info("Loading SSEQ file");

	//if (args.length == 2) {
	//	auto pFile = PseudoFile(file);
	//	auto sdat = SDAT(pFile);
	//	foreach (sseq; sdat.sseqs) {
	//		infof("%s: %s", sseq.id, sseq.name);
	//	}
	//	return 0;
	//}
	//auto player = SSEQPlayer(file, args[2].to!uint);
	//player.player.interpolation = interpolation;
	info("SDL audio init success");

	//infof("Now playing %s", player.song.sseq.filename);
	//infof("Sequence: %s, Bank: %s, wave archives: %s", player.song.sseq.filename, player.song.sbnk.filename, player.song.swar[].filter!(x => !!x).map!(x => x.filename));

	writeln("Press enter to exit");
	while(true) {
		if (kbhit()) {
			getch(); //make sure the key press is actually consumed
			break;
		}
		//if (!player.isPlaying) {
		//	break;
		//}
	}
	//player.stop();

	return 0;
}
