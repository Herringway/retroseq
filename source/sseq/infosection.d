module sseq.infosection;

import sseq.common;
import sseq.infoentry;

struct INFORecord(T)
{
	T[uint] entries;

	void Read(ref PseudoFile file, uint startOffset) {

		uint count = file.ReadLE!uint();
		auto entryOffsets = new uint[](count);
		file.ReadLE(entryOffsets);
		for (uint i = 0; i < count; ++i)
			if (entryOffsets[i])
			{
				file.pos = startOffset + entryOffsets[i];
				this.entries[i] = T();
				this.entries[i].Read(file);
			}
	}
};

struct INFOSection
{
	INFORecord!INFOEntrySEQ SEQrecord;
	INFORecord!INFOEntryBANK BANKrecord;
	INFORecord!INFOEntryWAVEARC WAVEARCrecord;

	void Read(ref PseudoFile file) {

		uint startOfINFO = file.pos;
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "INFO"))
			throw new Exception("SDAT INFO Section invalid");
		file.ReadLE!uint(); // size
		uint[8] recordOffsets;
		file.ReadLE(recordOffsets);
		if (recordOffsets[RecordName.REC_SEQ])
		{
			file.pos = startOfINFO + recordOffsets[RecordName.REC_SEQ];
			this.SEQrecord.Read(file, startOfINFO);
		}
		if (recordOffsets[RecordName.REC_BANK])
		{
			file.pos = startOfINFO + recordOffsets[RecordName.REC_BANK];
			this.BANKrecord.Read(file, startOfINFO);
		}
		if (recordOffsets[RecordName.REC_WAVEARC])
		{
			file.pos = startOfINFO + recordOffsets[RecordName.REC_WAVEARC];
			this.WAVEARCrecord.Read(file, startOfINFO);
		}
	}
};
