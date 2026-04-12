// Shared types for the chat UI.

export type Role = "user" | "assistant";

export interface Message {
  role: Role;
  text: string;
}

export interface ChatApiResponse {
  reply: string;
  sources_used: number;
}
