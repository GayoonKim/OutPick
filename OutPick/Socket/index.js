import express from "express";
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server } from "socket.io";

const app = express();
const server = createServer(app);
const io = new Server(server);

let rooms = []; // 방 목록 저장

//const __dirname = dirname(fileURLToPath(import.meta.url));
//
//app.get('/', (req, res) => {
//  res.sendFile(join(__dirname, 'index.html'));
//});

io.on('connection', (socket) => {
    console.log('a user connected');
    
    // 사용자 식별을 위한 고유 ID 생성
    socket.on('set user', (user) => {
        socket.user = user
        console.log(`User set: ${user}`);
    });
    
    // 새 방 만들기
    socket.on('create room', (room, description) => {
        rooms.push(room);
        socket.join(room);
        console.log(`Romm created: ${room}: ${description}`);
        io.emit('room list', rooms, description);
    });
    
    // 방 참여
    socket.on('join room', (room) => {
        socket.join(room);
        console.log(`User joined room: ${room}`);
    });
    
    // 방 나가기
    socket.on('leave room', (room) => {
        socket.leave(room);
        console.log(`User left room: ${room}`);
      });
    
    // 방에 메시지 전송
    socket.on('chat message', (msg) => {
        const { room, message } = msg;
        console.log(`message: ${message} to room: ${room}`);
        io.to(room).emit('chat message', message);
      });
    
    
    socket.on('disconnect', () => {
      console.log('user disconnected');
  });
});

server.listen(3000, ()=> {
    console.log('server running at http://localhost:3000');
});

