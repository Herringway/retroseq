///
module retroseq.utility;

import std.range;
import std.traits;


///
T pop(T)(ref const(ubyte)[] buf) {
	scope(exit) buf = buf[T.sizeof .. $];
	return buf.peek!T;
}

///
T peek(T)(const(ubyte)[] buf) {
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

/// Wrapper for SDL callbacks
extern (C) void sdlSampleFunctionWrapper(alias Function)(void* user, ubyte* buf, int bufSize) nothrow if (isDynamicArray!(Parameters!Function[1])) {
	static bool done;
	import std.exception : assumeWontThrow;
	import std.stdio : writeln;
	if (done) {
		return;
	}
	try {
		Function(*cast(Parameters!Function[0]*)user, cast(Parameters!Function[1])buf[0 .. bufSize]);
	} catch (Throwable e) {
		assumeWontThrow(writeln(e));
		done = true;
	}
}

private struct EndianType(T, bool littleEndian) {
	ubyte[T.sizeof] raw;
	alias native this;
	version(BigEndian) {
		enum needSwap = littleEndian;
	} else {
		enum needSwap = !littleEndian;
	}
	T native() const @safe {
		T result = (cast(T[])(raw[].dup))[0];
		static if (needSwap) {
			swapEndianness(result);
		}
		return result;
	}
	void native(out T result) const @safe {
		result = (cast(T[])(raw[].dup))[0];
		static if (needSwap) {
			swapEndianness(result);
		}
	}
	void toString(Range)(Range sink) const if (isOutputRange!(Range, const(char))) {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s"(this.native);
	}
	void opAssign(ubyte[T.sizeof] input) {
		raw = input;
	}
	void opAssign(ubyte[] input) {
		assert(input.length == T.sizeof, "Array must be "~T.sizeof.stringof~" bytes long");
		raw = input;
	}
	void opAssign(T input) @safe {
		static if (needSwap) {
			swapEndianness(input);
		}
		union Raw {
			T val;
			ubyte[T.sizeof] raw;
		}
		raw = Raw(input).raw;
	}
}

void swapEndianness(T)(ref T val) {
	import std.bitmanip : swapEndian;
	static if (isIntegral!T || isSomeChar!T || isBoolean!T) {
		val = swapEndian(val);
	} else static if (isFloatingPoint!T) {
		import std.algorithm : reverse;
		union Raw {
			T val;
			ubyte[T.sizeof] raw;
		}
		auto raw = Raw(val);
		reverse(raw.raw[]);
		val = raw.val;
	} else static if (is(T == struct)) {
		foreach (ref field; val.tupleof) {
			swapEndianness(field);
		}
	} else static if (isStaticArray!T) {
		foreach (ref element; val) {
			swapEndianness(element);
		}
	} else static assert(0, "Unsupported type "~T.stringof);
}

alias LittleEndian(T) = EndianType!(T, true);
alias BigEndian(T) = EndianType!(T, false);
