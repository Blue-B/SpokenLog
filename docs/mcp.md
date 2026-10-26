# AI connection (MCP)

SpokenLog for Windows and macOS can let AI tools search and read your recordings' transcripts through the [Model Context Protocol](https://modelcontextprotocol.io). Ask things like "When did we decide the launch date, and who said it?" in Claude Code, Codex, pi, Claude or ChatGPT, and the AI looks it up in your library.

- **Read-only.** The AI can list recordings, search transcripts and read them. It cannot rename, edit, delete or transcribe anything, and it never receives audio files.
- **Local first.** The server runs inside the SpokenLog app and listens only on `127.0.0.1`. Nothing is uploaded unless you connect a cloud AI or open a tunnel yourself.
- **What leaves your computer.** Transcript text that the AI reads is sent to that AI's provider (for example Anthropic or OpenAI). If your AI tool runs a local model (for example pi, Codex or Claude Code pointed at Ollama or LM Studio), it stays on your computer.

## Turn it on

1. Open SpokenLog > **Settings** > **AI connection (MCP)**.
2. Turn on **Let AI tools read recordings**.
3. Copy the setup line for your AI tool (below). The address looks like `http://127.0.0.1:47821/mcp/<secret>`.

The server runs while SpokenLog is open and starts again automatically the next time you open it. The secret in the address works like a password: anyone who has the full address and can reach it can read your transcripts. Use **New address** in the same screen to revoke every existing connection.

## Tools the AI gets

| Tool | What it does |
| --- | --- |
| `list_recordings` | Lists recordings newest first, filtered by title, date range, folder or favorites. |
| `search_transcripts` | Finds segments containing all the given words, with recording, time (`00:10:40`) and speaker. |
| `get_transcript` | Reads one transcript, optionally only a time range or one speaker. |

Search matches words literally (case-insensitive); it does not understand synonyms. Recordings in the trash are never returned.

## Connect a tool on the same computer

Replace `<address>` with the address copied from SpokenLog.

**Claude Code**

```sh
claude mcp add -s user --transport http spokenlog <address>
```

**Codex**

```sh
codex mcp add spokenlog --url <address>
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.spokenlog]
url = "<address>"
```

**pi** (MCP adapter, `~/.pi/agent/mcp.json`)

```json
{
  "mcpServers": {
    "spokenlog": { "url": "<address>" }
  }
}
```

**Claude Desktop** (local config; needs [Node.js](https://nodejs.org)) in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "spokenlog": { "command": "npx", "args": ["-y", "mcp-remote", "<address>"] }
  }
}
```

Other tools that support Streamable HTTP MCP servers (Cursor, VS Code, LM Studio and others) can use the address directly.

## Connect ChatGPT or Claude on the web

Web and mobile AI apps connect from their providers' servers, not from your computer, so they cannot reach `127.0.0.1`. You need a tunnel. Only do this if you accept that the provider's servers will read your transcripts.

**ChatGPT (recommended: OpenAI Secure MCP Tunnel, no public address)**

1. Follow OpenAI's [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels) and run `tunnel-client` with `--mcp-server-url <address>`.
2. In ChatGPT on the web, open **Plugins** > **+** > **Add custom MCP server**, choose **Tunnel**, select your tunnel and choose **No authentication** (the secret is already in the address).

Adding custom MCP servers depends on your ChatGPT plan and workspace settings.

**Claude (claude.ai, Claude Desktop custom connectors) or ChatGPT with a public tunnel**

1. Start a tunnel to the SpokenLog port, for example with [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/):

   ```sh
   cloudflared tunnel --url http://127.0.0.1:47821
   ```

2. It prints an address like `https://example-words.trycloudflare.com`. Your connector URL is that address plus the path from SpokenLog: `https://example-words.trycloudflare.com/mcp/<secret>`.
3. Claude: **Customize** > **Connectors** > **Add custom connector**, paste the URL and choose **No sign in**. ChatGPT: **Add custom MCP server** > **Server URL**, with **No authentication**.

While the tunnel runs, anyone with the full URL can read your transcripts. Stop the tunnel when you are done and use **New address** in SpokenLog if the URL may have been shared.

## Try it

- "In SpokenLog, find where we talked about the ad budget and tell me the amount and who said it."
- "List my SpokenLog recordings from last week in the 회의 folder."
- "Summarize what 민수 said in the October 20 meeting."

## Troubleshooting

- **Connection refused:** SpokenLog must be open and the switch on.
- **Port 47821 is used by another program:** close the other program and turn the switch off and on.
- **404:** the secret in the address is wrong or was replaced by **New address**. Copy the address again.
- **The AI says there is nothing:** only transcribed recordings can be searched. Transcribe the recording first.
- **Phones:** Android and iPhone do not run the server, because phones suspend background apps. Import or sync the recordings to a computer running SpokenLog.
