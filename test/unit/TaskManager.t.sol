// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";
import {ITaskManager} from "../../src/interfaces/ITaskManager.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAdoptionStrategy is IAdoptionStrategy {
    function evaluateSubmission(
        uint256 submissionId,
        uint256 approveCount,
        uint256 rejectCount,
        uint256 totalReviews,
        uint256 timeSinceSubmission
    ) external pure override returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) {
        submissionId;
        timeSinceSubmission;
        // Simple mock logic: adopt if more approvals than rejections
        if (totalReviews > 0 && approveCount > rejectCount) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Majority approved");
        }
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Not ready");
    }

    function shouldCompleteTask(
        uint256 taskId,
        uint256 adoptedSubmissionId
    ) external pure override returns (bool shouldComplete) {
        taskId;
        return adoptedSubmissionId > 0; // Complete if any submission adopted
    }

    function getStrategyConfig() external pure override returns (bytes memory config) {
        return "";
    }

    function updateStrategyConfig(bytes calldata newConfig) external override {
        // Mock implementation - do nothing
    }

    function getStrategyMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return ("MockAdoptionStrategy", "1.0.0", "Simple mock adoption strategy for testing");
    }
}

contract MockGuard {
    function getGuardMetadata()
        external
        pure
        returns (string memory name, string memory version, string memory description)
    {
        return ("MockGuard", "1.0.0", "Mock guard used for testing");
    }
}

contract BrokenGuard {
    // Intentionally missing getGuardMetadata implementation
}

