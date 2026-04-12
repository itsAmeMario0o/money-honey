import type { Message } from "../types";

interface MessageBubbleProps {
  message: Message;
}

export default function MessageBubble({ message }: MessageBubbleProps) {
  const bubbleClass = message.role === "user" ? "bubble user" : "bubble assistant";
  return (
    <div className={bubbleClass}>
      <div className="bubble-role">{message.role === "user" ? "You" : "Money Honey"}</div>
      <div className="bubble-text">{message.text}</div>
    </div>
  );
}
