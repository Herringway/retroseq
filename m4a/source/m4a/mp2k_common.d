module m4a.mp2k_common;

int FLOOR_DIV_POW2(int a, ubyte b) @safe pure {
	return (a > 0) ? (a / b) : ((a + 1 - b) / b);
}
