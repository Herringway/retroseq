///
module retroseq.utility;

import std.exception;
import std.format;
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
	return cast(const(T)[])(input[start .. start + getMaxSliceSize!T(input, start)]);
}

///
size_t getMaxSliceSize(T)(const(ubyte)[] input, size_t start) @safe pure {
	return (((input.length - start) / T.sizeof) * T.sizeof);
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

///
struct RelativePointer(Element, Offset, size_t Base) {
	align(1):
	Offset offset; ///
	///
	bool isValid() const @safe pure {
		return offset >= Base;
	}
	///
	const(Element)[] toAbsoluteArray(const(ubyte)[] base) const {
		return toAbsoluteArray!Element(base);
	}
	///
	const(Element)[] toAbsoluteArray(const(ubyte)[] base, size_t length) const {
		return toAbsoluteArray!Element(base, length);
	}
	///
	const(T)[] toAbsoluteArray(T)(const(ubyte)[] base) const {
		const realOffset = offset - Base;
		return toAbsoluteArray!T(base, (base.length - realOffset) / T.sizeof);
	}
	///
	const(T)[] toAbsoluteArray(T)(const(ubyte)[] base, size_t length) const {
		const realOffset = offset - Base;
		enforce (realOffset < base.length, format!"Invalid pointer: %X"(offset));
		return cast(const(T)[])(base[realOffset .. realOffset + length * T.sizeof]);
	}
	///
	Offset opAssign(Offset newValue) {
		return offset = newValue;
	}
	void toString(W)(auto ref W writer) const {
		writer.formattedWrite!"$%X"(offset);
	}
}

@safe pure unittest {
	ubyte[] sample = [1, 2, 3, 4, 5];
	alias RelativePointer1 = RelativePointer!(ubyte, uint, 0);
	alias RelativePointer2 = RelativePointer!(ushort, uint, 0);
	assert(RelativePointer1(0).toAbsoluteArray(sample) == [1, 2, 3, 4, 5]);
	assert(RelativePointer1(1).toAbsoluteArray(sample) == [2, 3, 4, 5]);

	assert(RelativePointer2(0).toAbsoluteArray(sample) == [0x0201, 0x0403]);
	assert(RelativePointer2(0).toAbsoluteArray(sample, 1) == [0x0201]);
	assert(RelativePointer2(1).toAbsoluteArray(sample) == [0x0302, 0x0504]);
	assert(RelativePointer2(1).toAbsoluteArray(sample, 1) == [0x0302]);
	assert(RelativePointer2(0).toAbsoluteArray!ubyte(sample) == [1, 2, 3, 4, 5]);
	assert(RelativePointer2(1).toAbsoluteArray!ubyte(sample) == [2, 3, 4, 5]);
}
