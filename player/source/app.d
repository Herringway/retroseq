import nspc;

import std.algorithm.comparison;
import std.conv;
import std.experimental.logger;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.path;
import std.stdio;
import std.string;
import std.utf;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID;

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

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	NSPCPlayer* nspc = cast(NSPCPlayer*) user;
	try {
		nspc.fillBuffer(cast(short[2][])(buf[0 .. bufSize]));
	} catch (Error e) {
		assumeWontThrow(writeln(e));
		throw e;
	}
}

int main(string[] args) {
	enum channels = 2;
	bool verbose;
	int sampleRate = 44100;
	ushort speed = NSPCPlayer.defaultSpeed;
	string outfile;
	bool dumpBRRFiles;
	if (args.length < 2) {
		return 1;
	}

	auto help = getopt(args,
		"f|samplerate", "Sets sample rate (Hz)", &sampleRate,
		"b|brrdump", "Dumps BRR samples used", &dumpBRRFiles,
		"o|outfile", "Dumps output to file", &outfile,
		"v|verbose", "Print more verbose information", &verbose,
		"s|speed", "Sets playback speed (500 is default)", &speed);
	if (help.helpWanted) {
		defaultGetoptPrinter("NSPC player", help.options);
		return 1;
	}
	if (verbose) {
		sharedLog = new FileLogger(stdout, LogLevel.trace);
	}

	auto filePath = args[1];
	auto file = cast(ubyte[])read(args[1]);

	NSPCPlayer nspc;
	// initialization
	trace("Initializing NSPC");
	nspc.initialize(sampleRate);

	trace("Loading NSPC file");
	// Load files
	nspc.loadNSPCFile(file);

	nspc.play();
	trace("Playing NSPC music");

	nspc.setSpeed(speed);

	if (outfile != "") {
		dumpWav(nspc, sampleRate, channels, outfile);
	} else if (dumpBRRFiles) {
		foreach(idx, sample; nspc.getSamples) {
			const filename = format!"%s.%s.brr.wav"(args[1], idx);
			dumpWav(sample.data, sampleRate, 1, filename);
			writeln("Writing ", filename);
		}
	} else {
		// Prepare to play music
		if (!initAudio(&_sampling_func, channels, sampleRate, &nspc)) {
			return 1;
		}
		trace("SDL audio init success");


		writeln("Press enter to exit");
		readln();
	}

	return 0;
}

struct WAVFile {
	align(1):
	char[4] riffSignature = "RIFF";
	uint fileSize;
	char[4] wavSignature = "WAVE";
	char[4] fmtChunkSignature = "fmt ";
	uint fmtLength = 16;
	ushort format = 1;
	ushort channels;
	uint sampleRate;
	uint secondSize;
	ushort sampleSize;
	ushort bitsPerSample;
	char[4] dataSignature = "data";
	uint dataSize;
	void recalcSizes(size_t sampleCount) @safe pure {
		assert(sampleCount <= uint.max, "Too many samples");
		sampleSize = cast(ushort)(channels * bitsPerSample / 8);
		secondSize = sampleRate * sampleSize;
		dataSize = cast(uint)(sampleCount * sampleSize);
		fileSize = cast(uint)(WAVFile.sizeof - 8 + dataSize);
	}
}

void dumpWav(ref NSPCPlayer player, uint sampleRate, ushort channels, string filename) {
	player.looping = false;
	short[2][] samples;
	while (player.isPlaying) {
		short[2][4096] buffer;
		samples ~= player.fillBuffer(buffer[]);
	}
	dumpWav(samples, sampleRate, channels, filename);
}

void dumpWav(T)(T[] samples, uint sampleRate, ushort channels, string filename) {
	auto file = File(filename, "w");
	WAVFile header;
	header.sampleRate = sampleRate;
	header.channels = channels;
	header.bitsPerSample = 16;
	header.recalcSizes(samples.length);
	file.rawWrite([header]);
	file.rawWrite(samples);
}
