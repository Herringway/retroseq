module pxtone.delay;

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.max;

enum DelayUnit {
	Beat = 0,
	Meas,
	Second,
	num,
}

// (12byte) =================
struct Delay {
	ushort unit;
	ushort group;
	float rate = 0.0;
	float freq = 0.0;
}

struct PxtnDelay {
private:
	bool bPlayed = true;
	DelayUnit unit = DelayUnit.Beat;
	int group = 0;
	float rate = 33.0;
	float freq = 3.0f;

	int sampleNum = 0;
	int offset = 0;
	int[][pxtnMaxChannel] bufs = null;
	int rateS32 = 0;

public:

	 ~this() nothrow @safe {
		toneRelease();
	}

	DelayUnit getUnit() const nothrow @safe {
		return unit;
	}

	int getGroup() const nothrow @safe {
		return group;
	}

	float getRate() const nothrow @safe {
		return rate;
	}

	float getFreq() const nothrow @safe {
		return freq;
	}

	void set(DelayUnit unit, float freq, float rate, int group) nothrow @safe {
		this.unit = unit;
		this.group = group;
		this.rate = rate;
		this.freq = freq;
	}

	bool getPlayed() const nothrow @safe {
		return bPlayed;
	}

	void setPlayed(bool b) nothrow @safe {
		bPlayed = b;
	}

	bool switchPlayed() nothrow @safe {
		bPlayed = !bPlayed;
		return bPlayed;
	}

	void toneRelease() nothrow @safe {
		bufs = null;
		sampleNum = 0;
	}

	void toneReady(int beatNum, float beatTempo, int sps) @safe {
		toneRelease();

		scope(failure) {
			toneRelease();
		}
		if (freq && rate) {
			offset = 0;
			rateS32 = cast(int) rate; // /100;

			switch (unit) {
			case DelayUnit.Beat:
				sampleNum = cast(int)(sps * 60 / beatTempo / freq);
				break;
			case DelayUnit.Meas:
				sampleNum = cast(int)(sps * 60 * beatNum / beatTempo / freq);
				break;
			case DelayUnit.Second:
				sampleNum = cast(int)(sps / freq);
				break;
			default:
				break;
			}

			for (int c = 0; c < pxtnMaxChannel; c++) {
				bufs[c] = new int[](sampleNum);
			}
		}
	}

	void toneSupple(int ch, int[] groupSamples) nothrow @safe {
		if (!sampleNum) {
			return;
		}
		int a = bufs[ch][offset] * rateS32 / 100;
		if (bPlayed) {
			groupSamples[group] += a;
		}
		bufs[ch][offset] = groupSamples[group];
	}

	void toneIncrement() nothrow @safe {
		if (!sampleNum) {
			return;
		}
		if (++offset >= sampleNum) {
			offset = 0;
		}
	}

	void toneClear() nothrow @safe {
		if (!sampleNum) {
			return;
		}
		int def = 0; // ..
		for (int i = 0; i < pxtnMaxChannel; i++) {
			bufs[i][0 .. sampleNum] = def;
		}
	}
}
