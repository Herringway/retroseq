///
module sseq.common;

/**
 * The following function is used to convert an integer into a hexidecimal
 * string, the length being determined by the size of the integer.  8-bit
 * integers are in the format of 0x00, 16-bit integers are in the format of
 * 0x0000, and so on.
 */
string NumToHexString(T)(ref const T num)
{
	char[T.sizeof * 2] hex;
	ubyte len = T.sizeof * 2;
	for (ubyte i = 0; i < len; ++i)
	{
		ubyte tmp = (num >> (i * 4)) & 0xF;
		hex[$ - i - 1] = cast(char)(tmp < 10 ? tmp + '0' : tmp - 10 + 'a');
	}
	return "0x" ~ hex;
}

/**
 * SDAT Record types
 * List of types taken from the Nitro Composer Specification
 * http://www.feshrine.net/hacking/doc/nds-sdat.html
 */
enum RecordName
{
	REC_SEQ, ///
	REC_SEQARC, ///
	REC_BANK, ///
	REC_WAVEARC, ///
	REC_PLAYER, ///
	REC_GROUP, ///
	REC_PLAYER2, ///
	REC_STRM, ///
}

///
bool VerifyHeader(size_t N)(ref byte[N] arr, const string header) @safe
{
	return arr[] == header;
}

/**
 * The remaining functions in this file come from the FeOS Sound System source code.
 */
int Cnv_Attack(int attk) @safe
{
	static const ubyte[] lut =
	[
		0x00, 0x01, 0x05, 0x0E, 0x1A, 0x26, 0x33, 0x3F, 0x49, 0x54,
		0x5C, 0x64, 0x6D, 0x74, 0x7B, 0x7F, 0x84, 0x89, 0x8F
	];

	if (attk & 0x80) // Supposedly invalid value...
		attk = 0; // Use apparently correct default
	return attk >= 0x6D ? lut[0x7F - attk] : 0xFF - attk;
}

///
int Cnv_Fall(int fall) @safe
{
	if (fall & 0x80) // Supposedly invalid value...
		fall = 0; // Use apparently correct default
	if (fall == 0x7F)
		return 0xFFFF;
	else if (fall == 0x7E)
		return 0x3C00;
	else if (fall < 0x32)
		return ((fall << 1) + 1) & 0xFFFF;
	else
		return (0x1E00 / (0x7E - fall)) & 0xFFFF;
}

///
int Cnv_Scale(int scale)
{
	static const short[] lut =
	[
		-32768, -421, -361, -325, -300, -281, -265, -252,
		-240, -230, -221, -212, -205, -198, -192, -186,
		-180, -175, -170, -165, -161, -156, -152, -148,
		-145, -141, -138, -134, -131, -128, -125, -122,
		-120, -117, -114, -112, -110, -107, -105, -103,
		-100, -98, -96, -94, -92, -90, -88, -86,
		-85, -83, -81, -79, -78, -76, -74, -73,
		-71, -70, -68, -67, -65, -64, -62, -61,
		-60, -58, -57, -56, -54, -53, -52, -51,
		-49, -48, -47, -46, -45, -43, -42, -41,
		-40, -39, -38, -37, -36, -35, -34, -33,
		-32, -31, -30, -29, -28, -27, -26, -25,
		-24, -23, -23, -22, -21, -20, -19, -18,
		-17, -17, -16, -15, -14, -13, -12, -12,
		-11, -10, -9, -9, -8, -7, -6, -6,
		-5, -4, -3, -3, -2, -1, -1, 0
	];

	if (scale & 0x80) // Supposedly invalid value...
		scale = 0x7F; // Use apparently correct default
	return lut[scale];
}

///
int Cnv_Sust(int sust) @safe
{
	static const short[] lut =
	[
		-32768, -722, -721, -651, -601, -562, -530, -503,
		-480, -460, -442, -425, -410, -396, -383, -371,
		-360, -349, -339, -330, -321, -313, -305, -297,
		-289, -282, -276, -269, -263, -257, -251, -245,
		-239, -234, -229, -224, -219, -214, -210, -205,
		-201, -196, -192, -188, -184, -180, -176, -173,
		-169, -165, -162, -158, -155, -152, -149, -145,
		-142, -139, -136, -133, -130, -127, -125, -122,
		-119, -116, -114, -111, -109, -106, -103, -101,
		-99, -96, -94, -91, -89, -87, -85, -82,
		-80, -78, -76, -74, -72, -70, -68, -66,
		-64, -62, -60, -58, -56, -54, -52, -50,
		-49, -47, -45, -43, -42, -40, -38, -36,
		-35, -33, -31, -30, -28, -27, -25, -23,
		-22, -20, -19, -17, -16, -14, -13, -11,
		-10, -8, -7, -6, -4, -3, -1, 0
	];

	if (sust & 0x80) // Supposedly invalid value...
		sust = 0x7F; // Use apparently correct default
	return lut[sust];
}

///
int Cnv_Sine(int arg) @safe
{
	static const int lut_size = 32;
	static const byte[] lut =
	[
		0, 6, 12, 19, 25, 31, 37, 43, 49, 54, 60, 65, 71, 76, 81, 85, 90, 94,
		98, 102, 106, 109, 112, 115, 117, 120, 122, 123, 125, 126, 126, 127, 127
	];

	if (arg < lut_size)
		return lut[arg];
	if (arg < 2 * lut_size)
		return lut[2 * lut_size - arg];
	if (arg < 3 * lut_size)
		return -lut[arg - 2 * lut_size];
	/*else*/
	return -lut[4 * lut_size - arg];
}

///
int read8(ref const(ubyte)[] ppData) @safe
{
	int x = ppData[0];
	ppData = ppData[1 .. $];
	return x;
}

///
int read16(ref const(ubyte)[] ppData) @safe
{
	int x = read8(ppData);
	x |= read8(ppData) << 8;
	return x;
}

///
int read24(ref const(ubyte)[] ppData) @safe
{
	int x = read8(ppData);
	x |= read8(ppData) << 8;
	x |= read8(ppData) << 16;
	return x;
}

///
int readvl(ref const(ubyte)[] ppData) @safe
{
	int x = 0;
	for (;;)
	{
		int data = read8(ppData);
		x = (x << 7) | (data & 0x7F);
		if (!(data & 0x80))
			break;
	}
	return x;
}
