///
module pxtone.master;
// '12/03/03

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.evelist;
import pxtone.util;

/////////////////////////////////
// file io
/////////////////////////////////

// master info(8byte) ================
///
struct Master {
	ushort dataNumber; /// data-num is 3 (clock / status / volume)
	ushort rrr; ///
	uint eventNumber; ///
}

///
struct PxtnMaster {
private:
	int beatNum = EventDefault.beatNumber; ///
	float beatTempo = EventDefault.beatTempo; ///
	int beatClock = EventDefault.beatClock; ///
	int measNum = 1; ///
	int repeatMeas; ///
	int lastMeas; ///
	int volume; ///

public:
	///
	void reset() nothrow @safe {
		beatNum = EventDefault.beatNumber;
		beatTempo = EventDefault.beatTempo;
		beatClock = EventDefault.beatClock;
		measNum = 1;
		repeatMeas = 0;
		lastMeas = 0;
	}

	///
	void set(int beatNum, float beatTempo, int beatClock) nothrow @safe {
		this.beatNum = beatNum;
		this.beatTempo = beatTempo;
		this.beatClock = beatClock;
	}

	///
	void get(out int pBeatNum, out float pBeatTempo, out int pBeatClock, out int pMeasNum) const nothrow @safe {
		pBeatNum = this.beatNum;
		pBeatTempo = this.beatTempo;
		pBeatClock = this.beatClock;
		pMeasNum = this.measNum;
	}

	///
	int getBeatNum() const nothrow @safe {
		return beatNum;
	}

	///
	float getBeatTempo() const nothrow @safe {
		return beatTempo;
	}

	///
	int getBeatClock() const nothrow @safe {
		return beatClock;
	}

	///
	int getMeasNum() const nothrow @safe {
		return measNum;
	}

	///
	int getRepeatMeas() const nothrow @safe {
		return repeatMeas;
	}

	///
	int getLastMeas() const nothrow @safe {
		return lastMeas;
	}

	///
	int getLastClock() const nothrow @safe {
		return lastMeas * beatClock * beatNum;
	}

	///
	int getPlayMeas() const nothrow @safe {
		if (lastMeas) {
			return lastMeas;
		}
		return measNum;
	}

	///
	void setMeasNum(int measNum) nothrow @safe {
		if (measNum < 1) {
			measNum = 1;
		}
		if (measNum <= repeatMeas) {
			measNum = repeatMeas + 1;
		}
		if (measNum < lastMeas) {
			measNum = lastMeas;
		}
		this.measNum = measNum;
	}

	///
	void setRepeatMeas(int meas) nothrow @safe {
		if (meas < 0) {
			meas = 0;
		}
		repeatMeas = meas;
	}

	///
	void setLastMeas(int meas) nothrow @safe {
		if (meas < 0) {
			meas = 0;
		}
		lastMeas = meas;
	}

	///
	void setBeatClock(int beatClock) nothrow @safe {
		if (beatClock < 0) {
			beatClock = 0;
		}
		this.beatClock = beatClock;
	}

	///
	void adjustMeasNum(int clock) nothrow @safe {
		int mNum;
		int bNum;

		bNum = (clock + beatClock - 1) / beatClock;
		mNum = (bNum + beatNum - 1) / beatNum;
		if (measNum <= mNum) {
			measNum = mNum;
		}
		if (repeatMeas >= measNum) {
			repeatMeas = 0;
		}
		if (lastMeas > measNum) {
			lastMeas = measNum;
		}
	}

	///
	int getThisClock(int meas, int beat, int clock) const nothrow @safe {
		return beatNum * beatClock * meas + beatClock * beat + clock;
	}

	///
	void ioWrite(ref PxtnDescriptor pDoc, int rough) const @safe {
		uint size = 15;
		short bclock = cast(short)(beatClock / rough);
		int clockRepeat = bclock * beatNum * getRepeatMeas();
		int clockLast = bclock * beatNum * getLastMeas();
		byte bnum = cast(byte) beatNum;
		float btempo = beatTempo;
		pDoc.write(size);
		pDoc.write(bclock);
		pDoc.write(bnum);
		pDoc.write(btempo);
		pDoc.write(clockRepeat);
		pDoc.write(clockLast);
	}

