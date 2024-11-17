module m4a.mp2k_common;

//#if ((-1 >> 1) == -1) && __has_builtin(__builtin_ctz)
//#define FLOOR_DIV_POW2(a, b) ((a) >> __builtin_ctz(b))
//#else
int FLOOR_DIV_POW2(int a, ubyte b) {
	return ((a) > 0 ? (a) / (b) : (((a) + 1 - (b)) / (b)));
}
//#endif

//#define NOT_GBA_BIOS
////#define ORIGINAL_COARSE_POSITION_CLEARING
//#define POKEMON_EXTENSIONS
