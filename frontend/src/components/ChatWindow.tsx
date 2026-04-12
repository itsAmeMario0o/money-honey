import { useState } from "react";
import { sendChatMessage } from "../api";
import type { Message } from "../types";
import MessageBubble from "./MessageBubble";

export default function ChatWindow() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSend() {
    const text = input.trim();
    if (!text || isSending) {
      return;
    }
    setError(null);
    setIsSending(true);
    setMessages((prev) => [...prev, { role: "user", text }]);
    setInput("");

    try {
      const response = await sendChatMessage(text);
      setMessages((prev) => [...prev, { role: "assistant", text: response.reply }]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setIsSending(false);
    }
  }

  return (
    <div className="chat-window">
      <div className="chat-history">
        {messages.map((message, index) => (
          <MessageBubble key={index} message={message} />
        ))}
      </div>
      {error && <div className="chat-error">{error}</div>}
      <div className="chat-input-row">
        <input
          className="chat-input"
          value={input}
          onChange={(event) => setInput(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              handleSend();
            }
          }}
          placeholder="Ask Money Honey anything about your finances..."
          disabled={isSending}
        />
        <button className="chat-send" onClick={handleSend} disabled={isSending}>
          {isSending ? "..." : "Send"}
        </button>
      </div>
    </div>
  );
}
