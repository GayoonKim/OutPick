import express from "express";
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server } from "socket.io";

const app = express();
const server = createServer(app);
const io = new Server(server);

io.on('connection', (socket) => {
    console.log('a user connected');

    // 방 참여
    socket.on('join room', (room, user) => {
        socket.join(room);
//      console.log(socket.rooms)
        console.log(`${user} joined room: ${room}`);
    });
    
    // 방 나가기
    socket.on('leave room', (room, user) => {
        socket.leave(room);
        console.log(`${user} left room: ${room}`);
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
