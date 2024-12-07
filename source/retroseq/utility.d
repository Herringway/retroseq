///
module retroseq.utility;

import std.traits;

///
T pop(T)(ref const(ubyte)[] buf) {
	scope(exit) buf = buf[T.sizeof .. $];
	return (cast(const(T)[])buf[0 .. 0 + T.sizeof])[0];
}

///
const(T)[] sliceMax(T)(const(ubyte)[] input, size_t start) @safe pure {
	return cast(const(T)[])(input[start .. start + ((($ - start) / T.sizeof) * T.sizeof)]);
}

///
void Funcify(alias Method, T)(ref T newThis, Parameters!Method params) {
	__traits(getMember, newThis, __traits(identifier, Method))(params);
}
