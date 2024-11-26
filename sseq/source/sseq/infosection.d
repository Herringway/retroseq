module sseq.infosection;

import sseq.common;

struct INFOSection {
	align(1):
	char[4] type;
	uint blockSize;
	uint[8] recordOffsets;
	auto record(T)(const(ubyte)[] infoBlock, size_t idx) const @safe {
		static struct Result {
			private const(ubyte)[] data;
			private const(uint)[] entries;
			this(const(ubyte)[] data, size_t offset) @safe {
				this.data = data;
				auto count = (cast(const(uint)[])(data[offset .. offset + uint.sizeof]))[0];
				entries = cast(const(uint)[])(data[offset + uint.sizeof .. offset + uint.sizeof + uint.sizeof * count]);
			}
			size_t length() const => entries.length;
			bool isValid(size_t idx) const => (idx < entries.length) && (entries[idx] != 0);
			T opIndex(size_t idx) const {
				return (cast(const(T)[])data[entries[idx] .. entries[idx] + T.sizeof])[0];
			}
		}
		return Result(infoBlock, recordOffsets[idx]);
	}
	auto SEQrecord(const(ubyte)[] infoBlock) const {
		return record!INFOEntrySEQ(infoBlock, RecordName.REC_SEQ);
	}
	auto BANKrecord(const(ubyte)[] infoBlock) const {
		return record!INFOEntryBANK(infoBlock, RecordName.REC_BANK);
	}
	auto WAVEARCrecord(const(ubyte)[] infoBlock) const {
		return record!INFOEntryWAVEARC(infoBlock, RecordName.REC_WAVEARC);
	}
}

struct INFOEntrySEQ {
	align(1):
	ushort fileID;
	ushort unknown2;
	ushort bank;
	ubyte vol;
	ubyte cpr;
	ubyte ppr;
	ubyte ply;
	ushort unknownA;
}

struct INFOEntryBANK {
	align(1):
	ushort fileID;
	ushort unknown2;
	ushort[4] waveArc;
}

struct INFOEntryWAVEARC {
	align(1):
	ushort fileID;
	ushort unknown2;
}
