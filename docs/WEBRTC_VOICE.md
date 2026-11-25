# In-app WebRTC voice (booking Call)

## Stack
- Signaling: Socket.IO events `voice_call_invite|accept|reject|hangup|signal`
- ICE: `GET /bookings/:id/webrtc-config` (STUN + optional TURN)
- Media: P2P via `flutter_webrtc`; Coturn TURN for cellular NAT

## Env (backend `.env`)
```
WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302
WEBRTC_TURN_URLS=turn:103.102.234.152:3478?transport=udp,turn:103.102.234.152:3478?transport=tcp
WEBRTC_TURN_USERNAME=gixbee
WEBRTC_TURN_CREDENTIAL=gixbee_turn_dev
```
Match `TURN_CREDENTIAL` / `TURN_EXTERNAL_IP` for the `coturn` service in `docker-compose.yml`.

## Security group
Open UDP/TCP **3478** and UDP **49160–49200** on the MilesWeb VPS for Coturn.

## Fallback
If mic permission fails or invite errors, the app opens the phone dialer (`tel:`) when a counterpart number is available.
