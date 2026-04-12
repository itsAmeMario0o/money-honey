import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ChatWindow from "../ChatWindow";

// Mock the API module so tests don't hit the network.
vi.mock("../../api", () => ({
  sendChatMessage: vi.fn().mockResolvedValue({
    reply: "Hey babe, save more.",
    sources_used: 4,
  }),
}));

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
});
