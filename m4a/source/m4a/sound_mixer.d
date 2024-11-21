module m4a.sound_mixer;

import m4a.mp2k_common;
import m4a.cgb_audio;
import m4a.internal;
import m4a.m4a;


ubyte RunMixerFrame(M4APlayer* player, float[2][] audioBuffer) @system pure {
	int samplesPerFrame = cast(int)audioBuffer.length;

	player.playerCounter += audioBuffer.length;
	while (player.playerCounter >= player.soundInfo.samplesPerFrame) {
		player.playerCounter -= player.soundInfo.samplesPerFrame;
		uint maxScanlines = player.soundInfo.maxScanlines;

		if (player.soundInfo.firstPlayerFunc != null) {
			player.soundInfo.firstPlayerFunc(*player, *player.soundInfo.firstPlayer);
		}

		player.soundInfo.cgbMixerFunc(*player);
	}
	samplesPerFrame = player.soundInfo.samplesPerFrame;
	float[2][] outBuffer = player.soundInfo.outBuffer;
	float[2][] cgbBuffer = player.soundInfo.cgbBuffer;

	int dmaCounter = player.soundInfo.dmaCounter;

	if (dmaCounter > 1) {
		outBuffer = outBuffer[samplesPerFrame * (player.soundInfo.pcmDmaPeriod - (dmaCounter - 1)) .. $];
	}

	//MixerRamFunc mixerRamFunc = ((MixerRamFunc)MixerCodeBuffer);
	SampleMixer(&player.soundInfo, 0, cast(ushort)samplesPerFrame, outBuffer, cast(ubyte)dmaCounter);

	player.gb.audio_generate(&player.soundInfo, cast(ushort)samplesPerFrame, cgbBuffer);

	samplesPerFrame = player.soundInfo.samplesPerFrame;
	float[2][] m4aBuffer = player.soundInfo.outBuffer;
	cgbBuffer = player.soundInfo.cgbBuffer;

	if (dmaCounter > 1) {
		m4aBuffer = m4aBuffer[samplesPerFrame * (player.soundInfo.pcmDmaPeriod - (dmaCounter - 1)) .. $];
	}

	for(uint i = 0; i < audioBuffer.length; i++) {
		audioBuffer[i][0] = m4aBuffer[i][0] + cgbBuffer[i][0];
		audioBuffer[i][1] = m4aBuffer[i][1] + cgbBuffer[i][1];
	}

	if(cast(byte)(--player.soundInfo.dmaCounter) <= 0)
		player.soundInfo.dmaCounter = player.soundInfo.pcmDmaPeriod;

	return 1;
}

//__attribute__((target("thumb")))
void SampleMixer(SoundMixerState *mixer, uint scanlineLimit, ushort samplesPerFrame, float[2][] outBuffer, ubyte dmaCounter) @system pure {
	uint reverb = mixer.reverb;
	if (reverb) {
		// The vanilla reverb effect outputs a mono sound from four sources:
		// - L/R channels as they were mixer.pcmDmaPeriod frames ago
		// - L/R channels as they were (mixer.pcmDmaPeriod - 1) frames ago
		float[2][] tmp1 = outBuffer;
		float[2][] tmp2;
		if (dmaCounter == 2) {
			tmp2 = mixer.outBuffer;
		} else {
			tmp2 = outBuffer[samplesPerFrame .. $];
		}
		ushort i = 0;
		do {
			float s = tmp1[0][0] + tmp1[0][1] + tmp2[0][0] + tmp2[0][1];
			s *= (cast(float)reverb / 512.0f);
			tmp1[0][0] = tmp1[0][1] = s;
			tmp1 = tmp1[1 .. $];
			tmp2 = tmp2[1 .. $];
		}
		while(++i < samplesPerFrame);
	} else {
		// memset(outBuffer, 0, samplesPerFrame);
		// memset(outBuffer + maxBufSize, 0, samplesPerFrame);
		for (int i = 0; i < samplesPerFrame; i++) {
			float[2][] dst = outBuffer[i .. i + 1];
			dst[0][1] = dst[0][0] = 0.0f;
		}
	}

	float divFreq = mixer.divFreq;
	byte numChans = mixer.numChans;
	SoundChannel[] chan = mixer.chans[];

	for (int i = 0; i < numChans; i++, chan = chan[1 .. $]) {
		WaveData *wav = chan[0].wav;

		if (TickEnvelope(&chan[0], wav))
		{

			GenerateAudio(mixer, &chan[0], wav, outBuffer, samplesPerFrame, divFreq);
		}
	}
}

