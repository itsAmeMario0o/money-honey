import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ChatWindow from "../ChatWindow";
import { sendChatMessage } from "../../api";

vi.mock("../../api", () => ({
  sendChatMessage: vi.fn().mockResolvedValue({
    reply: "Hey babe, save more.",
    sources_used: 4,
  }),
}));

const mockSend = vi.mocked(sendChatMessage);

describe("ChatWindow", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the chat input and send button", () => {
    render(<ChatWindow />);
    expect(screen.getByPlaceholderText(/Ask Money Honey/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /send/i })).toBeInTheDocument();
  });

  it("shows the user message and the reply after sending", async () => {
    render(<ChatWindow />);
    const user = userEvent.setup();
    const input = screen.getByPlaceholderText(/Ask Money Honey/i);

    await user.type(input, "How much should I save?");
    await user.click(screen.getByRole("button", { name: /send/i }));

    expect(await screen.findByText("How much should I save?")).toBeInTheDocument();
    expect(await screen.findByText(/save more/i)).toBeInTheDocument();
  });

  it("sends empty history on the first message", async () => {
    render(<ChatWindow />);
    const user = userEvent.setup();

    await user.type(screen.getByPlaceholderText(/Ask Money Honey/i), "hi");
    await user.click(screen.getByRole("button", { name: /send/i }));

    await screen.findByText(/save more/i);
    expect(mockSend).toHaveBeenCalledWith("hi", []);
  });

  it("sends prior turns as history on the second message", async () => {
    render(<ChatWindow />);
    const user = userEvent.setup();
    const input = screen.getByPlaceholderText(/Ask Money Honey/i);

    await user.type(input, "first question");
    await user.click(screen.getByRole("button", { name: /send/i }));
    await screen.findByText(/save more/i);

    await user.type(input, "follow up");
    await user.click(screen.getByRole("button", { name: /send/i }));

    expect(mockSend).toHaveBeenLastCalledWith("follow up", [
      { role: "user", content: "first question" },
      { role: "assistant", content: "Hey babe, save more." },
    ]);
  });
});
