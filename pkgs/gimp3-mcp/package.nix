{
  lib,
  python3Packages,
  fetchPypi,
  fetchpatch,
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

  # Workaround: runs on mcp 1 and 2 (nixpkgs has 2: FastMCP is MCPServer, and
  # only a ToolError's message reaches the client). Drop with tifyr/gimp3-mcp#2.
  patches = [
    (fetchpatch {
      url = "https://github.com/tifyr/gimp3-mcp/commit/c3e98c6ab2a02f3d27430dfe31c7eab9f5fb5096.patch";
      includes = [
        "gimp_mcp_server.py"
        "pyproject.toml"
      ];
      hash = "sha256-nS6uMSnjJKaxswgld5abpSU9NHmY54ZItRDI6tsmf3c=";
    })
  ];

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
