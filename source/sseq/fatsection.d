module sseq.fatsection;

import sseq.common;

struct FATRecord
{
	uint offset;

	void Read(ref PseudoFile file) {

		this.offset = file.ReadLE!uint();
		file.ReadLE!uint(); // size
		uint[2] reserved;
		file.ReadLE(reserved);
	}
}

struct FATSection
{
	FATRecord[] records;

	void Read(ref PseudoFile file) {
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "FAT "))
			throw new Exception("SDAT FAT Section invalid");
		file.ReadLE!uint(); // size
		uint count = file.ReadLE!uint();
		this.records.length = count;
		for (uint i = 0; i < count; ++i)
			this.records[i].Read(file);
	}
}
