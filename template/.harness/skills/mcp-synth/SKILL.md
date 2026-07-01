---
name: mcp-synth
description: Use ONLY when a phase needs a tool that is not yet wired up — most often a headless browser to capture a screenshot for visual/perceptual verification of a UI. Synthesizes the MCP server on demand (in an isolated container), registers it in opencode.json, validates it, and notes credential placeholders. Not for MCPs already present in the manifest.
---

# mcp-synth — fabricate the tool you need, when you need it

The Harness does not ship every MCP up front; it **synthesizes them on demand**.
When a phase reaches a capability it lacks — classically, the front-end arrives
and a `[human]` task needs a screenshot — bring up the needed MCP, register it,
and validate it. This is what lets the Harness grow its toolset alongside the
project instead of demanding you anticipate every tool at the start.

## Procedure

1. **Confirm the need is real and unmet.** Check `.harness/mcp/manifest.json`
   and the project's `opencode.json` `mcp` block. If the server already exists,
   stop — do not duplicate.

2. **Pick the server.** For visual verification, use a headless-browser MCP
   (see `references/browser.md`). Prefer a container so it stays isolated from
   the host.

3. **Register it in `opencode.json`** under `mcp`:
   ```json
   {
     "mcp": {
       "playwright": {
         "type": "local",
         "command": ["npx", "-y", "@playwright/mcp"],
         "enabled": true
       }
     }
   }
   ```
   - Local servers (`npx`/`docker`) take `command` as a string array.
   - Remote servers take a `url`; OAuth servers need no manual token.
   - **Never invent secrets.** For any required credential, write a placeholder
     such as `{env:SOME_TOKEN}`, add the variable to `.env.example` with a
     comment, and record the pending item for the human.

4. **Validate.** After registering, the human must restart opencode (MCP servers
   connect at startup). Then confirm the server appears with `opencode mcp list`
   and exercise one tool call.

5. **Use it for the artefact.** Capture the screenshot/text, save it under
   `.harness/` and reference its path in the async judgment note (`review` records
   it; the `desk` bulletin surfaces it). Perceptual verification never blocks.

## Quarantine mode (when invoked by `distill`)

When `distill` generates a NEW tool, do **not** register it in `opencode.json`.
Instead write `.harness/mcp/{name}/mcp.json` with `"enabled": false` and
`"status": "quarantine"`. Because opencode only loads servers listed in
`opencode.json`, this makes the tool inert — `build` physically cannot call it.
Promotion is a human action: flip `status` to `approved`, register it in
`opencode.json`, and restart opencode. An agent never grants itself network access.

See `references/browser.md` for the headless-browser specifics.