	///
	void ioRead(ref PxtnDescriptor pDoc) @safe {
		short beatClock = 0;
		byte beatNum = 0;
		float beatTempo = 0;
		int clockRepeat = 0;
		int clockLast = 0;

		uint size = 0;

		pDoc.read(size);
		if (size != 15) {
			throw new PxtoneException("fmt unknown");
		}

		pDoc.read(beatClock);
		pDoc.read(beatNum);
		pDoc.read(beatTempo);
		pDoc.read(clockRepeat);
		pDoc.read(clockLast);

		this.beatClock = beatClock;
		this.beatNum = beatNum;
		this.beatTempo = beatTempo;

		setRepeatMeas(clockRepeat / (beatNum * beatClock));
		setLastMeas(clockLast / (beatNum * beatClock));
	}

	///
	int ioReadEventNumber(ref PxtnDescriptor pDoc) @safe {
		uint size;
		pDoc.read(size);
		if (size != 15) {
			return 0;
		}
		byte[15] buf;
		pDoc.read(buf[]);
		return 5;
	}

	///
	void ioReadOld(ref PxtnDescriptor pDoc) @safe {
		Master mast;
		int size = 0;
		int e = 0;
		int status = 0;
		int clock = 0;
		int volume = 0;
		int absolute = 0;

		int beatClock, beatNum, repeatClock, lastClock;
		float beatTempo = 0;

		pDoc.read(size);
		pDoc.read(mast);

		// unknown format
		if (mast.dataNumber != 3) {
			throw new PxtoneException("fmt unknown");
		}
		if (mast.rrr) {
			throw new PxtoneException("fmt unknown");
		}

		beatClock = EventDefault.beatClock;
		beatNum = EventDefault.beatNumber;
		beatTempo = EventDefault.beatTempo;
		repeatClock = 0;
		lastClock = 0;

		absolute = 0;

		for (e = 0; e < cast(int) mast.eventNumber; e++) {
			pDoc.readVarInt(status);
			pDoc.readVarInt(clock);
			pDoc.readVarInt(volume);
			absolute += clock;
			clock = absolute;

			switch (status) {
			case EventKind.beatClock:
				beatClock = volume;
				if (clock) {
					throw new PxtoneException("desc broken");
				}
				break;
			case EventKind.beatTempo:
				beatTempo = reinterpretInt(volume);
				if (clock) {
					throw new PxtoneException("desc broken");
				}
				break;
			case EventKind.beatNumber:
				beatNum = volume;
				if (clock) {
					throw new PxtoneException("desc broken");
				}
				break;
			case EventKind.repeat:
				repeatClock = clock;
				if (volume) {
					throw new PxtoneException("desc broken");
				}
				break;
			case EventKind.last:
				lastClock = clock;
				if (volume) {
					throw new PxtoneException("desc broken");
				}
				break;
			default:
				throw new PxtoneException("fmt unknown");
			}
		}

		if (e != mast.eventNumber) {
			throw new PxtoneException("desc broken");
		}

		this.beatNum = beatNum;
		this.beatTempo = beatTempo;
		this.beatClock = beatClock;

		setRepeatMeas(repeatClock / (beatNum * beatClock));
		setLastMeas(lastClock / (beatNum * beatClock));
	}

	///
	int ioReadOldEventNumber(ref PxtnDescriptor pDoc) @safe {
		Master mast;
		int size;
		int work;
		int e;

		pDoc.read(size);
		pDoc.read(mast);

		if (mast.dataNumber != 3) {
			return 0;
		}

		for (e = 0; e < cast(int) mast.eventNumber; e++) {
			pDoc.readVarInt(work);
			pDoc.readVarInt(work);
			pDoc.readVarInt(work);
		}

		return mast.eventNumber;
	}
}
