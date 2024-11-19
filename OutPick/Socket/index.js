import express from "express";
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server } from "socket.io";

const app = express();
const server = createServer(app);
const io = new Server(server);

let rooms = {}; // 방 목록 및 방 별 사용자 관리

const __dirname = dirname(fileURLToPath(import.meta.url));

app.get('/', (req, res) => {
  res.sendFile(join(__dirname, 'index.html'));
});

io.on('connection', (socket) => {
    console.log('a user connected:', socket.id);
    
    // 새 클라이언트 연결 시 방 목록 전송
    socket.emit("room list", Object.keys(rooms));
    
    // 사용자 ID 설정
    socket.on('set username', (username) => {
        socket.username = username || "Anonymous";
        console.log(`User set username: ${socket.username}`);
        socket.emit("username set", socket.username)
    });
    
    // 새 방 만들기
    socket.on('create room', (roomName) => {
        if (!rooms[roomName]) {
            rooms[roomName] = [];
            console.log(`Room created: ${roomName}`);
        }
        
        socket.join(roomName);
        rooms[roomName].push(socket.roomName) || "Anonymous";
        io.emit("room list", Object.keys(rooms)); // 모든 클라이언트에게 방 목록 전송
    });
    
    // 방 참여
    socket.on('join room', (roomName) => {
        if (rooms[roomName]) {
            socket.join(roomName);
            rooms[roomName].push(socket.username || "Anonymous");
            console.log(`${socket.username} joined room: ${roomName}`);
            io.to(roomName).emit("user list", rooms[roomName]); // 해당 방 사용자 목록 전송
        } else {
            socket.emit("error", `Room ${roomName} does not exist`);
        }
    });
    
    // 방 나가기
    socket.on('leave room', (room) => {
        socket.leave(room);
        console.log(`User left room: ${room}`);
      });
    
    // 방에 메시지 전송
    socket.on("chat message", (data) => {
      const { roomName, message } = data;

      if (!roomName || !message) {
        console.error("Invalid data received:", data);
        return;
      }

      console.log(`[${roomName}] ${socket.username}: ${message}`);
      io.to(roomName).emit("chat message", {
        user: socket.username || "Anonymous",
        message,
      });
    });
    
    socket.on('disconnect', () => {
        console.log('User disconnected', socket.id);
        for (const room in rooms) {
            rooms[room] = rooms[room].filter((user) => user !== socket.username);
            io.to(room).emit("user list", rooms[room]); // 참여 유저 목록 갱신
        }
      });
});

server.listen(3000, ()=> {
    console.log('server running at http://localhost:3000');
});
