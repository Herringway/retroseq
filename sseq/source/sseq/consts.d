module sseq.consts;

enum TrackState {
	alloc,
	noteWait,
	porta,
	tie,
	end
}

enum TrackUpdateFlags {
	volume,
	pan,
	timer,
	mod,
	len
}

enum ChannelState {
	none,
	start,
	attack,
	decay,
	sustain,
	release
}

enum ChannelFlags {
	updateVolume,
	updatePan,
	updateTimer
}

enum ChannelType {
	pcm,
	psg,
	noise
}

enum Interpolation
{
	none,
	linear,
	lagrange4Point,
	lagrange6Point,
	sinc
}

immutable uint ARM7_CLOCK = 33513982;
immutable double SecondsPerClockCycle = 64.0 * 2728.0 / ARM7_CLOCK;

immutable int FSS_TRACKCOUNT = 16;
immutable int FSS_MAXTRACKS = 32;
immutable int FSS_TRACKSTACKSIZE = 3;
immutable int AMPL_K = 723;
immutable int AMPL_MIN = -AMPL_K;
immutable int AMPL_THRESHOLD = AMPL_MIN << 7;

int SOUND_FREQ(int n) @safe { return -0x1000000 / n; }

uint SOUND_VOL(int n) @safe { return n; }
uint SOUND_VOLDIV(int n) @safe { return n << 8; }
uint SOUND_PAN(int n) @safe { return n << 16; }
uint SOUND_DUTY(int n) @safe { return n << 24; }
immutable uint SOUND_REPEAT = 1 << 27;
immutable uint SOUND_ONE_SHOT = 1 << 28;
uint SOUND_LOOP(bool a) @safe { return a ? SOUND_REPEAT : SOUND_ONE_SHOT; }
immutable uint SOUND_FORMAT_PSG = 3 << 29;
uint SOUND_FORMAT(int n) @safe { return n << 29; }
immutable uint SCHANNEL_ENABLE = 1 << 31;
