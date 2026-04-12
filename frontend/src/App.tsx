import ChatWindow from "./components/ChatWindow";

export default function App() {
  return (
    <div className="app">
      <header className="app-header">
        <h1>🍯 Money Honey</h1>
        <p>Your finances, but make them fabulous.</p>
      </header>
      <main>
        <ChatWindow />
      </main>
    </div>
  );
}
