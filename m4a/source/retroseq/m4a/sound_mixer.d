///
module retroseq.m4a.sound_mixer;

import retroseq.interpolation;
import retroseq.m4a.cgb_audio;
import retroseq.m4a.internal;
import retroseq.m4a.m4a;
import retroseq.m4a.music_player;

import std.range : chain, cycle;

///
void RunMixerFrame(ref M4APlayer player, float[2][] audioBuffer) @safe pure
	in(audioBuffer.length == player.soundInfo.samplesPerFrame, "Invalid buffer size")
{
	player.playerCounter += player.soundInfo.samplesPerFrame;
	while (player.playerCounter >= player.soundInfo.samplesPerFrame) {
		player.playerCounter -= player.soundInfo.samplesPerFrame;

		MP2KPlayerMain(player);

		player.cgbMixerFunc();
	}
	float[2][] outBuffer = player.soundInfo.outBuffer;

	if (player.soundInfo.dmaCounter > 1) {
		outBuffer = outBuffer[player.soundInfo.samplesPerFrame * (player.soundInfo.pcmDmaPeriod - (player.soundInfo.dmaCounter - 1)) .. $];
	}

	SampleMixer(player.soundInfo, 0, cast(ushort)player.soundInfo.samplesPerFrame, outBuffer, cast(ubyte)player.soundInfo.dmaCounter);

	player.gb.audio_generate(player.soundInfo, audioBuffer[0 .. player.soundInfo.samplesPerFrame]);

	for (uint i = 0; i < audioBuffer.length; i++) {
		audioBuffer[i][0] += outBuffer[i][0];
		audioBuffer[i][1] += outBuffer[i][1];
	}

	if (cast(byte)(--player.soundInfo.dmaCounter) <= 0) {
		player.soundInfo.dmaCounter = player.soundInfo.pcmDmaPeriod;
	}
}

///
void SampleMixer(ref SoundMixerState mixer, uint scanlineLimit, ushort samplesPerFrame, float[2][] outBuffer, ubyte dmaCounter) @safe pure {
	if (mixer.reverb) {
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
			version(vanillaReverb) {
				float s = tmp1[0][0] + tmp1[0][1] + tmp2[0][0] + tmp2[0][1];
				s *= (cast(float)mixer.reverb / 512.0f);
				tmp1[0][0] = tmp1[0][1] = s;
			} else {
				float[2] s = [ tmp1[0][0] + tmp2[0][0], tmp1[0][1]  + tmp2[0][1] ];
				s[] *= (cast(float)mixer.reverb / 512.0f);
				tmp1[0] = s;
			}
			tmp1 = tmp1[1 .. $];
			tmp2 = tmp2[1 .. $];
		} while (++i < samplesPerFrame);
	} else {
		outBuffer[0 .. samplesPerFrame][] = [ 0, 0 ];
	}

	foreach (ref chan; mixer.chans) {
		if (TickEnvelope(chan, chan.wav)) {
			GenerateAudio(mixer, chan, chan.wav, outBuffer[0 .. samplesPerFrame], mixer.divFreq);
		}
	}
}

/// Returns 1 if channel is still active after moving envelope forward a frame
private uint TickEnvelope(ref SoundChannel chan, const Wave wav) @safe pure {
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

	if (!chan.isActive) {
		return 0;
	}

	static void attack(ubyte env, ref SoundChannel chan) {
		const newEnv = env + chan.attack;
		if (newEnv > 0xFF) {
			chan.envelopeVolume = 0xFF;
			--chan.statusFlags;
		} else {
			chan.envelopeVolume = cast(ubyte)newEnv;
		}
	}
	ubyte env = 0;
	if (!chan.start) {
		env = chan.envelopeVolume;

		if (chan.echoEnabled) {
			// Note-wise echo
			--chan.echoVolume;
			if (chan.echoVolume <= 0) {
				chan.statusFlags = 0;
				return 0;
			} else {
				return 1;
			}
		} else if (chan.stop) {
			// Release
			chan.envelopeVolume = env * chan.release / 256U;
			ubyte echoVolume = chan.echoVolume;
			if (chan.envelopeVolume > echoVolume) {
				return 1;
			} else if (echoVolume == 0) {
				chan.statusFlags = 0;
				return 0;
			} else {
				chan.echoEnabled = true;
				return 1;
			}
		}

		final switch (chan.envelopeState) {
		case EnvelopeState.decay:
			chan.envelopeVolume = env * chan.decay / 256U;

			ubyte sustain = chan.sustain;
			if ((chan.envelopeVolume <= sustain) && (sustain == 0)) {
				// Duplicated echo check from Release section above
				if (chan.echoVolume == 0) {
					chan.statusFlags = 0;
					return 0;
				} else {
					chan.echoEnabled = true;
					return 1;
				}
			} else if (chan.envelopeVolume <= sustain) {
				chan.envelopeVolume = sustain;
				--chan.statusFlags;
			}
			break;
		case EnvelopeState.attack:
			attack(env, chan);
			break;
		case EnvelopeState.sustain:
		case EnvelopeState.release:
			break;
		}

		return 1;
	} else if (chan.stop) {
		// Init and stop cancel each other out
		chan.statusFlags = 0;
		return 0;
	} else {
		// Init channel
		chan.statusFlags = 0;
		chan.envelopeState = EnvelopeState.attack;
		chan.currentPointer = wav.sample[chan.count .. $];
		chan.count = wav.header.size - chan.count;
		chan.samplePosition = 0;
		chan.envelopeVolume = 0;
		chan.loop = !!(wav.header.loopFlags & 0xC0);
		attack(env, chan);
		return 1;
	}
}

///
private void GenerateAudio(ref SoundMixerState mixer, ref SoundChannel chan, const Wave wav, float[2][] outBuffer, float romSamplesPerOutputSample) @safe pure {
	ubyte v = cast(ubyte)(chan.envelopeVolume * (mixer.masterVol + 1) / 16);
	chan.envelopeVolumeRight = chan.rightVolume * v / 256;
	chan.envelopeVolumeLeft = chan.leftVolume * v / 256;

	// have the sample repeat infinitely, either with 0s if it doesn't loop or the sample starting at its loop point if it does
	const(byte)[] loopStart = [0];
	if (chan.loop) {
		loopStart = wav.sample[wav.header.loopStart .. $];
	}
	auto samples = chan.currentPointer.chain(loopStart.cycle);

	if (chan.fix) {
		romSamplesPerOutputSample *= mixer.origFreq;
	} else {
		romSamplesPerOutputSample *= chan.freq;
	}

	foreach (ref output; outBuffer) {
		// Use linear interpolation to calculate a value between the currentPointer sample in the wav and the nextChannelPointer sample. Also cancel out the 9.23 stuff
		float sample = linearInterpolation(samples[cast(uint)chan.samplePosition], samples[cast(uint)chan.samplePosition + 1], chan.samplePosition % 1);

		output[0] += (sample * chan.envelopeVolumeLeft) / 32768.0;
		output[1] += (sample * chan.envelopeVolumeRight) / 32768.0;

		chan.samplePosition += romSamplesPerOutputSample;
		if (!chan.loop && (chan.samplePosition > chan.count)) {
			chan.statusFlags = 0;
		}
	}
}
