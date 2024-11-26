module sseq.fatsection;

import sseq.common;

struct FATRecord {
	align(1):
	uint offset;
	uint size;
	ulong reserved;
}

struct FATSection {
	align(1):
	char[4] type;
	uint blockSize;
	uint fileCount;

	FATRecord file(const(ubyte)[] fatBlock, size_t idx) const @safe
		in (idx < fileCount, "File ID out of range")
	{
		return (cast(const(FATRecord)[])(fatBlock[FATSection.sizeof .. FATSection.sizeof + FATRecord.sizeof * fileCount]))[idx];
	}
}
