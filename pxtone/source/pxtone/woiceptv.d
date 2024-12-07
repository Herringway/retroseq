///
module pxtone.woiceptv;
// '12/03/03

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.pulse.noise;
import pxtone.woice;

immutable int expectedVersion = 20060111; /// support no-envelope

///
void writeWave(ref PxtnDescriptor pDoc, const(PxtnVoiceUnit)* voiceUnit, ref int pTotal) @safe {
	int num, i, size;
	byte sc;
	ubyte uc;

	pDoc.writeVarInt(voiceUnit.type, pTotal);

	switch (voiceUnit.type) {
		// coordinate (3)
	case PxtnVoiceType.coordinate:
		pDoc.writeVarInt(voiceUnit.wave.num, pTotal);
		pDoc.writeVarInt(voiceUnit.wave.reso, pTotal);
		num = voiceUnit.wave.num;
		for (i = 0; i < num; i++) {
			uc = cast(byte) voiceUnit.wave.points[i].x;
			pDoc.write(uc);
			pTotal++;
			sc = cast(byte) voiceUnit.wave.points[i].y;
			pDoc.write(sc);
			pTotal++;
		}
		break;

		// Overtone (2)
	case PxtnVoiceType.overtone:

		pDoc.writeVarInt(voiceUnit.wave.num, pTotal);
		num = voiceUnit.wave.num;
		for (i = 0; i < num; i++) {
			pDoc.writeVarInt(voiceUnit.wave.points[i].x, pTotal);
			pDoc.writeVarInt(voiceUnit.wave.points[i].y, pTotal);
		}
		break;

		// sampling (7)
	case PxtnVoiceType.sampling:
		pDoc.writeVarInt(voiceUnit.pcm.getChannels(), pTotal);
		pDoc.writeVarInt(voiceUnit.pcm.getBPS(), pTotal);
		pDoc.writeVarInt(voiceUnit.pcm.getSPS(), pTotal);
		pDoc.writeVarInt(voiceUnit.pcm.getSampleHead(), pTotal);
		pDoc.writeVarInt(voiceUnit.pcm.getSampleBody(), pTotal);
		pDoc.writeVarInt(voiceUnit.pcm.getSampleTail(), pTotal);

		size = voiceUnit.pcm.getBufferSize();

		pDoc.write(voiceUnit.pcm.getPCMBuffer());
		pTotal += size;
		break;

	case PxtnVoiceType.oggVorbis:
		throw new PxtoneException("Ogg Vorbis is not supported here");
	default:
		break;
	}
}

///
void writeEnvelope(ref PxtnDescriptor pDoc, const(PxtnVoiceUnit)* voiceUnit, ref int pTotal) @safe {
	int num, i;

	// envelope. (5)
	pDoc.writeVarInt(voiceUnit.envelope.fps, pTotal);
	pDoc.writeVarInt(voiceUnit.envelope.headNumber, pTotal);
	pDoc.writeVarInt(voiceUnit.envelope.bodyNumber, pTotal);
	pDoc.writeVarInt(voiceUnit.envelope.tailNumber, pTotal);

	num = voiceUnit.envelope.headNumber + voiceUnit.envelope.bodyNumber + voiceUnit.envelope.tailNumber;
	for (i = 0; i < num; i++) {
		pDoc.writeVarInt(voiceUnit.envelope.points[i].x, pTotal);
		pDoc.writeVarInt(voiceUnit.envelope.points[i].y, pTotal);
	}
}

///
void readWave(ref PxtnDescriptor pDoc, PxtnVoiceUnit* voiceUnit) @safe {
	int i, num;
	byte sc;
	ubyte uc;

	pDoc.readVarInt(*cast(int*)&voiceUnit.type);

	switch (voiceUnit.type) {
		// coodinate (3)
	case PxtnVoiceType.coordinate:
		pDoc.readVarInt(voiceUnit.wave.num);
		pDoc.readVarInt(voiceUnit.wave.reso);
		num = voiceUnit.wave.num;
		voiceUnit.wave.points = new PxtnPoint[](num);
		for (i = 0; i < num; i++) {
			pDoc.read(uc);
			voiceUnit.wave.points[i].x = uc;
			pDoc.read(sc);
			voiceUnit.wave.points[i].y = sc;
		}
		num = voiceUnit.wave.num;
		break;
		// overtone (2)
	case PxtnVoiceType.overtone:

		pDoc.readVarInt(voiceUnit.wave.num);
		num = voiceUnit.wave.num;
		voiceUnit.wave.points = new PxtnPoint[](num);
		for (i = 0; i < num; i++) {
			pDoc.readVarInt(voiceUnit.wave.points[i].x);
			pDoc.readVarInt(voiceUnit.wave.points[i].y);
		}
		break;

		// voiceUnit.sampling. (7)
	case PxtnVoiceType.sampling:
		throw new PxtoneException("fmt unknown"); // un-support

		//pDoc.readVarInt(voiceUnit.pcm.ch);
		//pDoc.readVarInt(voiceUnit.pcm.bps);
		//pDoc.readVarInt(voiceUnit.pcm.sps);
		//pDoc.readVarInt(voiceUnit.pcm.sampleHead);
		//pDoc.readVarInt(voiceUnit.pcm.sampleBody);
		//pDoc.readVarInt(voiceUnit.pcm.sampleTail);
		//size = ( voiceUnit.pcm.sampleHead + voiceUnit.pcm.sampleBody + voiceUnit.pcm.sampleTail ) * voiceUnit.pcm.ch * voiceUnit.pcm.bps / 8;
		//if( !_malloc_zero( (void **)&voiceUnit.pcm.p_smp,    size )          ) goto End;
		//if( !pDoc.read(        voiceUnit.pcm.p_smp, 1, size ) ) goto End;
		//break;

	default:
		throw new PxtoneException("PTV not supported"); // un-support
	}
}

///
void readEnvelope(ref PxtnDescriptor pDoc, PxtnVoiceUnit* voiceUnit) @safe {
	int num, i;

	scope(failure) {
		voiceUnit.envelope.points = null;
	}
	//voiceUnit.envelope. (5)
	pDoc.readVarInt(voiceUnit.envelope.fps);
	pDoc.readVarInt(voiceUnit.envelope.headNumber);
	pDoc.readVarInt(voiceUnit.envelope.bodyNumber);
	pDoc.readVarInt(voiceUnit.envelope.tailNumber);
	if (voiceUnit.envelope.bodyNumber) {
		throw new PxtoneException("fmt unknown");
	}
	if (voiceUnit.envelope.tailNumber != 1) {
		throw new PxtoneException("fmt unknown");
	}

	num = voiceUnit.envelope.headNumber + voiceUnit.envelope.bodyNumber + voiceUnit.envelope.tailNumber;
	voiceUnit.envelope.points = new PxtnPoint[](num);
	for (i = 0; i < num; i++) {
		pDoc.readVarInt(voiceUnit.envelope.points[i].x);
		pDoc.readVarInt(voiceUnit.envelope.points[i].y);
	}
}
