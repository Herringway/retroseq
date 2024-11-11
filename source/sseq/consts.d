module sseq.consts;

immutable uint ARM7_CLOCK = 33513982;
immutable double SecondsPerClockCycle = 64.0 * 2728.0 / ARM7_CLOCK;

uint BIT(uint n) @safe { return 1 << n; }

enum { TS_ALLOCBIT, TS_NOTEWAIT, TS_PORTABIT, TS_TIEBIT, TS_END, TS_BITS };

enum { TUF_VOL, TUF_PAN, TUF_TIMER, TUF_MOD, TUF_LEN, TUF_BITS };

enum { CS_NONE, CS_START, CS_ATTACK, CS_DECAY, CS_SUSTAIN, CS_RELEASE };

enum { CF_UPDVOL, CF_UPDPAN, CF_UPDTMR, CF_BITS };

enum { TYPE_PCM, TYPE_PSG, TYPE_NOISE };

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
immutable uint SOUND_REPEAT = BIT(27);
immutable uint SOUND_ONE_SHOT = BIT(28);
uint SOUND_LOOP(bool a) @safe { return a ? SOUND_REPEAT : SOUND_ONE_SHOT; }
immutable uint SOUND_FORMAT_PSG = 3 << 29;
uint SOUND_FORMAT(int n) @safe { return n << 29; }
immutable uint SCHANNEL_ENABLE = BIT(31);

enum Interpolation
{
	INTERPOLATION_NONE,
	INTERPOLATION_LINEAR,
	INTERPOLATION_4POINTLEGRANGE,
	INTERPOLATION_6POINTLEGRANGE,
	INTERPOLATION_SINC
}
