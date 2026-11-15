# Talks MCP over stdio to the server without GIMP: proves mcp loads, all tools
# register, and a tool that needs GIMP reports why it failed.
{
  runCommand,
  python3,
  gimp3-mcp,
}:
runCommand "gimp3-mcp-smoke" { nativeBuildInputs = [ python3 ]; } ''
  export HOME=$TMPDIR
  python3 - ${gimp3-mcp}/bin/gimp3-mcp <<'EOF'
  import json, subprocess, sys

  p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

  def call(i, method, params=None):
      p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params or {}}) + "\n")
      p.stdin.flush()
      while True:
          m = json.loads(p.stdout.readline())
          if m.get("id") == i:
              return m["result"]

  call(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}})
  p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
  tools = call(2, "tools/list")["tools"]
  assert len(tools) >= 80, f"only {len(tools)} tools"
  assert not any("ctx" in json.dumps(t["inputSchema"]) for t in tools), "ctx leaked into a schema"
  err = call(3, "tools/call", {"name": "get_image_metadata", "arguments": {}})["content"][0]["text"]
  assert "Could not connect to GIMP" in err, err
  p.terminate()
  print(f"{len(tools)} tools; error: {err}")
  EOF
  touch $out
''
