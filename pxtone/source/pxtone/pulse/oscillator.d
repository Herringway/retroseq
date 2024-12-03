module pxtone.pulse.oscillator;

import pxtone.pxtn;

import std.math;

struct PxtnPulseOscillator {
private:
	const(PxtnPoint)[] pPoint = null;
	int pointNum = 0;
	int pointReso = 0;
	int volume = 0;
	int sampleNum = 0;

public:
	void readyGetSample(return const scope PxtnPoint[] pPoint, int pointNum, int volume, int sampleNum, int pointReso) nothrow @safe scope {
		this.volume = volume;
		this.pPoint = pPoint;
		this.sampleNum = sampleNum;
		this.pointNum = pointNum;
		this.pointReso = pointReso;
	}

	double getOneSampleOvertone(int index) nothrow @safe scope {
		int o;
		double workDouble = 0;
		double pi = 3.1415926535897932;
		double sss;

		for (o = 0; o < pointNum; o++) {
			sss = 2 * pi * (pPoint[o].x) * index / sampleNum;
			workDouble += (sin(sss) * cast(double) pPoint[o].y / (pPoint[o].x) / 128);
		}
		workDouble = workDouble * volume / 128;

		return workDouble;
	}

	double getOneSampleCoordinate(int index) nothrow @safe scope {
		int i;
		int c;
		int x1, y1, x2, y2;
		int w, h;
		double work;

		i = pointReso * index / sampleNum;

		// find target 2 ponits
		c = 0;
		while (c < pointNum) {
			if (pPoint[c].x > i) {
				break;
			}
			c++;
		}

		//末端
		if (c == pointNum) {
			x1 = pPoint[c - 1].x;
			y1 = pPoint[c - 1].y;
			x2 = pointReso;
			y2 = pPoint[0].y;
		} else {
			if (c) {
				x1 = pPoint[c - 1].x;
				y1 = pPoint[c - 1].y;
				x2 = pPoint[c].x;
				y2 = pPoint[c].y;
			} else {
				x1 = pPoint[0].x;
				y1 = pPoint[0].y;
				x2 = pPoint[0].x;
				y2 = pPoint[0].y;
			}
		}

		w = x2 - x1;
		i = i - x1;
		h = y2 - y1;

		if (i) {
			work = cast(double) y1 + cast(double) h * cast(double) i / cast(double) w;
		} else {
			work = y1;
		}

		return work * volume / 128 / 128;

	}
}
