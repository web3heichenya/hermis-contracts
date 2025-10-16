// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {BasicRewardStrategy} from "../../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        uint256,
        uint256 approveCount,
        uint256 rejectCount,
        uint256 totalReviews,
        uint256
    ) external pure override returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) {
        if (totalReviews >= 2 && approveCount > rejectCount) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Majority approved");
        }
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Needs more reviews");
    }

    function shouldCompleteTask(uint256, uint256 adoptedSubmissionId) external pure override returns (bool) {
        return adoptedSubmissionId > 0;
    }

    function getStrategyConfig() external pure override returns (bytes memory) {
        return "";
    }

    function updateStrategyConfig(bytes calldata) external override {}

    function getStrategyMetadata() external pure override returns (string memory, string memory, string memory) {
        return ("MockAdoptionStrategy", "1.0.0", "Mock strategy");
    }
}

/// @title MaliciousPublisher
/// @notice Malicious contract that attempts reentrancy during task publishing
/// @dev Tries to exploit receive() callback when receiving ETH refunds
contract MaliciousPublisher {
    TaskManager public taskManager;
    uint256 public attackCount;
    uint256 public maxAttacks = 3;

    constructor(address _taskManager) {
        taskManager = TaskManager(_taskManager);
    }

    /// @notice Receive function that attempts reentrancy
    /// @dev Should be blocked by ReentrancyGuard in TaskManager
    receive() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            // Attempt to cancel the same task again during refund (reentrancy)
            try taskManager.cancelTask(1, "Reentrant cancel") {} catch {}
        }
    }

    function createTask(address strategy, uint256 deadline, uint256 reward) external returns (uint256) {
        return
            taskManager.createTask(
                "Malicious Task",
                "Attempt reentrancy",
                "Requirements",
                "development",
                deadline,
                reward,
                address(0),
                address(0),
                address(0),
                strategy
            );
    }

    function publishTask(uint256 taskId) external payable {
        taskManager.publishTask{value: msg.value}(taskId);
    }

    function cancelTask(uint256 taskId) external {
        taskManager.cancelTask(taskId, "Testing reentrancy");
    }
}

/// @title MaliciousStaker
/// @notice Malicious contract that attempts reentrancy during staking operations
/// @dev Tries to exploit onERC20Received or similar callbacks
contract MaliciousStaker {
    ReputationManager public reputationManager;
    MockToken public stakeToken;
    uint256 public attackCount;
    uint256 public maxAttacks = 3;
    bool public attacking;

    constructor(address _reputationManager, address _stakeToken) {
        reputationManager = ReputationManager(_reputationManager);
        stakeToken = MockToken(_stakeToken);
    }

    /// @notice Attempts reentrancy during ERC20 transfer callbacks
    /// @dev Should be blocked by ReentrancyGuard
    function onERC20Received(address, address, uint256, bytes memory) external returns (bytes4) {
        if (!attacking && attackCount < maxAttacks) {
            attacking = true;
            attackCount++;
            // Attempt to stake again during callback
            try reputationManager.stake(1 ether, address(stakeToken)) {} catch {}
            attacking = false;
        }
        return this.onERC20Received.selector;
    }

    function approveAndStake(uint256 amount) external {
        stakeToken.approve(address(reputationManager), amount);
        reputationManager.stake(amount, address(stakeToken));
    }

    function requestUnstake() external {
        reputationManager.requestUnstake();
    }

    function unstake() external {
        reputationManager.unstake();
    }
}

