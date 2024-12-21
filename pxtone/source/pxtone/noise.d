///
module pxtone.noise;

// '12/03/29

import pxtone.descriptor;

import pxtone.pulse.noisebuilder;
import pxtone.pulse.noise;
import pxtone.pulse.pcm;
import pxtone.error;

///
struct PxtoneNoise {
	private PxtnPulseNoiseBuilder bldr; ///
	private int channels = 2; ///
	private int sps = 44100; ///
	private int bps = 16; ///

	///
	void qualitySet(int channels, int sps, int bps) @safe {
		switch (channels) {
		case 1:
		case 2:
			break;
		default:
			throw new PxtoneException("Invalid channel count");
		}

		switch (sps) {
		case 48000:
		case 44100:
		case 22050:
		case 11025:
			break;
		default:
			throw new PxtoneException("Invalid sample rate");
		}

		switch (bps) {
		case 8:
		case 16:
			break;
		default:
			throw new PxtoneException("Invalid bps");
		}

		this.channels = channels;
		this.bps = bps;
		this.sps = sps;
	}

	///
	void qualityGet(out int pChannels, out int pSPS, out int pBPS) const nothrow @safe {
		if (pChannels) {
			pChannels = channels;
		}
		if (pSPS) {
			pSPS = sps;
		}
		if (pBPS) {
			pBPS = bps;
		}
	}

	///
	void generate(ref PxtnDescriptor pDoc, out void[] ppBuf, out int pSize) const @safe {
		PxtnPulseNoise noise;

		noise.read(pDoc);
		PxtnPulsePCM pcm = bldr.buildNoise(noise, channels, sps, bps);

		pSize = pcm.getBufferSize();
		ppBuf = pcm.devolveSamplingBuffer();
	}
}
