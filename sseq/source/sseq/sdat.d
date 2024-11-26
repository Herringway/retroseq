module sseq.sdat;

import std.algorithm.sorting;
import std.conv;
import std.exception;
import std.typecons;

import sseq.common;
import sseq.fatsection;
import sseq.infosection;
import sseq.ndsstdheader;
import sseq.symbsection;
import sseq.sbnk;
import sseq.sseq;
import sseq.swar;

struct Song {
	const(SSEQ)* sseq;
	const(SBNK)* sbnk;
	const(SWAR)*[4] swar;
}

struct SDAT
{
	private static struct Block {
		align(1):
		uint offset;
		uint size;
	}
	NDSStdHeader header;
	INFOSection infoSection;
	FATSection fatSection;
	Nullable!SYMBSection symbSection;
	const(ubyte)[] sdatData;
	const(ubyte)[] symbSectionData;
	const(ubyte)[] infoSectionData;
	const(ubyte)[] fatSectionData;
	const(ubyte)[] fileSectionData;

	this(const(ubyte)[] data) @safe {
		sdatData = data;
		auto origData = data;
		// Read sections
		header = data.pop!NDSStdHeader();
		enforce(header.type == "SDAT");
		const symb = data.pop!Block();
		const info = data.pop!Block();
		const fat = data.pop!Block();
		void readSection(T)(ref T section, ref const(ubyte)[] sectionData, uint offset, string signature) {
			data = origData[offset .. $];
			section = data.pop!T();
			enforce(section.type == signature);
			sectionData = origData[offset .. offset + section.blockSize];
		}
		if (symb.offset) {
			symbSection = SYMBSection.init;
			readSection!SYMBSection(symbSection.get, symbSectionData, symb.offset, "SYMB");
		}
		readSection!INFOSection(infoSection, infoSectionData, info.offset, "INFO");
		readSection!FATSection(fatSection, fatSectionData, fat.offset, "FAT ");
	}
	auto sseqs() {
		static struct Result {
			static struct SongEntry {
				uint id;
				const(char)[] name;
			}
			private INFOSection infoSection;
			private Nullable!SYMBSection symbSection;
			private const(ubyte)[] symbSectionData;
			private const(ubyte)[] infoSectionData;
			private size_t idx;
			bool empty() const => idx >= infoSection.SEQrecord(infoSectionData).length;
			SongEntry front() const => SongEntry(cast(uint)idx, symbSection.isNull ? "" : symbSection.get.record(symbSectionData, RecordName.REC_SEQ)[idx]);
			void popFront() {
				do {
					 idx++;
				} while((idx < infoSection.SEQrecord(infoSectionData).length) && !infoSection.SEQrecord(infoSectionData).isValid(idx));
			}
		}
		return Result(infoSection, symbSection, symbSectionData, infoSectionData);
	}
	const(ubyte)[] readFile(size_t id) const @safe /*pure*/ {
		const record = fatSection.file(fatSectionData, id);
		return sdatData[record.offset .. record.offset + record.size];
	}
	Song getSSEQ(uint sseqToLoad) @safe {
		Song song;
		enforce(infoSection.SEQrecord(infoSectionData).length, "No SSEQ records found in SDAT");

		enforce(infoSection.SEQrecord(infoSectionData).isValid(sseqToLoad), "SSEQ of " ~ sseqToLoad.text ~ " is not found");

		// Read SSEQ
		ushort fileID = infoSection.SEQrecord(infoSectionData)[sseqToLoad].fileID;
		const(char)[] name = "SSEQ" ~ NumToHexString(fileID)[2 .. $];
		if (!symbSection.isNull)
			name = NumToHexString(sseqToLoad)[6 .. $] ~ " - " ~ symbSection.get.record(symbSectionData, RecordName.REC_SEQ)[sseqToLoad];
		auto sseqFile = readFile(fileID);
		SSEQ* newSSEQ = new SSEQ(name);
		newSSEQ.header = sseqFile.pop!NDSStdHeader();
		verify(newSSEQ.header, "SSEQ");
		newSSEQ.dataHeader = sseqFile.pop!(SSEQ.DataHeader)();
		enforce(newSSEQ.dataHeader.type == "DATA");
		newSSEQ.info = infoSection.SEQrecord(infoSectionData)[sseqToLoad];
		newSSEQ.data = sseqFile;
		song.sseq = newSSEQ;

		// Read SBNK for this SSEQ
		ushort bank = newSSEQ.info.bank;
		fileID = infoSection.BANKrecord(infoSectionData)[bank].fileID;
		name = "SBNK" ~ NumToHexString(fileID)[2 .. $];
		if (!symbSection.isNull)
			name = NumToHexString(bank)[2 .. $] ~ " - " ~ symbSection.get.record(symbSectionData, RecordName.REC_BANK)[bank];
		auto sbnkFile = readFile(fileID);
		SBNK *newSBNK = new SBNK(name);
		newSBNK.header = sbnkFile.pop!NDSStdHeader();
		newSBNK.dataHeader = sbnkFile.pop!(SBNK.DataHeader)();
		enforce(newSBNK.dataHeader.type == "DATA");
		newSBNK.info = infoSection.BANKrecord(infoSectionData)[bank];
		newSBNK.read(sbnkFile);
		song.sbnk = newSBNK;

		// Read SWARs for this SBNK
		for (int i = 0; i < 4; ++i)
			if (newSBNK.info.waveArc[i] != 0xFFFF)
			{
				ushort waveArc = newSBNK.info.waveArc[i];
				fileID = infoSection.WAVEARCrecord(infoSectionData)[waveArc].fileID;
				name = "SWAR" ~ NumToHexString(fileID)[2 .. $];
				if (!symbSection.isNull)
					name = NumToHexString(waveArc)[2 .. $] ~ " - " ~ symbSection.get.record(symbSectionData, RecordName.REC_WAVEARC)[waveArc];
				auto swarFile = readFile(fileID);
				SWAR *newSWAR = new SWAR(name);
				newSWAR.header = swarFile.pop!NDSStdHeader();
				verify(newSWAR.header, "SWAR");
				newSWAR.dataHeader = swarFile.pop!(SWAR.DataHeader)();
				enforce(newSWAR.dataHeader.type == "DATA");
				newSWAR.info = infoSection.WAVEARCrecord(infoSectionData)[waveArc];
				newSWAR.data = swarFile;
				newSWAR.loadSWAVs();
				song.swar[i] = newSWAR;
			}
			else
				song.swar[i] = null;
		return song;
	}
};
