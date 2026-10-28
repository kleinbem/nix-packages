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

  # Needs mcp 1.x: mcp 2 removed mcp.server.fastmcp, which the server imports.
  dependencies = [ python3Packages.mcp ];

  pythonImportsCheck = [ "gimp3_mcp" ];

  meta = {
    description = "MCP server for GIMP 3 (the GIMP plugin ships in the sdist)";
    homepage = "https://github.com/tifyr/gimp3-mcp";
    license = lib.licenses.gpl3Only;
    mainProgram = "gimp3-mcp";
  };
})
