{
  lib,
  python3Packages,
  fetchFromGitHub,
  runCommand,
  nix-update-script,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "agent-task-queue";
  version = "0.4.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "block";
    repo = "agent-task-queue";
    tag = "v${finalAttrs.version}";
    hash = "sha256-BLSUENh7ft/+2m8Ivm+MhM0xEVl6tvnFrs8y2vVF6jY=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [ python3Packages.fastmcp ];

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-asyncio
  ];

  # The tests start the server and the CLI as subprocesses; their queue
  # database lives in the default data directory, /tmp/agent-task-queue, which
  # the sandbox provides (a test checks that default, so don't override it).

  # These three drive the tq CLI with SIGINT and read its queue database in
  # between; they depend on process timing and fail in the sandbox
  # ("Blocker should be running", "no such table: queue"). The other 79 tests
  # cover the queue and the CLI.
  disabledTests = [
    "test_sigint_cleanup_waiting_task"
    "test_cancel_and_restart_proceeds"
    "test_rapid_cancel_restart_cycles"
  ];

  pythonImportsCheck = [
    "task_queue"
    "tq"
  ];

  passthru = {
    tests.cli = runCommand "agent-task-queue-cli-test" { } ''
      ${finalAttrs.finalPackage}/bin/tq --help | grep -qi queue
      ${finalAttrs.finalPackage}/bin/agent-task-queue --help | grep -qi queue
      touch $out
    '';
    updateScript = nix-update-script { };
  };

  meta = {
    description = "MCP server and CLI that queue AI agents' expensive commands so they run one at a time";
    homepage = "https://github.com/block/agent-task-queue";
    changelog = "https://github.com/block/agent-task-queue/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "agent-task-queue";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