contract TaskManagerTest is Test {
    TaskManager internal taskManager;
    Treasury internal treasury;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    MockToken internal stakeToken;
    MockAdoptionStrategy internal mockAdoptionStrategy;
    MockGuard internal mockGuard;
    BrokenGuard internal brokenGuard;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant ADMIN = address(0x10);

    uint256 internal constant DEFAULT_TASK_REWARD = 1 ether;
    uint256 internal constant DEFAULT_DEADLINE_OFFSET = 7 days;

    function setUp() public {
        // Fund test accounts
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(ADMIN, 100 ether);

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy mock stake token
        stakeToken = new MockToken();

        // Deploy mock adoption strategy
        mockAdoptionStrategy = new MockAdoptionStrategy();
        mockGuard = new MockGuard();
        brokenGuard = new BrokenGuard();

        // Deploy HermisSBT
        hermisSBT = new HermisSBT(
            ADMIN,
            "Hermis SBT",
            "HSBT",
            "https://hermis.ai/metadata/",
            "https://hermis.ai/contract-metadata"
        );

        // Deploy ReputationManager
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Deploy AllowlistManager as upgradeable proxy
        AllowlistManager allowlistManagerImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, ADMIN);
        ERC1967Proxy allowlistManagerProxy = new ERC1967Proxy(address(allowlistManagerImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistManagerProxy));

        // Allow mock contracts
        vm.startPrank(ADMIN);
        allowlistManager.allowGuard(address(mockGuard));
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        // Deploy TaskManager as upgradeable proxy
        TaskManager taskManagerImpl = new TaskManager();
        bytes memory initData = abi.encodeWithSelector(
            TaskManager.initialize.selector,
            ADMIN,
            address(treasury),
            address(reputationManager),
            address(allowlistManager)
        );
        ERC1967Proxy taskManagerProxy = new ERC1967Proxy(address(taskManagerImpl), initData);
        taskManager = TaskManager(address(taskManagerProxy));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true);

        // Authorize ReputationManager to interact with TaskManager
        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(reputationManager), true);

        // Authorize TaskManager to interact with ReputationManager
        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(taskManager), true);

        // Initialize users
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        // Give users some tokens
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
    }

    function testCreateTask_Success() public {
        string memory title = "Test Development Task";
        string memory description = "A comprehensive test task";
        string memory requirements = "Must implement X, Y, Z";
        string memory category = "development";
        uint256 deadline = block.timestamp + DEFAULT_DEADLINE_OFFSET;
        uint256 reward = DEFAULT_TASK_REWARD;

        vm.prank(ALICE);
        uint256 taskId = taskManager.createTask(
            title,
            description,
            requirements,
            category,
            deadline,
            reward,
            address(0), // ETH reward
            address(0), // No submission guard
            address(0), // No review guard
            address(mockAdoptionStrategy) // Use mock adoption strategy
        );

        // Verify task was created correctly
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);

        assertEq(task.id, taskId);
        assertEq(task.publisher, ALICE);
        assertEq(task.title, title);
        assertEq(task.description, description);
        assertEq(task.requirements, requirements);
        assertEq(task.category, category);
        assertEq(task.deadline, deadline);
        assertEq(task.reward, reward);
        assertEq(task.rewardToken, address(0));
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.DRAFT));
        assertEq(task.adoptedSubmissionId, 0);
    }

    function testCreateTask_RevertWhenInvalidDeadline() public {
        vm.prank(ALICE);
        vm.expectRevert();
        taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp - 1, // Past deadline
            1 ether,
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateTask_RevertWhenZeroReward() public {
        vm.prank(ALICE);
        vm.expectRevert();
        taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + DEFAULT_DEADLINE_OFFSET,
            0, // Zero reward
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateTask_RevertWhenInvalidGuard() public {
        vm.prank(ALICE);
        vm.expectRevert(ITaskManager.InvalidConfiguration.selector);
        taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + DEFAULT_DEADLINE_OFFSET,
            DEFAULT_TASK_REWARD,
            address(0),
            address(brokenGuard),
            address(0),
            address(mockAdoptionStrategy)
        );
    }

    function testPublishTask_Success() public {
        uint256 taskId = _createBasicTask(ALICE);

        // Provide ETH for the task reward since it's an ETH-based task
        vm.deal(ALICE, DEFAULT_TASK_REWARD * 2);
        vm.prank(ALICE);
        taskManager.publishTask{value: DEFAULT_TASK_REWARD}(taskId);

        // Verify task status changed
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.PUBLISHED));
    }

    function testPublishTask_RevertWhenInsufficientEthFunding() public {
        uint256 taskId = _createBasicTask(ALICE);

        // Attempt to publish with less than required reward value
        vm.deal(ALICE, DEFAULT_TASK_REWARD);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITreasury.InsufficientBalance.selector,
                address(0),
                DEFAULT_TASK_REWARD,
                DEFAULT_TASK_REWARD - 1
            )
        );
        taskManager.publishTask{value: DEFAULT_TASK_REWARD - 1}(taskId);
    }

    function testPublishTask_Erc20RewardPath() public {
        // Create ERC20-denominated task
        uint256 taskId = _createTaskWithToken(ALICE, address(stakeToken));

        // Fund and approve ALICE tokens
        stakeToken.mint(ALICE, DEFAULT_TASK_REWARD);
        vm.prank(ALICE);
        stakeToken.approve(address(taskManager), DEFAULT_TASK_REWARD);

        vm.prank(ALICE);
        taskManager.publishTask(taskId);

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.PUBLISHED));

        // Verify treasury recorded the reward balance
        uint256 treasuryBalance = treasury.getBalance(address(stakeToken), "task", taskId);
        assertEq(treasuryBalance, DEFAULT_TASK_REWARD);
    }

    function testPublishTask_RevertWhenAlreadyPublished() public {
        uint256 taskId = _createBasicTask(ALICE);
        _publishTask(taskId, ALICE);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ITaskManager.TaskNotActive.selector, taskId));
        taskManager.publishTask(taskId);
    }

    function testUpdateTaskGuards_AllowsValidContracts() public {
        uint256 taskId = _createBasicTask(ALICE);

        vm.prank(ALICE);
        taskManager.updateTaskGuards(taskId, address(mockGuard), address(mockGuard), address(mockAdoptionStrategy));

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(task.submissionGuard, address(mockGuard));
        assertEq(task.reviewGuard, address(mockGuard));
    }

    function testInitialize_RevertWhenCalledTwice() public {
        // Create a new TaskManager implementation
        TaskManager taskManagerImpl = new TaskManager();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            TaskManager.initialize.selector,
            ADMIN,
            address(treasury),
            address(reputationManager),
            address(allowlistManager)
        );
        ERC1967Proxy taskManagerProxy = new ERC1967Proxy(address(taskManagerImpl), initData);
        TaskManager newManager = TaskManager(address(taskManagerProxy));

        // Attempt to initialize again should revert
        vm.expectRevert();
        newManager.initialize(ADMIN, address(treasury), address(reputationManager), address(allowlistManager));
    }

    function testPublishTask_RevertWhenNotOwner() public {
        uint256 taskId = _createBasicTask(ALICE);

        vm.prank(BOB);
        vm.expectRevert();
        taskManager.publishTask(taskId);
    }

    // Note: Skipping insufficient payment test due to contract payable bug
    // function testPublishTask_RevertWhenInsufficientPayment() public {
    //     // Test would fail because publishTask isn't marked payable
    // }

    function testActivateTask_Success() public {
        uint256 taskId = _createBasicTask(ALICE);
        _publishTask(taskId, ALICE);

        vm.prank(address(reputationManager)); // Simulate authorized call
        taskManager.activateTask(taskId);

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.ACTIVE));
    }

    function testCompleteTask_Success() public {
        uint256 taskId = _createBasicTask(ALICE);
        _publishTask(taskId, ALICE);

        uint256 submissionId = 123;

        vm.prank(address(reputationManager)); // Simulate authorized call
        taskManager.completeTask(taskId, submissionId);

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.COMPLETED));
        assertEq(task.adoptedSubmissionId, submissionId);
    }

    function testCancelTask_Success() public {
        uint256 taskId = _createBasicTask(ALICE);
        _publishTask(taskId, ALICE);

        uint256 aliceBalanceBefore = ALICE.balance;

        vm.prank(ALICE);
        taskManager.cancelTask(taskId, "Changed requirements");

        // Verify task was cancelled
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.CANCELLED));

        // Verify refund was issued
        assertGt(ALICE.balance, aliceBalanceBefore);
    }

    function testCanAcceptSubmissions() public {
        uint256 taskId = _createBasicTask(ALICE);

        // Draft task cannot accept submissions
        (bool canAccept, string memory reason) = taskManager.canAcceptSubmissions(taskId);
        assertFalse(canAccept);
        assertTrue(bytes(reason).length > 0);

        // Published task can accept submissions
        _publishTask(taskId, ALICE);
        (canAccept, reason) = taskManager.canAcceptSubmissions(taskId);
        assertTrue(canAccept);

        // Expired task cannot accept submissions
        vm.warp(block.timestamp + DEFAULT_DEADLINE_OFFSET + 1);
        (canAccept, reason) = taskManager.canAcceptSubmissions(taskId);
        assertFalse(canAccept);
    }

    // Helper functions
    function _createBasicTask(address publisher) internal returns (uint256 taskId) {
        vm.prank(publisher);
        return
            taskManager.createTask(
                "Test Task",
                "A test task description",
                "Basic requirements",
                "development",
                block.timestamp + DEFAULT_DEADLINE_OFFSET,
                DEFAULT_TASK_REWARD,
                address(0), // ETH reward
                address(0), // No submission guard
                address(0), // No review guard
                address(mockAdoptionStrategy) // Use mock adoption strategy
            );
    }

    function _createTaskWithToken(address publisher, address rewardToken) internal returns (uint256 taskId) {
        vm.prank(publisher);
        return
            taskManager.createTask(
                "Token Task",
                "ERC20 reward",
                "Deliver ERC20 work",
                "development",
                block.timestamp + DEFAULT_DEADLINE_OFFSET,
                DEFAULT_TASK_REWARD,
                rewardToken,
                address(0),
                address(0),
                address(mockAdoptionStrategy)
            );
    }

    function _publishTask(uint256 taskId, address publisher) internal {
        // Fund publisher with ETH for task reward
        vm.deal(publisher, DEFAULT_TASK_REWARD * 2);
        vm.prank(publisher);
        taskManager.publishTask{value: DEFAULT_TASK_REWARD}(taskId);
    }
}
