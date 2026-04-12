// Thin fetch wrapper for the Money Honey backend.

import type { ChatApiResponse } from "./types";

export async function sendChatMessage(message: string): Promise<ChatApiResponse> {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });

  if (!response.ok) {
    throw new Error(`Chat API returned ${response.status}`);
  }
  return response.json();
}
