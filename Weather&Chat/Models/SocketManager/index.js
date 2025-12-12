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
    socket.on('create room', (roomID) => {
        if (!rooms[roomID]) {
            rooms[roomID] = [];
            console.log(`[Room created] ${roomID}`);
        }
        socket.username = socket.username || "Anonymous";
        socket.join(roomID);
        // Only add if not already present
        if (!rooms[roomID].includes(socket.username)) {
            rooms[roomID].push(socket.username);
        }
        io.emit("room list", Object.keys(rooms)); // 모든 클라이언트에게 방 목록 전송
        io.to(roomID).emit("user list", rooms[roomID]); // 방 사용자 목록 전송
    });
    
    // 방 참여
    socket.on('join room', (roomID) => {
        if (rooms[roomID]) {
            socket.username = socket.username || "Anonymous";
            socket.join(roomID);
            // Prevent duplicate usernames
            if (!rooms[roomID].includes(socket.username)) {
                rooms[roomID].push(socket.username);
            }
            console.log(`[Join] ${socket.username} joined room: ${roomID}`);
            io.to(roomID).emit("user list", rooms[roomID]); // 해당 방 사용자 목록 전송
        } else {
            socket.emit("error", `Room ${roomID} does not exist`);
        }
    });
    
    // 방 나가기
    socket.on('leave room', (roomID) => {
        socket.leave(roomID);
        if (rooms[roomID]) {
            rooms[roomID] = rooms[roomID].filter((user) => user !== socket.username);
            io.to(roomID).emit("user list", rooms[roomID]);
        }
        console.log(`[Leave] ${socket.username} left room: ${roomID}`);
    });
    
    // 방에 메시지 전송
    socket.on("chat message", (data) => {
      // Accept both message and msg keys from client
      const roomID = data.roomID;
      const message = data.msg;

      if (!roomID || !message) {
        console.error("[Chat] Invalid data received:", data);
        return;
      }

      io.to(roomID).emit("chat message", {
        user: socket.username || "Anonymous",
        message,
      });
      console.log(`[Chat][${roomID}] ${socket.username || "Anonymous"}: ${message}`);
    });
    
    socket.on('disconnect', () => {
        console.log(`[Disconnect] User disconnected: ${socket.id} (${socket.username || "Anonymous"})`);
        for (const roomID in rooms) {
            if (rooms[roomID].includes(socket.username)) {
                rooms[roomID] = rooms[roomID].filter((user) => user !== socket.username);
                io.to(roomID).emit("user list", rooms[roomID]); // 참여 유저 목록 갱신
            }
        }
    });
});

server.listen(3000, ()=> {
    console.log('server running at http://localhost:3000');
});
