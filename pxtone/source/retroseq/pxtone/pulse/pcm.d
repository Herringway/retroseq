///
module retroseq.pxtone.pulse.pcm;

import std.exception;

import retroseq.pxtone.descriptor;
import retroseq.pxtone.error;
import retroseq.pxtone.pxtn;

///
private struct WAVEFORMATCHUNK {
	ushort formatID; // PCM:0x0001
	ushort ch; //
	uint sps; //
	uint bytesPerSec; // byte per sec.
	ushort blockSize; //
	ushort bps; // bit per sample.
	ushort ext; // no use for pcm.
}

///
struct PxtnPulsePCM {
private:
	int channels; ///
	int sps; ///
	int bps; ///
	int sampleBody; ///
	ubyte[] pcmSamples; ///

	// stereo / mono
	///
	private void convertChannelNum(int newChannels) @safe {
		ubyte[] pcmWork = null;
		const sampleSize = sampleBody * channels * bps / 8;

		enforce!PxtoneException(pcmSamples != null, "No data to convert");
		if (channels == newChannels) {
			return;
		}

		if (newChannels == 2) { // mono to stereo
			pcmWork = new ubyte[](sampleSize * 2);

			switch (bps) {
			case 8:
				int b = 0;
				for (int a = 0; a < sampleSize; a++) {
					pcmWork[b] = pcmSamples[a];
					pcmWork[b + 1] = pcmSamples[a];
					b += 2;
				}
				break;
			case 16:
				int b = 0;
				for (int a = 0; a < sampleSize; a += 2) {
					pcmWork[b] = pcmSamples[a];
					pcmWork[b + 1] = pcmSamples[a + 1];
					pcmWork[b + 2] = pcmSamples[a];
					pcmWork[b + 3] = pcmSamples[a + 1];
					b += 4;
				}
				break;
			default:
				break;
			}
		} else { // stereo to mono
			pcmWork = new ubyte[](sampleSize / 2);

			switch (bps) {
			case 8:
				int b = 0;
				for (int a = 0; a < sampleSize; a += 2) {
					int temp1 = cast(int) pcmSamples[a] + cast(int) pcmSamples[a + 1];
					pcmWork[b] = cast(ubyte)(temp1 / 2);
					b++;
				}
				break;
			case 16:
				int b = 0;
				for (int a = 0; a < sampleSize; a += 4) {
					int temp1 = (cast(short[])pcmSamples[a + 0 .. a + 2])[0];
					int temp2 = (cast(short[])pcmSamples[a + 2 .. a + 4])[0];
					(cast(short[])(pcmWork[b .. b + 2]))[0] = cast(short)((temp1 + temp2) / 2);
					b += 2;
				}
				break;
			default:
				break;
			}
		}

		pcmSamples = pcmWork;

		// update param.
		channels = newChannels;
	}

