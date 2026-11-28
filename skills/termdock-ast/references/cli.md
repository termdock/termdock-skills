# Code Graph MCP CLI

Use Termdock 1.29 or later. Set the MCP client command to `termdock` and pass these arguments:

```text
mcp code-graph --path /absolute/path/to/project
```

If the client cannot find the CLI on its PATH, use the absolute path to the bundled CLI. On macOS this is usually `/Applications/Termdock.app/Contents/Resources/cli/termdock`. On Windows use `resources/cli/termdock.exe` from the installed app. On Linux use `resources/cli/termdock` from an extracted AppImage.

The CLI starts a local stdio server without opening the Termdock UI or calling the Terminal API. Stdout carries only JSON-RPC. Read startup errors on stderr. The server can list tools without an index; to call tools, open the project in Termdock first to build its index. The server does not update the saved index.
