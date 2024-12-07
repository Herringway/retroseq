///
module sseq.symbsection;

import sseq.common;
import std.string;

///
struct SYMBSection
{
	align(1):
	char[4] type; ///
	uint blockSize; ///
	uint[8] recordOffsets; ///
	///
	auto record(const(ubyte)[] symbBlock, size_t idx) const @safe {
		static struct Result {
			private const(ubyte)[] data;
			private const(uint)[] entries;
			this(const(ubyte)[] data, size_t offset) @safe {
				this.data = data;
				auto count = (cast(const(uint)[])(data[offset .. offset + uint.sizeof]))[0];
				entries = cast(const(uint)[])(data[offset + uint.sizeof .. offset + uint.sizeof + uint.sizeof * count]);
			}
			const(char)[] opIndex(size_t idx) {
				return (cast(const(char)[])data[entries[idx] .. $]).fromStringz;
			}
		}
		return Result(symbBlock, recordOffsets[idx]);
	}
}
