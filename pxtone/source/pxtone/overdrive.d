///
module pxtone.overdrive;
// '12/03/03

import pxtone.pxtn;
import pxtone.error;
import pxtone.descriptor;

private enum tuneOverdriveCutMax = 99.9f; ///
private enum tuneOverdriveCutMin = 50.0f; ///
private enum tuneOverdriveAmpMax = 8.0f; ///
private enum tuneOverdriveAmpMin = 0.1f; ///
private enum tuneOverdriveDefaultCut = 90.0f; ///
private enum tuneOverdriveDefaultAmp = 2.0f; ///

///
struct pxtnOverDrive {
	bool played = true; ///

	int group; ///
	float cut; ///
	float amp; ///

	int cut16BitTop; ///

	///
	float getCut() const nothrow @safe {
		return cut;
	}

	///
	float getAmp() const nothrow @safe {
		return amp;
	}

	///
	int getGroup() const nothrow @safe {
		return group;
	}

	///
	void set(float cut, float amp, int group) nothrow @safe {
		this.cut = cut;
		this.amp = amp;
		this.group = group;
	}

	///
	bool getPlayed() const nothrow @safe {
		return played;
	}

	///
	void setPlayed(bool b) nothrow @safe {
		played = b;
	}

	///
	bool switchPlayed() nothrow @safe {
		played = played ? false : true;
		return played;
	}

	///
	void toneReady() nothrow @safe {
		cut16BitTop = cast(int)(32767 * (100 - cut) / 100);
	}

	///
	void toneSupple(int[] groupSamples) const nothrow @safe {
		if (!played) {
			return;
		}
		int work = groupSamples[group];
		if (work > cut16BitTop) {
			work = cut16BitTop;
		} else if (work < -cut16BitTop) {
			work = -cut16BitTop;
		}
		groupSamples[group] = cast(int)(cast(float) work * amp);
	}

	///
	void write(ref PxtnDescriptor pDoc) const @safe {
		Overdrive over;
		int size;

		over.cut = cut;
		over.amp = amp;
		over.group = cast(ushort) group;

		// dela ----------
		size = Overdrive.sizeof;
		pDoc.write(size);
		pDoc.write(over);
	}

	///
	void read(ref PxtnDescriptor pDoc) @safe {
		Overdrive over;
		int size = 0;

		pDoc.read(size);
		pDoc.read(over);

		if (over.xxx) {
			throw new PxtoneException("fmt unknown");
		}
		if (over.yyy) {
			throw new PxtoneException("fmt unknown");
		}
		if (over.cut > tuneOverdriveCutMax || over.cut < tuneOverdriveCutMin) {
			throw new PxtoneException("fmt unknown");
		}
		if (over.amp > tuneOverdriveAmpMax || over.amp < tuneOverdriveAmpMin) {
			throw new PxtoneException("fmt unknown");
		}

		cut = over.cut;
		amp = over.amp;
		group = over.group;
	}
}

// (8byte) =================
///
struct Overdrive {
	ushort xxx; ///
	ushort group; ///
	float cut = 0.0; ///
	float amp = 0.0; ///
	float yyy = 0.0; ///
}
