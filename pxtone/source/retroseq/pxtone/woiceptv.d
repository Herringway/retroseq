///
module retroseq.pxtone.woiceptv;
// '12/03/03

import std.exception;

import retroseq.pxtone.descriptor;
import retroseq.pxtone.error;
import retroseq.pxtone.pulse.noise;
import retroseq.pxtone.pxtn;
import retroseq.pxtone.woice;

immutable int expectedVersion = 20060111; /// support no-envelope

///
void writeWave(R)(ref R output, const(PxtnVoiceUnit)* voiceUnit, ref int pTotal) @safe {
	int num, i, size;
	byte sc;
	ubyte uc;

	output.writeVarInt(voiceUnit.type, pTotal);

	switch (voiceUnit.type) {
		// coordinate (3)
	case PxtnVoiceType.coordinate:
		output.writeVarInt(voiceUnit.wave.num, pTotal);
		output.writeVarInt(voiceUnit.wave.reso, pTotal);
		num = voiceUnit.wave.num;
		for (i = 0; i < num; i++) {
			uc = cast(byte) voiceUnit.wave.points[i].x;
			output.write(uc);
			pTotal++;
			sc = cast(byte) voiceUnit.wave.points[i].y;
			output.write(sc);
			pTotal++;
		}
		break;

		// Overtone (2)
	case PxtnVoiceType.overtone:

		output.writeVarInt(voiceUnit.wave.num, pTotal);
		num = voiceUnit.wave.num;
		for (i = 0; i < num; i++) {
			output.writeVarInt(voiceUnit.wave.points[i].x, pTotal);
			output.writeVarInt(voiceUnit.wave.points[i].y, pTotal);
		}
		break;

		// sampling (7)
	case PxtnVoiceType.sampling:
		output.writeVarInt(voiceUnit.pcm.getChannels(), pTotal);
		output.writeVarInt(voiceUnit.pcm.getBPS(), pTotal);
		output.writeVarInt(voiceUnit.pcm.getSPS(), pTotal);
		output.writeVarInt(0, pTotal);
		output.writeVarInt(voiceUnit.pcm.getSampleBody(), pTotal);
		output.writeVarInt(0, pTotal);

		size = voiceUnit.pcm.getBufferSize();

		output.write(voiceUnit.pcm.getPCMBuffer());
		pTotal += size;
		break;

	case PxtnVoiceType.oggVorbis:
		throw new PxtoneException("Ogg Vorbis is not supported here");
	default:
		break;
	}
}

///
void writeEnvelope(R)(ref R output, const(PxtnVoiceUnit)* voiceUnit, ref int pTotal) @safe {
	int num, i;

	// envelope. (5)
	output.writeVarInt(voiceUnit.envelope.fps, pTotal);
	output.writeVarInt(voiceUnit.envelope.headNumber, pTotal);
	output.writeVarInt(voiceUnit.envelope.bodyNumber, pTotal);
	output.writeVarInt(voiceUnit.envelope.tailNumber, pTotal);

	num = voiceUnit.envelope.headNumber + voiceUnit.envelope.bodyNumber + voiceUnit.envelope.tailNumber;
	for (i = 0; i < num; i++) {
		output.writeVarInt(voiceUnit.envelope.points[i].x, pTotal);
		output.writeVarInt(voiceUnit.envelope.points[i].y, pTotal);
	}
}

///
void readWave(ref const(ubyte)[] buffer, PxtnVoiceUnit* voiceUnit) @safe {
	int i, num;
	byte sc;
	ubyte uc;

	buffer.popVarInt(*cast(int*)&voiceUnit.type);

	switch (voiceUnit.type) {
		// coodinate (3)
	case PxtnVoiceType.coordinate:
		buffer.popVarInt(voiceUnit.wave.num);
		buffer.popVarInt(voiceUnit.wave.reso);
		num = voiceUnit.wave.num;
		voiceUnit.wave.points = new PxtnPoint[](num);
		for (i = 0; i < num; i++) {
			buffer.pop(uc);
			voiceUnit.wave.points[i].x = uc;
			buffer.pop(sc);
			voiceUnit.wave.points[i].y = sc;
		}
		num = voiceUnit.wave.num;
		break;
		// overtone (2)
	case PxtnVoiceType.overtone:

		buffer.popVarInt(voiceUnit.wave.num);
		num = voiceUnit.wave.num;
		voiceUnit.wave.points = new PxtnPoint[](num);
		for (i = 0; i < num; i++) {
			buffer.popVarInt(voiceUnit.wave.points[i].x);
			buffer.popVarInt(voiceUnit.wave.points[i].y);
		}
		break;

		// voiceUnit.sampling. (7)
	case PxtnVoiceType.sampling:
		throw new PxtoneException("fmt unknown"); // un-support

		//buffer.popVarInt(voiceUnit.pcm.ch);
		//buffer.popVarInt(voiceUnit.pcm.bps);
		//buffer.popVarInt(voiceUnit.pcm.sps);
		//buffer.popVarInt(voiceUnit.pcm.sampleHead);
		//buffer.popVarInt(voiceUnit.pcm.sampleBody);
		//buffer.popVarInt(voiceUnit.pcm.sampleTail);
		//size = ( voiceUnit.pcm.sampleHead + voiceUnit.pcm.sampleBody + voiceUnit.pcm.sampleTail ) * voiceUnit.pcm.ch * voiceUnit.pcm.bps / 8;
		//if( !_malloc_zero( (void **)&voiceUnit.pcm.p_smp,    size )          ) goto End;
		//if( !buffer.pop(        voiceUnit.pcm.p_smp, 1, size ) ) goto End;
		//break;

	default:
		throw new PxtoneException("PTV not supported"); // un-support
	}
}

///
void readEnvelope(ref const(ubyte)[] buffer, PxtnVoiceUnit* voiceUnit) @safe {
	int num, i;

	scope(failure) {
		voiceUnit.envelope.points = null;
	}
	//voiceUnit.envelope. (5)
	buffer.popVarInt(voiceUnit.envelope.fps);
	buffer.popVarInt(voiceUnit.envelope.headNumber);
	buffer.popVarInt(voiceUnit.envelope.bodyNumber);
	buffer.popVarInt(voiceUnit.envelope.tailNumber);
	enforce!PxtoneException(!voiceUnit.envelope.bodyNumber, "fmt unknown");
	enforce!PxtoneException(voiceUnit.envelope.tailNumber == 1, "fmt unknown");

	num = voiceUnit.envelope.headNumber + voiceUnit.envelope.bodyNumber + voiceUnit.envelope.tailNumber;
	voiceUnit.envelope.points = new PxtnPoint[](num);
	for (i = 0; i < num; i++) {
		buffer.popVarInt(voiceUnit.envelope.points[i].x);
		buffer.popVarInt(voiceUnit.envelope.points[i].y);
	}
}
