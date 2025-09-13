///
module retroseq.sseq.fatsection;

import retroseq.sseq.common;

import std.format;

///
struct FATRecord {
	align(1):
	uint offset; ///
	uint size; ///
	ulong reserved; ///
}

///
struct FATSection {
	align(1):
	char[4] type; ///
	uint blockSize; ///
	uint fileCount; ///

	///
	FATRecord file(const(ubyte)[] fatBlock, size_t idx) const @safe
		in (idx < fileCount, format!"File ID %s out of range"(idx))
	{
		return (cast(const(FATRecord)[])(fatBlock[FATSection.sizeof .. FATSection.sizeof + FATRecord.sizeof * fileCount]))[idx];
	}
}