// Returns 1 if channel is still active after moving envelope forward a frame
//__attribute__((target("thumb")))
private uint TickEnvelope(SoundChannel *chan, WaveData *wav) @system pure {
	// MP2K envelope shape
	//                                                                 |
	// (linear)^                                                       |
	// Attack / \Decay (exponential)                                   |
	//       /   \_                                                    |
	//      /      '.,        Sustain                                  |
	//     /          '.______________                                 |
	//    /                           '-.       Echo (linear)          |
	//   /                 Release (exp) ''--..|\                      |
	//  /                                        \                     |

	ubyte status = chan.statusFlags;
	if ((status & 0xC7) == 0) {
		return 0;
	}

	ubyte env = 0;
	ushort newEnv;
	if ((status & 0x80) == 0) {
		env = chan.envelopeVolume;

		if (status & 4) {
			// Note-wise echo
			--chan.echoVolume;
			if (chan.echoVolume <= 0) {
				chan.statusFlags = 0;
				return 0;
			} else {
				return 1;
			}
		} else if (status & 0x40) {
			// Release
			chan.envelopeVolume = env * chan.release / 256U;
			ubyte echoVolume = chan.echoVolume;
			if (chan.envelopeVolume > echoVolume) {
				return 1;
			} else if (echoVolume == 0) {
				chan.statusFlags = 0;
				return 0;
			} else {
				chan.statusFlags |= 4;
				return 1;
			}
		}

		switch (status & 3) {
		case 2:
			// Decay
			chan.envelopeVolume = env * chan.decay / 256U;

			ubyte sustain = chan.sustain;
			if (chan.envelopeVolume <= sustain && sustain == 0) {
				// Duplicated echo check from Release section above
				if (chan.echoVolume == 0) {
					chan.statusFlags = 0;
					return 0;
				} else {
					chan.statusFlags |= 4;
					return 1;
				}
			} else if (chan.envelopeVolume <= sustain) {
				chan.envelopeVolume = sustain;
				--chan.statusFlags;
			}
			break;
		case 3:
		attack:
			newEnv = env + chan.attack;
			if (newEnv > 0xFF) {
				chan.envelopeVolume = 0xFF;
				--chan.statusFlags;
			} else {
				chan.envelopeVolume = cast(ubyte)newEnv;
			}
			break;
		case 1: // Sustain
		default:
			break;
		}

		return 1;
	} else if (status & 0x40) {
		// Init and stop cancel each other out
		chan.statusFlags = 0;
		return 0;
	} else {
		// Init channel
		chan.statusFlags = 3;
		chan.currentPointer = &wav.data[chan.count];
		chan.count = wav.size - chan.count;
		chan.fw = 0;
		chan.envelopeVolume = 0;
		if (wav.loopFlags & 0xC0) {
			chan.statusFlags |= 0x10;
		}
		goto attack;
	}
}

//__attribute__((target("thumb")))
private void GenerateAudio(SoundMixerState *mixer, SoundChannel *chan, WaveData *wav, float[2][] outBuffer, ushort samplesPerFrame, float divFreq) pure {
	ubyte v = cast(ubyte)(chan.envelopeVolume * (mixer.masterVol + 1) / 16U);
	chan.envelopeVolumeRight = chan.rightVolume * v / 256U;
	chan.envelopeVolumeLeft = chan.leftVolume * v / 256U;

	int loopLen = 0;
	byte *loopStart;
	if (chan.statusFlags & 0x10) {
		loopStart = &wav.data[0] + wav.loopStart;
		loopLen = wav.size - wav.loopStart;
	}
	int samplesLeftInWav = chan.count;
	byte *currentPointer = chan.currentPointer;
	int envR = chan.envelopeVolumeRight;
	int envL = chan.envelopeVolumeLeft;
	/*if (chan.type & 8) {
		for (ushort i = 0; i < samplesPerFrame; i++, outBuffer+=2) {
			byte c = *(currentPointer++);

			outBuffer[1] += (c * envR) / 32768.0f;
			outBuffer[0] += (c * envL) / 32768.0f;
			if (--samplesLeftInWav == 0) {
				samplesLeftInWav = loopLen;
				if (loopLen != 0) {
					currentPointer = loopStart;
				} else {
					chan.statusFlags = 0;
					return;
				}
			}
		}

		chan.count = samplesLeftInWav;
		chan.currentPointer = currentPointer;
	} else {*/
	float finePos = chan.fw;
	float romSamplesPerOutputSample = divFreq;

	if (chan.type == 8){
		romSamplesPerOutputSample *= mixer.origFreq;
	}else{
		romSamplesPerOutputSample *= chan.freq;
	}
	short b = currentPointer[0];
	short m = cast(short)(currentPointer[1] - b);
	currentPointer += 1;

	for (ushort i = 0; i < samplesPerFrame; i++, outBuffer = outBuffer[1 .. $]) {
		// Use linear interpolation to calculate a value between the currentPointer sample in the wav
		// and the nextChannelPointer sample. Also cancel out the 9.23 stuff
		float sample = (finePos * m) + b;

		outBuffer[0][1] += (sample * envR) / 32768.0f;
		outBuffer[0][0] += (sample * envL) / 32768.0f;

		finePos += romSamplesPerOutputSample;
		uint newCoarsePos = cast(uint)finePos;
		if (newCoarsePos != 0) {
			finePos -= cast(int)finePos;
			samplesLeftInWav -= newCoarsePos;
			if (samplesLeftInWav <= 0) {
				if (loopLen != 0) {
					currentPointer = loopStart;
					newCoarsePos = -samplesLeftInWav;
					samplesLeftInWav += loopLen;
					while (samplesLeftInWav <= 0) {
						newCoarsePos -= loopLen;
						samplesLeftInWav += loopLen;
					}
					b = currentPointer[newCoarsePos];
					m = cast(short)(currentPointer[newCoarsePos + 1] - b);
					currentPointer += newCoarsePos + 1;
				} else {
					chan.statusFlags = 0;
					return;
				}
			} else {
				b = currentPointer[newCoarsePos - 1];
				m = cast(short)(currentPointer[newCoarsePos] - b);
				currentPointer += newCoarsePos;
			}
		}
	}

	chan.fw = finePos;
	chan.count = samplesLeftInWav;
	chan.currentPointer = currentPointer - 1;
	//}
}