	// change bps
	///
	private void convertBitPerSample(int newBPS) @safe {
		ubyte[] pcmWork;

		enforce!PxtoneException(pcmSamples, "No data to convert");
		if (bps == newBPS) {
			return;
		}

		const sampleSize = sampleBody * channels * bps / 8;

		switch (newBPS) {
			// 16 to 8 --------
		case 8:
			const workSize = sampleSize / 2;
			pcmWork = new ubyte[](workSize);
			int b = 0;
			for (int a = 0; a < sampleSize; a += 2) {
				int temp1 = ((cast(short[])(pcmSamples[a .. a + 2])))[0];
				temp1 = (temp1 / 0x100) + 128;
				pcmWork[b] = cast(ubyte) temp1;
				b++;
			}
			break;
			//  8 to 16 --------
		case 16:
			const workSize = sampleSize * 2;
			pcmWork = new ubyte[](workSize);
			int b = 0;
			for (int a = 0; a < sampleSize; a++) {
				int temp1 = pcmSamples[a];
				temp1 = (temp1 - 128) * 0x100;
				((cast(short[])(pcmWork[b .. b + 2])))[0] = cast(short) temp1;
				b += 2;
			}
			break;

		default:
			throw new PxtoneException("Invalid requested bps");
		}

		pcmSamples = pcmWork;

		// update param.
		bps = newBPS;
	}
	// sps
	///
	private void convertSamplePerSecond(int newSPS) @safe {
		bool bRet = false;

		ubyte[] p1byteWork = null;
		ushort[] p2byteWork = null;
		uint[] p4byteWork = null;

		enforce!PxtoneException(pcmSamples, "No data to convert");
		if (sps == newSPS) {
			return;
		}

		int bodySize = sampleBody * channels * bps / 8;

		bodySize = cast(int)((cast(double) bodySize * cast(double) newSPS + cast(double)(sps) - 1) / sps);

		int workSize = bodySize;

		if (channels == 2 && bps == 16) { // stereo 16bit ========
			sampleBody = bodySize / 4;
			const sampleNum = workSize / 4;
			workSize = sampleNum * 4;
			const p4byteData = cast(uint[]) pcmSamples;
			p4byteWork = new uint[](workSize / uint.sizeof);

			for (int a = 0; a < sampleNum; a++) {
				int b = cast(int)(cast(double) a * cast(double)(sps) / cast(double) newSPS);
				p4byteWork[a] = p4byteData[b];
			}
		} else if (channels == 1 && bps == 8) { // mono 8bit ========
			sampleBody = bodySize / 1;
			const sampleNum = workSize / 1;
			workSize = sampleNum * 1;
			const p1byteData = cast(ubyte[]) pcmSamples;
			p1byteWork = new ubyte[](workSize);

			for (int a = 0; a < sampleNum; a++) {
				int b = cast(int)(cast(double) a * cast(double)(sps) / cast(double)(newSPS));
				p1byteWork[a] = p1byteData[b];
			}
		} else { // mono 16bit / stereo 8bit ========
			sampleBody = bodySize / 2;
			const sampleNum = workSize / 2;
			workSize = sampleNum * 2;
			const p2byteData = cast(ushort[]) pcmSamples;
			p2byteWork = new ushort[](workSize / ushort.sizeof);

			for (int a = 0; a < sampleNum; a++) {
				int b = cast(int)(cast(double) a * cast(double)(sps) / cast(double) newSPS);
				p2byteWork[a] = p2byteData[b];
			}
		}

		if (p4byteWork) {
			pcmSamples = cast(ubyte[])p4byteWork;
		} else if (p2byteWork) {
			pcmSamples = cast(ubyte[])p2byteWork;
		} else if (p1byteWork) {
			pcmSamples = p1byteWork;
		} else {
			throw new PxtoneException("Invalid data");
		}

		// update.
		sps = newSPS;
	}

public:
	///
	 ~this() nothrow @safe {
		release();
	}

	///
	void create(int ch, int sps, int bps, int sampleNum) @safe {
		release();

		enforce!PxtoneException(bps == 8 || bps == 16, "pcm unknown");

		channels = ch;
		this.sps = sps;
		this.bps = bps;
		sampleBody = sampleNum;

		// bit / sample is 8 or 16
		const size = sampleBody * bps * channels / 8;

		pcmSamples = new ubyte[](size);

		if (bps == 8) {
			pcmSamples[] = 128;
		} else {
			pcmSamples[] = 0;
		}
	}

	///
	void release() nothrow @safe {
		pcmSamples = null;
		channels = 0;
		sps = 0;
		bps = 0;
		sampleBody = 0;
	}

	///
	void read(ref const(ubyte)[] buffer) @safe {
		char[16] buf = 0;
		uint size = 0;
		WAVEFORMATCHUNK format;

		pcmSamples = null;
		scope(failure) {
			pcmSamples = null;
		}

		// 'RIFFxxxxWAVEfmt '
		buffer.pop(buf[]);

		enforce!PxtoneException(buf[0 .. 4] != "RIFF" && buf[8 .. 16] == "WAVEfmt ", "pcm unknown");

		// read format.
		buffer.pop(size);
		buffer.pop(format);

		enforce!PxtoneException(format.formatID == 0x0001, "pcm unknown");
		enforce!PxtoneException(format.ch == 1 || format.ch == 2, "pcm unknown");
		enforce!PxtoneException(format.bps == 8 || format.bps == 16 ,"pcm unknown");

		// find 'data'
		buffer = buffer[12 .. $];
	 	// skip 'RIFFxxxxWAVE'

		while (1) {
			buffer.pop(buf[0 .. 4]);
			buffer.pop(size);
			if (buf[0] == 'd' && buf[1] == 'a' && buf[2] == 't' && buf[3] == 'a') {
				break;
			}
			buffer = buffer[size .. $];
		}

		create(format.ch, format.sps, format.bps, size * 8 / format.bps / format.ch);

		buffer.pop(pcmSamples[0 .. size]);
	}

