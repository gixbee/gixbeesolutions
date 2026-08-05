import { VoiceCallsService } from './voice-calls.service';

describe('VoiceCallsService.getIceServers', () => {
  function makeService(env: Record<string, string | undefined>) {
    const config = {
      get: (key: string, fallback?: string) =>
        env[key] !== undefined ? env[key] : fallback,
    };
    return new VoiceCallsService(
      {} as any,
      {} as any,
      config as any,
    );
  }

  it('always includes STUN servers', () => {
    const svc = makeService({});
    const { iceServers } = svc.getIceServers();
    expect(iceServers.length).toBeGreaterThanOrEqual(1);
    const urls = iceServers[0].urls;
    const list = Array.isArray(urls) ? urls : [urls];
    expect(list.some((u) => String(u).startsWith('stun:'))).toBe(true);
  });

  it('adds static TURN when username/credential set', () => {
    const svc = makeService({
      WEBRTC_TURN_URLS: 'turn:example.com:3478',
      WEBRTC_TURN_USERNAME: 'gixbee',
      WEBRTC_TURN_CREDENTIAL: 'secret',
    });
    const { iceServers } = svc.getIceServers();
    const turn = iceServers.find((s) => s.username === 'gixbee');
    expect(turn).toBeDefined();
    expect(turn!.credential).toBe('secret');
  });
});
