// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/core/TaskManager.sol";

contract TestInvalidTitle is Test {
    TaskManager taskManager;

    function setUp() public {
        taskManager = new TaskManager();
    }

    function testInvalidTaskTitle() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidTaskTitle(string)", ""));

        // This should revert with InvalidTaskTitle
        taskManager.createTask(
            "", // empty title should trigger InvalidTaskTitle
            "Test description",
            "Test requirements",
            "test",
            block.timestamp + 1 days,
            1 ether,
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }
}
