///
module retroseq.pxtone.descriptor;
// '11/08/12 pxFile.h
// '16/01/22 pxFile.h
// '16/04/27 pxtnFile. (int)
// '16/09/09 pxtnDescriptor.

import retroseq.pxtone.error;
import retroseq.pxtone.pxtn;

import std.exception;
import std.stdio;
import std.traits;

///
enum PxSCE = false;

///
enum PxtnSeek {
	set = 0, ///
	cur, ///
	end, ///
	num ///
}

void write(R, T)(ref R output, T value) if (!is(T: A[], A)) {
	T[1] tmp = value;
	write(output, tmp[]);
}

void write(R, T)(ref R output, T[] data) {
	import std.range : put;
	put(output, cast(const(ubyte)[])data);
}
void writeVarInt(R)(ref R output, int val) @safe {
	int _;
	writeVarInt(output, val, _);
}
void writeVarInt(R)(ref R output, int val, ref int pAdd) @safe {
	import std.range : put;

	ubyte[5] a = 0;
	ubyte[5] b = 0;
	uint us = cast(uint) val;
	int bytes = 0;

	(cast(uint[])(a[0 .. uint.sizeof]))[0] = us;
	a[4] = 0;

	// 1byte(7bit)
	if (us < 0x00000080) {
		bytes = 1;
		b[0] = a[0];
	}  // 2byte(14bit)
	else if (us < 0x00004000) {
		bytes = 2;
		b[0] = ((a[0] << 0) & 0x7F) | 0x80;
		b[1] = (a[0] >> 7) | ((a[1] << 1) & 0x7F);
	}  // 3byte(21bit)
	else if (us < 0x00200000) {
		bytes = 3;
		b[0] = ((a[0] << 0) & 0x7F) | 0x80;
		b[1] = (a[0] >> 7) | ((a[1] << 1) & 0x7F) | 0x80;
		b[2] = (a[1] >> 6) | ((a[2] << 2) & 0x7F);
	}  // 4byte(28bit)
	else if (us < 0x10000000) {
		bytes = 4;
		b[0] = ((a[0] << 0) & 0x7F) | 0x80;
		b[1] = (a[0] >> 7) | ((a[1] << 1) & 0x7F) | 0x80;
		b[2] = (a[1] >> 6) | ((a[2] << 2) & 0x7F) | 0x80;
		b[3] = (a[2] >> 5) | ((a[3] << 3) & 0x7F);
	}  // 5byte(32bit)
	else {
		bytes = 5;
		b[0] = ((a[0] << 0) & 0x7F) | 0x80;
		b[1] = (a[0] >> 7) | ((a[1] << 1) & 0x7F) | 0x80;
		b[2] = (a[1] >> 6) | ((a[2] << 2) & 0x7F) | 0x80;
		b[3] = (a[2] >> 5) | ((a[3] << 3) & 0x7F) | 0x80;
		b[4] = (a[3] >> 4) | ((a[4] << 4) & 0x7F);
	}
	put(output, b[0 .. bytes]);
	pAdd += bytes;
}

void pop(T)(ref const(ubyte)[] buffer, ref T dest) if (!is(T: A[], A)) {
	T[1] value;
	pop(buffer, value[]);
	dest = value[0];
}

T pop(T)(ref const(ubyte)[] buffer) {
	T[1] value;
	pop(buffer, value[]);
	return value[0];
}

void pop(T)(ref const(ubyte)[] buffer, T[] destination) {
	scope(exit) buffer = buffer[T.sizeof * destination.length .. $];
	destination[] = cast(const(T)[])buffer[0 .. T.sizeof * destination.length];
}

// 可変長読み込み（int  までを保証）
///
void popVarInt(T)(ref const(ubyte)[] buffer, ref T p) {
	int i;
	ubyte[5] a = 0;
	ubyte[5] b = 0;

	for (i = 0; i < 5; i++) {
		a[i] = buffer[i];
		if (!(a[i] & 0x80)) {
			break;
		}
	}
	buffer = buffer[i + 1 .. $];
	switch (i) {
	case 0:
		b[0] = (a[0] & 0x7F) >> 0;
		break;
	case 1:
		b[0] = cast(ubyte)(((a[0] & 0x7F) >> 0) | (a[1] << 7));
		b[1] = (a[1] & 0x7F) >> 1;
		break;
	case 2:
		b[0] = cast(ubyte)(((a[0] & 0x7F) >> 0) | (a[1] << 7));
		b[1] = cast(ubyte)(((a[1] & 0x7F) >> 1) | (a[2] << 6));
		b[2] = (a[2] & 0x7F) >> 2;
		break;
	case 3:
		b[0] = cast(ubyte)(((a[0] & 0x7F) >> 0) | (a[1] << 7));
		b[1] = cast(ubyte)(((a[1] & 0x7F) >> 1) | (a[2] << 6));
		b[2] = cast(ubyte)(((a[2] & 0x7F) >> 2) | (a[3] << 5));
		b[3] = (a[3] & 0x7F) >> 3;
		break;
	case 4:
		b[0] = cast(ubyte)(((a[0] & 0x7F) >> 0) | (a[1] << 7));
		b[1] = cast(ubyte)(((a[1] & 0x7F) >> 1) | (a[2] << 6));
		b[2] = cast(ubyte)(((a[2] & 0x7F) >> 2) | (a[3] << 5));
		b[3] = cast(ubyte)(((a[3] & 0x7F) >> 3) | (a[4] << 4));
		b[4] = (a[4] & 0x7F) >> 4;
		break;
	case 5:
		throw new PxtoneException("Integer too large");
	default:
		break;
	}

	p = (cast(int[]) b[0 .. 4])[0];
}

///
int getVarIntSize(int val) nothrow @safe {
	uint us;

	us = cast(uint) val;
	if (us < 0x80) {
		return 1; // 1byte( 7bit)
	}
	if (us < 0x4000) {
		return 2; // 2byte(14bit)
	}
	if (us < 0x200000) {
		return 3; // 3byte(21bit)
	}
	if (us < 0x10000000) {
		return 4; // 4byte(28bit)
	}
	//	if( value < 0x800000000 ) return 5;	// 5byte(35bit)
	if (us <= 0xffffffff) {
		return 5;
	}

	return 6;
}

///
private T trustedRead(T)(File file) @safe if (!hasIndirections!T) {
	T[1] p;
	file.trustedRead(p);
	return p[0];
}

///
private void trustedRead(T)(File file, T[] arr) @trusted if (!hasIndirections!T) {
	file.rawRead(arr);
}

///
private void trustedWrite(T)(File file, T val) @safe if (!hasIndirections!T) {
	T[1] p = [val];
	file.trustedWrite(p);
}

///
private void trustedWrite(T)(File file, T[] arr) @trusted if (!hasIndirections!T) {
	file.rawWrite(arr);
}
