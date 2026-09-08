import { readFileSync } from 'fs';
import { io } from 'socket.io-client';

const workers = JSON.parse(readFileSync('tokens.json', 'utf8'));
const token = workers[0].token;
const url = process.argv[2] || 'http://127.0.0.1:3000';
const mode = process.argv[3] || 'token';

console.log('Probing socket at', url, 'mode', mode);

const auth =
  mode === 'none'
    ? {}
    : mode === 'bearer'
      ? { token: `Bearer ${token}` }
      : { token };

const socket = io(url, {
  transports: ['websocket'],
  auth,
  timeout: 10000,
});

socket.on('connect', () => {
  console.log('CONNECTED', socket.id);
  socket.emit('joinUserRoom', {}, (ack) => console.log('joinUserRoom ack', ack));
  setTimeout(() => {
    socket.disconnect();
    process.exit(0);
  }, 2000);
});

socket.on('connect_error', (err) => {
  console.error('CONNECT_ERROR', err.message, err);
  process.exit(1);
});

socket.on('disconnect', (reason) => {
  console.log('DISCONNECT', reason);
});

setTimeout(() => {
  console.error('TIMEOUT');
  process.exit(1);
}, 15000);
