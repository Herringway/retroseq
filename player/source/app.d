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

uint scan(uint *songTable, uint *mode){
    uint pos = 0;
    uint temp;
    while(pos < (music.length - 35)){
        if((music[pos + 0] & 0xBF) == 0x89
        && music[pos + 1] == 0x18
        && music[pos + 2] == 0x0A
        && music[pos + 3] == 0x68
        && music[pos + 4] == 0x01
        && music[pos + 5] == 0x68
        && music[pos + 6] == 0x10
        && music[pos + 7] == 0x1C
        && (music[pos + 23] & 0xFE) == 0x08){
            break;
        }
        pos += 4;
    }
    //printf("pos: 0x%x (%d)\n", pos, pos);
    if(music[pos - 61] == 0x03
    && music[pos - 57] == 0x04){
        temp = (music[pos - 45] << 24) | (music[pos - 46] << 16) | (music[pos - 47] << 8) | music[pos - 48];
    }else{
        temp = (music[pos - 61] << 24) | (music[pos - 62] << 16) | (music[pos - 63] << 8) | music[pos - 64];
    }
    *mode = temp;
    pos = (music[pos + 23] << 24) | (music[pos + 22] << 16) | (music[pos + 21] << 8) | music[pos + 20];
    pos &= 0x7FFFFFF;
    *songTable = pos;
    return pos;
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

//void sampleFunction(ref SSEQPlayer player, short[2][] buffer) @safe {
//	if (player.stopped) {
//		return;
//	}
//	player.player.GenerateSamples(buffer);
//}

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	try {
		RunMixerFrame(SOUND_INFO_PTR, cast(float[2][])buf[0 .. bufSize]);
	} catch (Throwable e) {
		assumeWontThrow(writeln(e));
	}
}
uint songTableAddress;
ubyte[] music;
uint m4aMode;
int main(string[] args) {
	int sampleRate = 48000;
	bool verbose;
	auto help = getopt(args,
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
	music = cast(ubyte[])read(filename);

	if(songTableAddress >= music.length || songTableAddress == 0) {
	    scan(&songTableAddress, &m4aMode);
	}
	infof("songTableAddress: 0x%x (%d)", songTableAddress, songTableAddress);
	infof("Max Channels: %d", (m4aMode >> 8) & 0xF);
	infof("Volume: %d", (m4aMode >> 12) & 0xF);
	infof("Original Rate: %.2fhz", getOrigSampleRate(cast(ubyte)(((m4aMode >> 16) & 0xF) - 1)) * 59.727678571);
    m4aSoundInit(sampleRate, music, songTableAddress, m4aMode);
    m4aSongNumStart(cast(ushort)song);

	// Prepare to play music
	if (!initAudio(&_sampling_func, 2, sampleRate, null)) {
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
