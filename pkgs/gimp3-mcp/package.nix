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

  build-system = [ python3Packages.hatchling ];

  # Upstream pins mcp < 2 (FastMCP is MCPServer in 2), so use nixpkgs' mcp 1
  # like the other mcp 1 dependents.
  dependencies = [ python3Packages.mcp_1 ];

  pythonImportsCheck = [ "gimp3_mcp" ];

  meta = {
    description = "MCP server for GIMP 3 (the GIMP plugin ships in the sdist)";
    homepage = "https://github.com/tifyr/gimp3-mcp";
    license = lib.licenses.gpl3Only;
    mainProgram = "gimp3-mcp";
  };
})
