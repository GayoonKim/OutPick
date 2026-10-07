import {initializeApp} from "https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js";
import {getAuth, GoogleAuthProvider, inMemoryPersistence, onIdTokenChanged,
  setPersistence, signInWithPopup, signOut} from
  "https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js";

const app = initializeApp(window.Q7_FIREBASE_CONFIG);
const auth = getAuth(app);
await setPersistence(auth, inMemoryPersistence);
const status = document.querySelector("#status");
const loginButton = document.querySelector("#login");
const logoutButton = document.querySelector("#logout");
loginButton.addEventListener("click", async () => {
  status.textContent = "Google 로그인 중…";
  try { await signInWithPopup(auth, new GoogleAuthProvider()); } catch (error) {
    const code = /^auth\/[a-z-]+$/.test(error?.code ?? "") ? error.code : "auth/unknown";
    status.textContent = "로그인 실패 · " + code + ". 같은 브라우저의 popup 상태를 확인하세요.";
  }
});
logoutButton.addEventListener("click", async () => {
  await signOut(auth);
  await fetch("/q7/logout", {method: "POST"});
});
onIdTokenChanged(auth, async (user) => {
  loginButton.hidden = Boolean(user);
  logoutButton.hidden = !user;
  if (!user) { status.textContent = "로그인 전"; return; }
  try {
    const response = await fetch("/q7/auth", {
      method: "POST", headers: {"content-type": "application/json"},
      body: JSON.stringify({nonce: window.Q7_NONCE, idToken: await user.getIdToken()}),
      cache: "no-store",
    });
    if (!response.ok) throw new Error("auth rejected");
    const result = await response.json();
    status.textContent = "연결됨 · UID " + result.uid;
  } catch { status.textContent = "Development 인증을 확인하지 못했습니다."; }
});
