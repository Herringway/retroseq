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
	SSEQ* sseq;
	SBNK* sbnk;
	SWAR*[4] swar;
}

struct SDAT
{
	NDSStdHeader header;
	INFOSection infoSection;
	FATSection fatSection;
	Nullable!SYMBSection symbSection;

	this(ref PseudoFile file) @safe {
		// Read sections
		header.Read(file);
		header.Verify("SDAT", 0x0100FEFF);
		uint SYMBOffset = file.ReadLE!uint();
		file.ReadLE!uint(); // SYMB size
		uint INFOOffset = file.ReadLE!uint();
		file.ReadLE!uint(); // INFO size
		uint FATOffset = file.ReadLE!uint();
		file.ReadLE!uint(); // FAT Size
		if (SYMBOffset)
		{
			file.pos = SYMBOffset;
			SYMBSection tmp;
			tmp.Read(file);
			symbSection = tmp;
		}
		file.pos = INFOOffset;
		infoSection.Read(file);
		file.pos = FATOffset;
		fatSection.Read(file);
	}
	auto sseqs() {
		static struct Result {
			static struct SongEntry {
				uint id;
				string name;
			}
			private uint[] keys;
			private Nullable!SYMBSection symbSection;
			bool empty() const => keys.length == 0;
			SongEntry front() const => SongEntry(keys[0], symbSection.isNull ? "" : symbSection.get.SEQrecord.entries[keys[0]]);
			void popFront() { keys = keys[1 .. $]; }
		}
		return Result(infoSection.SEQrecord.entries.keys.sort.release, symbSection);
	}
	Song getSSEQ(ref PseudoFile file, uint sseqToLoad) @safe {
		Song song;
		enforce(infoSection.SEQrecord.entries, "No SSEQ records found in SDAT");

		enforce(sseqToLoad in infoSection.SEQrecord.entries, "SSEQ of " ~ sseqToLoad.text ~ " is not found");

		// Read SSEQ
		ushort fileID = infoSection.SEQrecord.entries[sseqToLoad].fileID;
		string name = "SSEQ" ~ NumToHexString(fileID)[2 .. $];
		if (!symbSection.isNull)
			name = NumToHexString(sseqToLoad)[6 .. $] ~ " - " ~ symbSection.get.SEQrecord.entries[sseqToLoad];
		file.pos = fatSection.records[fileID].offset;
		SSEQ *newSSEQ = new SSEQ(name);
		newSSEQ.info = infoSection.SEQrecord.entries[sseqToLoad];
		newSSEQ.Read(file);
		song.sseq = newSSEQ;

		// Read SBNK for this SSEQ
		ushort bank = newSSEQ.info.bank;
		fileID = infoSection.BANKrecord.entries[bank].fileID;
		name = "SBNK" ~ NumToHexString(fileID)[2 .. $];
		if (!symbSection.isNull)
			name = NumToHexString(bank)[2 .. $] ~ " - " ~ symbSection.get.BANKrecord.entries[bank];
		file.pos = fatSection.records[fileID].offset;
		SBNK *newSBNK = new SBNK(name);
		newSSEQ.bank = newSBNK;
		newSBNK.info = infoSection.BANKrecord.entries[bank];
		newSBNK.Read(file);
		song.sbnk = newSBNK;

		// Read SWARs for this SBNK
		for (int i = 0; i < 4; ++i)
			if (newSBNK.info.waveArc[i] != 0xFFFF)
			{
				ushort waveArc = newSBNK.info.waveArc[i];
				fileID = infoSection.WAVEARCrecord.entries[waveArc].fileID;
				name = "SWAR" ~ NumToHexString(fileID)[2 .. $];
				if (!symbSection.isNull)
					name = NumToHexString(waveArc)[2 .. $] ~ " - " ~ symbSection.get.WAVEARCrecord.entries[waveArc];
				file.pos = fatSection.records[fileID].offset;
				SWAR *newSWAR = new SWAR(name);
				newSBNK.waveArc[i] = newSWAR;
				newSWAR.info = infoSection.WAVEARCrecord.entries[waveArc];
				newSWAR.Read(file);
				song.swar[i] = newSWAR;
			}
			else
				song.swar[i] = null;
		return song;
	}
private:
	this(const ref SDAT);
	SDAT opAssign(const ref SDAT);
};
