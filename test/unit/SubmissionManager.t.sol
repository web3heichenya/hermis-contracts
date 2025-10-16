// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {BasicRewardStrategy} from "../../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";
import {IGuard} from "../../src/interfaces/IGuard.sol";
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
        return adoptedSubmissionId > 0;
    }

    function getStrategyConfig() external pure override returns (bytes memory config) {
        return "";
    }

    function updateStrategyConfig(bytes calldata newConfig) external override {
        // Mock implementation
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

contract TestAccessGuard is IGuard {
    mapping(address => bool) internal allowed;

    function setAllowed(address user, bool value) external {
        allowed[user] = value;
    }

    function validateUser(address user, bytes calldata data) external view returns (bool, string memory) {
        data;
        if (!allowed[user]) {
            return (false, "Guard: user not permitted");
        }
        return (true, "");
    }

    function getGuardConfig() external pure returns (bytes memory config) {
        return config;
    }

    function updateGuardConfig(bytes calldata newConfig) external override {}

    function getGuardMetadata()
        external
        pure
        returns (string memory name, string memory version, string memory description)
    {
        return ("TestAccessGuard", "1.0.0", "Test guard for access control flows");
    }
}

contract SubmissionManagerTest is Test {
    SubmissionManager internal submissionManager;
    TaskManager internal taskManager;
    Treasury internal treasury;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;
    MockToken internal stakeToken;
    MockAdoptionStrategy internal mockAdoptionStrategy;
    TestAccessGuard internal accessGuard;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant CHARLIE = address(0x3);
    address internal constant ADMIN = address(0x10);

    uint256 internal constant DEFAULT_TASK_REWARD = 1 ether;
    uint256 internal constant DEFAULT_DEADLINE_OFFSET = 7 days;

    function setUp() public {
        // Fund test accounts
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(ADMIN, 100 ether);

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy mock stake token
        stakeToken = new MockToken();

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

        // Deploy TaskManager as upgradeable proxy
        TaskManager taskManagerImpl = new TaskManager();
        bytes memory taskManagerInitData = abi.encodeWithSelector(
            TaskManager.initialize.selector,
            ADMIN,
            address(treasury),
            address(reputationManager),
            address(allowlistManager)
        );
        ERC1967Proxy taskManagerProxy = new ERC1967Proxy(address(taskManagerImpl), taskManagerInitData);
        taskManager = TaskManager(address(taskManagerProxy));

        // Deploy BasicRewardStrategy
        rewardStrategy = new BasicRewardStrategy(ADMIN);

        // Initialize BasicRewardStrategy with default config
        bytes memory defaultConfig = abi.encode(
            BasicRewardStrategy.BasicRewardConfig({
                creatorPercentage: 80,
                reviewerPercentage: 15,
                platformPercentage: 5,
                accuracyBonus: 20,
                accuracyPenalty: 10,
                minReviewerReward: 0,
                maxReviewerReward: 0
            })
        );
        vm.prank(ADMIN);
        rewardStrategy.initializeRewardStrategy(defaultConfig);

        // Deploy SubmissionManager as upgradeable proxy
        SubmissionManager submissionManagerImpl = new SubmissionManager();
        bytes memory submissionManagerInitData = abi.encodeWithSelector(
            SubmissionManager.initialize.selector,
            ADMIN,
            address(taskManager),
            address(reputationManager),
            address(treasury),
            address(rewardStrategy)
        );
        ERC1967Proxy submissionManagerProxy = new ERC1967Proxy(
            address(submissionManagerImpl),
            submissionManagerInitData
        );
        submissionManager = SubmissionManager(address(submissionManagerProxy));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(submissionManager), true);

        // Authorize SubmissionManager to interact with TaskManager
        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(submissionManager), true);

        // Authorize SubmissionManager to interact with ReputationManager
        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        // Fund TaskManager with ETH for rewards
        vm.deal(address(taskManager), 100 ether);

        // Initialize users
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        vm.prank(ADMIN);
        reputationManager.initializeUser(CHARLIE);

        // Deploy MockAdoptionStrategy
        mockAdoptionStrategy = new MockAdoptionStrategy();
        accessGuard = new TestAccessGuard();

        // Allow mock contracts in AllowlistManager
        vm.startPrank(ADMIN);
        allowlistManager.allowGuard(address(accessGuard));
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        // Give users some tokens
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);
    }

    function testSubmitWork_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        // Verify submission was created
        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(submission.taskId, taskId);
        assertEq(submission.submitter, BOB);
        assertEq(submission.contentHash, "QmBobsWork123");
        assertEq(uint256(submission.status), uint256(DataTypes.SubmissionStatus.SUBMITTED));

        // Verify task was activated
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.ACTIVE));
    }

    function testSubmitWork_RevertWhenSubmissionGuardRejects() public {
        uint256 taskId = _createTaskWithSubmissionGuard(ALICE, address(accessGuard));
        _publishTask(taskId, ALICE);

        // Guard denies BOB by default
        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmBobsWork123");
    }

    function testCanSubmitToTask_ReturnsGuardReason() public {
        uint256 taskId = _createTaskWithSubmissionGuard(ALICE, address(accessGuard));
        _publishTask(taskId, ALICE);

        (bool canSubmit, string memory reason) = submissionManager.canSubmitToTask(BOB, taskId);
        assertFalse(canSubmit);
        assertEq(reason, "Guard: user not permitted");

        // Allow BOB and verify granting access updates response
        accessGuard.setAllowed(BOB, true);
        (canSubmit, reason) = submissionManager.canSubmitToTask(BOB, taskId);
        assertTrue(canSubmit);
        assertEq(bytes(reason).length, 0);
    }

    function testSubmitWork_RevertWhenTaskNotAcceptingSubmissions() public {
        uint256 taskId = _createBasicTask(ALICE); // Draft task

        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmBobsWork123");
    }

    function testReviewSubmission_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        vm.prank(CHARLIE);
        uint256 reviewId = submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        // Verify review was recorded
        DataTypes.ReviewInfo memory review = submissionManager.getReview(reviewId);
        assertEq(review.submissionId, submissionId);
        assertEq(review.reviewer, CHARLIE);
        assertEq(uint256(review.outcome), uint256(DataTypes.ReviewOutcome.APPROVE));
        assertEq(review.reason, "Good work");

        // Verify submission counters updated
        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(submission.approveCount, 1);
        assertEq(submission.rejectCount, 0);
    }

    function testReviewSubmission_TriggersAdoptionAndRewards() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        uint256 submitterBalanceBefore = BOB.balance;

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Excellent");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(uint8(submission.status), uint8(DataTypes.SubmissionStatus.ADOPTED));

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint8(task.status), uint8(DataTypes.TaskStatus.COMPLETED));

        // Creator receives reward share after adoption
        assertGt(BOB.balance, submitterBalanceBefore);
    }

    function testReviewSubmission_RevertWhenReviewingOwnSubmission() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        // BOB trying to review his own submission
        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Self review");
    }

    function testReviewSubmission_RevertWhenAlreadyReviewed() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        // CHARLIE trying to review again
        vm.prank(CHARLIE);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Changed mind");
    }

    function testCanSubmitToTask_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        (bool canSubmit, string memory reason) = submissionManager.canSubmitToTask(BOB, taskId);
        assertTrue(canSubmit);
        assertEq(bytes(reason).length, 0);
    }

    function testCanSubmitToTask_RevertWhenTaskPublisher() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        (bool canSubmit, string memory reason) = submissionManager.canSubmitToTask(ALICE, taskId);
        assertFalse(canSubmit);
        assertTrue(bytes(reason).length > 0);
    }

    function testCanReviewSubmission_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        (bool canReview, string memory reason) = submissionManager.canReviewSubmission(CHARLIE, submissionId);
        assertTrue(canReview);
        assertEq(bytes(reason).length, 0);
    }

    function testGetSubmissionsByTask() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        // Create multiple submissions
        vm.prank(BOB);
        submissionManager.submitWork(taskId, "QmBobsWork123");

        vm.prank(CHARLIE);
        submissionManager.submitWork(taskId, "QmCharliesWork456");

        uint256[] memory submissions = submissionManager.getTaskSubmissions(taskId, 0, 10);
        assertEq(submissions.length, 2);
    }

    function testGetSubmissionsByUser() public {
        uint256 taskId1 = _createAndPublishTask(ALICE);
        uint256 taskId2 = _createAndPublishTask(ALICE);

        // BOB submits to both tasks
        vm.prank(BOB);
        submissionManager.submitWork(taskId1, "QmBobsWork123");

        vm.prank(BOB);
        submissionManager.submitWork(taskId2, "QmBobsWork456");

        uint256[] memory submissions = submissionManager.getUserSubmissions(BOB, 0, 10);
        assertEq(submissions.length, 2);
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
                address(mockAdoptionStrategy) // Use mockAdoptionStrategy
            );
    }

    function _createTaskWithSubmissionGuard(address publisher, address guardAddress) internal returns (uint256) {
        vm.prank(publisher);
        return
            taskManager.createTask(
                "Guarded Task",
                "Requires guard approval",
                "Guarded requirements",
                "development",
                block.timestamp + DEFAULT_DEADLINE_OFFSET,
                DEFAULT_TASK_REWARD,
                address(0),
                guardAddress,
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

    function _createAndPublishTask(address publisher) internal returns (uint256 taskId) {
        taskId = _createBasicTask(publisher);
        _publishTask(taskId, publisher);
    }
}
