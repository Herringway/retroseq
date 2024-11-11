module sseq.symbsection;

import sseq.common;

struct SYMBRecord
{
	string[uint] entries;

	void Read(ref PseudoFile file, uint startOffset) {
		uint count = file.ReadLE!uint();
		auto entryOffsets = new uint[](count);
		file.ReadLE(entryOffsets);
		for (uint i = 0; i < count; ++i)
			if (entryOffsets[i])
			{
				file.pos = startOffset + entryOffsets[i];
				this.entries[i] = file.ReadNullTerminatedString();
			}
	}
}

/*
 * The size has been left out of this structure as it is unused by this player.
 */
struct SYMBSection
{
	SYMBRecord SEQrecord;
	SYMBRecord BANKrecord;
	SYMBRecord WAVEARCrecord;

	void Read(ref PseudoFile file) {
		uint startOfSYMB = file.pos;
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "SYMB"))
			throw new Exception("SDAT SYMB Section invalid");
		file.ReadLE!uint(); // size
		uint[8] recordOffsets;
		file.ReadLE(recordOffsets);
		if (recordOffsets[RecordName.REC_SEQ])
		{
			file.pos = startOfSYMB + recordOffsets[RecordName.REC_SEQ];
			this.SEQrecord.Read(file, startOfSYMB);
		}
		if (recordOffsets[RecordName.REC_BANK])
		{
			file.pos = startOfSYMB + recordOffsets[RecordName.REC_BANK];
			this.BANKrecord.Read(file, startOfSYMB);
		}
		if (recordOffsets[RecordName.REC_WAVEARC])
		{
			file.pos = startOfSYMB + recordOffsets[RecordName.REC_WAVEARC];
			this.WAVEARCrecord.Read(file, startOfSYMB);
		}
	}
}
