///
module pxtone.descriptor;
// '11/08/12 pxFile.h
// '16/01/22 pxFile.h
// '16/04/27 pxtnFile. (int)
// '16/09/09 pxtnDescriptor.

import pxtone.error;
import pxtone.pxtn;

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

///
struct PxtnDescriptor {
private:
	ubyte[] buffer; ///
	File file; ///
	bool isFile; ///
	bool readOnly; ///
	int size; ///
	int currentPosition; ///

	///
	bool isOpen() nothrow @safe {
		return (buffer != null) || file.isOpen;
	}
public:
	///
	void setFileReadOnly(ref File fd) @safe {
		enforce(fd.isOpen, new PxtoneException("File must be opened for reading"));

		fd.seek(0, SEEK_END);
		ulong sz = fd.tell;
		fd.seek(0, SEEK_SET);
		file = fd;

		size = cast(int) sz;

		isFile = true;
		readOnly = true;
		currentPosition = 0;
	}

	///
	void setFileWritable(ref File fd) @safe {
		file = fd;
		size = 0;
		isFile = true;
		readOnly = false;
		currentPosition = 0;
	}

	///
	void setMemoryReadOnly(ubyte[] buf) @safe {
		enforce(buf.length >= 1, new PxtoneException("No data to read in buffer"));
		buffer = buf;
		isFile = false;
		readOnly = true;
		currentPosition = 0;
	}

	///
	void seek(PxtnSeek mode, int val) @safe {
		if (isFile) {
			static immutable int[PxtnSeek.num] seekMapping = [SEEK_SET, SEEK_CUR, SEEK_END];
			file.seek(val, seekMapping[mode]);
		} else {
			switch (mode) {
			case PxtnSeek.set:
				enforce(val < buffer.length, "Unexpected end of data");
				enforce(val >= 0, "Cannot seek to negative position");
				currentPosition = val;
				break;
			case PxtnSeek.cur:
				enforce(currentPosition + val < buffer.length, "Unexpected end of data");
				enforce(currentPosition + val >= 0, "Cannot seek to negative position");
				currentPosition += val;
				break;
			case PxtnSeek.end:
				enforce(buffer.length + val < buffer.length, "Unexpected end of data");
				enforce(buffer.length + val >= 0, "Cannot seek to negative position");
				currentPosition = cast(int)buffer.length + val;
				break;
			default:
				break;
			}
		}
	}

	///
	void write(T)(const T p) @safe if (!is(T : U[], U)) {
		union RawAccess {
			T t;
			ubyte[T.sizeof] bytes;
		}
		write(RawAccess(p).bytes);
	}

	///
	void write(T)(scope const(T)[] p) @safe {
		enforce(isOpen && isFile && !readOnly, new PxtoneException("File must be opened for writing"));

		file.trustedWrite(p);
		size += p.length * T.sizeof;
	}

	///
	void read(T)(T[] p) @safe {
		enforce(isOpen, new PxtoneException("File must be opened for reading"));
		enforce(readOnly, new PxtoneException("File must be opened for reading"));

		if (isFile) {
			file.trustedRead(p);
		} else {
			for (int i = 0; i < p.length; i++) {
				enforce(currentPosition + T.sizeof < buffer.length, new PxtoneException("Unexpected end of buffer"));
				p[i] = (cast(T[])buffer[currentPosition .. currentPosition + T.sizeof])[0];
				currentPosition += T.sizeof;
			}
		}
	}

	///
	void read(T)(ref T p) @safe if (!is(T : U[], U)) {
		enforce(isOpen, new PxtoneException("File must be opened for reading"));
		enforce(readOnly, new PxtoneException("File must be opened for reading"));

		if (isFile) {
			p = file.trustedRead!T();
		} else {
			enforce(currentPosition + T.sizeof < buffer.length, new PxtoneException("Unexpected end of buffer"));
			p = (cast(T[])buffer[currentPosition .. currentPosition + T.sizeof])[0];
			currentPosition += T.sizeof;
		}
	}

	// ..uint
	///
	void writeVarInt(int val) @safe {
		int dummy;
		writeVarInt(val, dummy);
	}
	void writeVarInt(int val, ref int pAdd) @safe {
		enforce(isOpen && isFile && !readOnly, new PxtoneException("File must be opened for writing"));

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
		file.trustedWrite(b[0 .. bytes]);
		pAdd += bytes;
		size += bytes;
	}
	// 可変長読み込み（int  までを保証）
	///
	void readVarInt(T)(ref T p) {
		enforce(isOpen && readOnly, new PxtoneException("File must be opened for reading"));

		int i;
		ubyte[5] a = 0;
		ubyte[5] b = 0;

		for (i = 0; i < 5; i++) {
			read(a[i]);
			if (!(a[i] & 0x80)) {
				break;
			}
		}
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
	int getByteSize() const nothrow @safe {
		return isFile ? size : cast(int)buffer.length;
	}
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