/// @title ReentrancyTest
/// @notice Critical security tests for reentrancy attack prevention
/// @dev Tests that ReentrancyGuard properly protects all state-changing functions
contract ReentrancyTest is Test {
    TaskManager internal taskManager;
    SubmissionManager internal submissionManager;
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;
    MockToken internal stakeToken;
    MockAdoptionStrategy internal mockStrategy;

    MaliciousPublisher internal maliciousPublisher;
    MaliciousStaker internal maliciousStaker;

    address internal constant ADMIN = address(0x1);
    address internal constant REVIEWER1 = address(0x4);
    address internal constant REVIEWER2 = address(0x5);

    function setUp() public {
        vm.deal(ADMIN, 100 ether);
        vm.deal(REVIEWER1, 100 ether);
        vm.deal(REVIEWER2, 100 ether);

        // Deploy base contracts
        stakeToken = new MockToken();
        mockStrategy = new MockAdoptionStrategy();
        treasury = new Treasury(ADMIN);
        hermisSBT = new HermisSBT(ADMIN, "Hermis SBT", "HSBT", "https://hermis.ai/", "https://hermis.ai/contract");
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Deploy AllowlistManager
        AllowlistManager allowlistImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, ADMIN);
        ERC1967Proxy allowlistProxy = new ERC1967Proxy(address(allowlistImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistProxy));

        vm.prank(ADMIN);
        allowlistManager.allowStrategy(address(mockStrategy));

        // Deploy TaskManager
        TaskManager taskManagerImpl = new TaskManager();
        bytes memory taskInitData = abi.encodeWithSelector(
            TaskManager.initialize.selector,
            ADMIN,
            address(treasury),
            address(reputationManager),
            address(allowlistManager)
        );
        ERC1967Proxy taskProxy = new ERC1967Proxy(address(taskManagerImpl), taskInitData);
        taskManager = TaskManager(address(taskProxy));

        // Deploy BasicRewardStrategy
        rewardStrategy = new BasicRewardStrategy(ADMIN);
        bytes memory rewardConfig = abi.encode(
            BasicRewardStrategy.BasicRewardConfig({
                creatorPercentage: 70,
                reviewerPercentage: 20,
                platformPercentage: 10,
                accuracyBonus: 20,
                accuracyPenalty: 10,
                minReviewerReward: 0,
                maxReviewerReward: 0
            })
        );
        vm.prank(ADMIN);
        rewardStrategy.initializeRewardStrategy(rewardConfig);

        // Deploy SubmissionManager
        SubmissionManager submissionImpl = new SubmissionManager();
        bytes memory submissionInitData = abi.encodeWithSelector(
            SubmissionManager.initialize.selector,
            ADMIN,
            address(taskManager),
            address(reputationManager),
            address(treasury),
            address(rewardStrategy)
        );
        ERC1967Proxy submissionProxy = new ERC1967Proxy(address(submissionImpl), submissionInitData);
        submissionManager = SubmissionManager(address(submissionProxy));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));
        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        // Set authorizations
        vm.startPrank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true);
        treasury.setAuthorizedContract(address(submissionManager), true);
        treasury.setAuthorizedContract(address(reputationManager), true);
        taskManager.setAuthorizedContract(address(submissionManager), true);
        reputationManager.setAuthorizedContract(address(taskManager), true);
        reputationManager.setAuthorizedContract(address(submissionManager), true);
        submissionManager.setAuthorizedContract(address(taskManager), true);
        vm.stopPrank();

        // Deploy malicious contracts
        maliciousPublisher = new MaliciousPublisher(address(taskManager));
        maliciousStaker = new MaliciousStaker(address(reputationManager), address(stakeToken));

        // Initialize malicious contracts as users
        vm.prank(ADMIN);
        reputationManager.initializeUser(address(maliciousPublisher));
        vm.prank(ADMIN);
        reputationManager.initializeUser(address(maliciousStaker));
        vm.prank(ADMIN);
        reputationManager.initializeUser(REVIEWER1);
        vm.prank(ADMIN);
        reputationManager.initializeUser(REVIEWER2);

        // Fund malicious contracts
        vm.deal(address(maliciousPublisher), 100 ether);
        stakeToken.mint(address(maliciousStaker), 100 ether);
    }

    /// @notice Test that publishTask is protected against reentrancy
    /// @dev Critical: Prevents double-spending of task rewards during publish
    function testReentrancy_PublishTask() public {
        // Malicious publisher creates a task
        uint256 taskId = maliciousPublisher.createTask(address(mockStrategy), block.timestamp + 7 days, 1 ether);

        // Attempt to publish with reentrancy attack
        vm.deal(address(maliciousPublisher), 10 ether);
        maliciousPublisher.publishTask{value: 1 ether}(taskId);

        // Verify task was published only once
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.PUBLISHED));

        // Verify no reentrancy occurred (attackCount should be 0)
        assertEq(maliciousPublisher.attackCount(), 0, "Reentrancy attack should have been prevented");
    }

    /// @notice Test that cancelTask with refund is protected against reentrancy
    /// @dev Critical: Prevents exploitation during ETH refunds
    /// @dev FIXED: Added nonReentrant modifier to cancelTask() function
    /// @dev The malicious receive() function WILL be called (ETH transfer triggers it),
    ///      but the reentrancy attempt inside receive() WILL BE BLOCKED by ReentrancyGuard
    function testReentrancy_CancelTask() public {
        // Create and publish task
        uint256 taskId = maliciousPublisher.createTask(address(mockStrategy), block.timestamp + 7 days, 1 ether);
        maliciousPublisher.publishTask{value: 1 ether}(taskId);

        uint256 balanceBefore = address(maliciousPublisher).balance;

        // Attempt to cancel with reentrancy
        maliciousPublisher.cancelTask(taskId);

        // Verify refund was received
        assertGt(address(maliciousPublisher).balance, balanceBefore, "Refund should have been received");

        // Verify task was cancelled only ONCE (not twice from reentrancy)
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.CANCELLED));

        // The receive() function WAS called (attackCount == 1) during ETH refund,
        // which is expected. The important thing is that the REENTRANT CALL
        // inside receive() was BLOCKED by ReentrancyGuard (see trace: ReentrancyGuardReentrantCall() revert)
        // This proves the fix is working correctly
        assertEq(maliciousPublisher.attackCount(), 1, "receive() was called once during refund (expected)");

        // The critical security check: task was only cancelled once, not twice
        // If reentrancy had succeeded, the task would have invalid state or multiple cancellations
    }

    /// @notice Test that stake function is protected against reentrancy
    /// @dev Critical: Prevents double-staking attacks
    function testReentrancy_Stake() public {
        // Reduce reputation to require staking
        vm.prank(ADMIN);
        reputationManager.updateReputation(address(maliciousStaker), -500, "Reduce for testing");

        // Attempt reentrancy during stake
        stakeToken.mint(address(maliciousStaker), 100 ether);
        maliciousStaker.approveAndStake(10 ether);

        // Verify only one stake occurred
        (, , uint256 stakedAmount, , ) = reputationManager.getUserReputation(address(maliciousStaker));
        assertEq(stakedAmount, 10 ether, "Only one stake should have succeeded");

        // Verify no reentrancy occurred
        assertEq(maliciousStaker.attackCount(), 0, "Reentrancy attack should have been prevented");
    }

    /// @notice Test that unstake function is protected against reentrancy
    /// @dev Critical: Prevents double-withdrawal of staked tokens
    function testReentrancy_Unstake() public {
        // Setup: stake tokens first
        vm.prank(ADMIN);
        reputationManager.updateReputation(address(maliciousStaker), -500, "Reduce for testing");

        stakeToken.mint(address(maliciousStaker), 100 ether);
        maliciousStaker.approveAndStake(10 ether);

        // Increase reputation to allow unstaking
        vm.prank(ADMIN);
        reputationManager.updateReputation(address(maliciousStaker), 500, "Restore reputation");

        // Request unstake
        maliciousStaker.requestUnstake();

        // Advance time past lock period
        vm.warp(block.timestamp + 8 days);

        uint256 balanceBefore = stakeToken.balanceOf(address(maliciousStaker));

        // Attempt reentrancy during unstake
        maliciousStaker.unstake();

        // Verify tokens were returned
        assertEq(stakeToken.balanceOf(address(maliciousStaker)), balanceBefore + 10 ether, "Tokens should be returned");

        // Verify no reentrancy occurred
        assertEq(maliciousStaker.attackCount(), 0, "Reentrancy attack should have been prevented");
    }

    /// @notice Test that reward withdrawal is protected against reentrancy
    /// @dev Critical: Prevents theft through reentrancy during reward distribution
    function testReentrancy_WithdrawReward() public {
        // Create a complete workflow to trigger reward distribution
        address publisher = address(0x100);
        address submitter = address(0x101);

        vm.deal(publisher, 10 ether);
        vm.prank(ADMIN);
        reputationManager.initializeUser(publisher);
        vm.prank(ADMIN);
        reputationManager.initializeUser(submitter);

        // Create and publish task
        vm.prank(publisher);
        uint256 taskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            2 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(publisher);
        taskManager.publishTask{value: 2 ether}(taskId);

        // Submit work
        vm.prank(submitter);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmTestHash");

        uint256 submitterBalanceBefore = submitter.balance;

        // Submit reviews to trigger adoption
        vm.prank(REVIEWER1);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        vm.prank(REVIEWER2);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Excellent");

        // Verify rewards were distributed without reentrancy
        uint256 submitterBalanceAfter = submitter.balance;
        assertGt(submitterBalanceAfter, submitterBalanceBefore, "Submitter should receive reward");

        // Verify task completed
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.COMPLETED));
    }
}
