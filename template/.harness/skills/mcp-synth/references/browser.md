# Headless browser MCP (for visual verification)

The most common on-demand tool in the Harness is a headless browser used to
capture a screenshot that backs a `[human]` verification task.

## Playwright MCP (recommended default)

Local, no credentials, runs Chromium headless via `npx`.

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp", "--headless"],
      "enabled": true
    }
  }
}
```

Typical capabilities: navigate to a URL, take a full-page or element
screenshot, read the accessibility tree, click and type. For the Harness you
mostly need: navigate → screenshot → save to `dashboard/shot-<id>.png`.

## Container isolation (when the host should stay clean)

Run the browser in a container so it never touches the host environment:

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["docker", "run", "--rm", "-i", "mcr.microsoft.com/playwright/mcp"],
      "enabled": true
    }
  }
}
```

## Flow for a perceptual check

1. Build serves the app locally (or the dev environment is already up via
   `.harness/dev.sh`).
2. Navigate to the relevant route, screenshot it, save it under `.harness/`.
3. In `review`, record an async judgment note in `decisions.md` referencing the
   artefact path (never a blocking request — perceptual checks do not block).
4. The `desk` bulletin surfaces it to the human, whose verdict (or silence =
   approval) feeds back as a normal intake item.

## Notes

- MCP servers connect at opencode **startup**; after registering one, the human
  must restart opencode before it is usable.
- Keep the server `enabled: false` or omit it until the front-end actually
  exists — synthesize on demand, not preemptively.