	///
	void write(R)(ref R output, const char[] pstrLIST) const @safe {
		enforce!PxtoneException(pcmSamples, "pcmSamples");

		WAVEFORMATCHUNK format;
		uint riffSize;
		uint factSize; // num sample.
		uint listSize; // num list text.
		uint isftSize;
		uint sampleSize;

		bool bText;

		char[4] tagRIFF = ['R', 'I', 'F', 'F'];
		char[4] tagWAVE = ['W', 'A', 'V', 'E'];
		char[8] tagFormat = ['f', 'm', 't', ' ', 0x12, 0, 0, 0];
		char[8] tagFact = ['f', 'a', 'c', 't', 0x04, 0, 0, 0];
		char[4] tagData = ['d', 'a', 't', 'a'];
		char[4] tagLIST = ['L', 'I', 'S', 'T'];
		char[8] tagINFO = ['I', 'N', 'F', 'O', 'I', 'S', 'F', 'T'];

		if (pstrLIST && pstrLIST.length) {
			bText = true;
		} else {
			bText = false;
		}

		sampleSize = sampleBody * channels * bps / 8;

		format.formatID = 0x0001; // PCM
		format.ch = cast(ushort) channels;
		format.sps = cast(uint) sps;
		format.bps = cast(ushort) bps;
		format.bytesPerSec = cast(uint)(sps * bps * channels / 8);
		format.blockSize = cast(ushort)(bps * channels / 8);
		format.ext = 0;

		factSize = sampleBody;
		riffSize = sampleSize;
		riffSize += 4; // 'WAVE'
		riffSize += 26; // 'fmt '
		riffSize += 12; // 'fact'
		riffSize += 8; // 'data'

		if (bText) {
			isftSize = cast(uint) pstrLIST.length;
			listSize = 4 + 4 + 4 + isftSize; // "INFO" + "ISFT" + size + ver_Text;
			riffSize += 8 + listSize; // 'LIST'
		} else {
			isftSize = 0;
			listSize = 0;
		}

		// open file..

		output.write(tagRIFF);
		output.write(riffSize);
		output.write(tagWAVE);
		output.write(tagFormat);
		output.write(format);

		if (bText) {
			output.write(tagLIST);
			output.write(listSize);
			output.write(tagINFO);
			output.write(isftSize);
			output.write(pstrLIST);
		}

		output.write(tagFact);
		output.write(factSize);
		output.write(tagData);
		output.write(sampleSize);
		output.write(pcmSamples);
	}

	// convert..
	///
	void convert(int newChannels, int newSPS, int newBPS) @safe {
		convertChannelNum(newChannels);
		convertBitPerSample(newBPS);
		convertSamplePerSecond(newSPS);
	}

	///
	void convertVolume(float v) @safe {
		enforce!PxtoneException(pcmSamples, "No sample data to convert");

		int sampleNum = sampleBody * channels;

		switch (bps) {
		case 8: {
				ubyte[] p8 = pcmSamples;
				for (int i = 0; i < sampleNum; i++) {
					p8[0] = cast(ubyte)(((cast(float)(p8[0]) - 128) * v) + 128);
					p8 = p8[1 .. $];
				}
				break;
			}
		case 16: {
				short[] p16 = cast(short[]) pcmSamples;
				for (int i = 0; i < sampleNum; i++) {
					p16[0] = cast(short)(cast(float)p16[0] * v);
					p16 = p16[1 .. $];
				}
				break;
			}
		default:
			throw new PxtoneException("Invalid bps");
		}
	}

	///
	void copy(ref PxtnPulsePCM pDest) const @safe {
		if (!pcmSamples) {
			pDest.release();
			return;
		}
		pDest.create(channels, sps, bps, sampleBody);
		const size = sampleBody * channels * bps / 8;
		pDest.pcmSamples[0 .. size] = pcmSamples[0 .. size];
	}

	///
	void copy(ref PxtnPulsePCM pDest, int start, int end) const @safe {
		int size, offset;

		if (!pcmSamples) {
			pDest.release();
			return;
		}

		size = (end - start) * channels * bps / 8;
		offset = start * channels * bps / 8;

		pDest.create(channels, sps, bps, end - start);

		pDest.pcmSamples[0 .. size] = pcmSamples[offset .. offset + size];
	}

	///
	ubyte[] devolveSamplingBuffer() nothrow @safe {
		ubyte[] p = pcmSamples;
		pcmSamples = null;
		return p;
	}

	///
	float getSec() const nothrow @safe {
		return cast(float)sampleBody / cast(float) sps;
	}

	///
	int getChannels() const nothrow @safe {
		return channels;
	}

	///
	int getBPS() const nothrow @safe {
		return bps;
	}

	///
	int getSPS() const nothrow @safe {
		return sps;
	}

	///
	int getSampleBody() const nothrow @safe {
		return sampleBody;
	}

	///
	int getBufferSize() const nothrow @safe {
		return sampleBody * channels * bps / 8;
	}

	///
	inout(ubyte)[] getPCMBuffer() inout nothrow @safe {
		return pcmSamples;
	}
}
