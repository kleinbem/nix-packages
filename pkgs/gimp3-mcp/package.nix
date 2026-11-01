{
  lib,
  python3Packages,
  fetchPypi,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "gimp3-mcp";
  version = "0.2.0";
  pyproject = true;

  src = fetchPypi {
    pname = "gimp3_mcp";
    inherit (finalAttrs) version;
    hash = "sha256-OVFKg9q7KZQcToiRpagphQ3ucXB/ymuRsPzsEwSBiHk=";
  };

  # mcp 2: FastMCP is MCPServer, and only a ToolError's message reaches the
  # client. Upstream still pins mcp<2; with mcp 1 (a held nixpkgs) the
  # package builds unpatched.
  # no-link: not reported upstream yet; drop with a gimp3-mcp release that
  # supports mcp 2.
  patches = lib.optional (lib.versionAtLeast python3Packages.mcp.version "2") ./mcp-2.patch;

  build-system = [ python3Packages.hatchling ];

  dependencies = [ python3Packages.mcp ];

  pythonImportsCheck = [ "gimp3_mcp" ];

  meta = {
    description = "MCP server for GIMP 3 (the GIMP plugin ships in the sdist)";
    homepage = "https://github.com/tifyr/gimp3-mcp";
    license = lib.licenses.gpl3Only;
    mainProgram = "gimp3-mcp";
  };
})
