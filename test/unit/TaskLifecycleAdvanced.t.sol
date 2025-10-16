// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {BasicRewardStrategy} from "../../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";
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

    function updateStrategyConfig(bytes calldata newConfig) external override {}

    function getStrategyMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return ("MockAdoptionStrategy", "1.0.0", "Simple mock adoption strategy for testing");
    }
}

/// @title TaskLifecycleAdvancedTest
/// @notice Advanced task lifecycle tests - covering missing edge cases
contract TaskLifecycleAdvancedTest is Test {
    TaskManager internal taskManager;
    SubmissionManager internal submissionManager;
    Treasury internal treasury;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;
    MockToken internal stakeToken;
    MockAdoptionStrategy internal mockAdoptionStrategy;

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

        // Deploy AllowlistManager
        AllowlistManager allowlistManagerImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, ADMIN);
        ERC1967Proxy allowlistManagerProxy = new ERC1967Proxy(address(allowlistManagerImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistManagerProxy));

        // Deploy TaskManager
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

        // Deploy BasicRewardStrategy
        rewardStrategy = new BasicRewardStrategy(ADMIN);
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

        // Deploy SubmissionManager
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

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(taskManager), true);

        // Initialize users
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        vm.prank(ADMIN);
        reputationManager.initializeUser(CHARLIE);

        // Deploy MockAdoptionStrategy
        mockAdoptionStrategy = new MockAdoptionStrategy();

        // Allow mock contracts in AllowlistManager
        vm.startPrank(ADMIN);
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        // Give users some tokens
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           TASK EXPIRATION TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test that expired tasks cannot accept submissions
    function testExpiredTask_CannotAcceptSubmissions() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        // Fast forward past deadline
        vm.warp(block.timestamp + DEFAULT_DEADLINE_OFFSET + 1);

        // Check task cannot accept submissions
        (bool canAccept, string memory reason) = taskManager.canAcceptSubmissions(taskId);
        assertFalse(canAccept);
        assertEq(reason, "Task deadline passed");
    }

    /// @notice Test refund logic for expired tasks
    function testExpiredTask_RefundPublisher() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        uint256 aliceBalanceBefore = ALICE.balance;

        // Fast forward past deadline
        vm.warp(block.timestamp + DEFAULT_DEADLINE_OFFSET + 1);

        // Publisher cancels expired task to get refund
        vm.prank(ALICE);
        taskManager.cancelTask(taskId, "Task expired without submissions");

        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.CANCELLED));

        // Verify refund was issued
        assertGt(ALICE.balance, aliceBalanceBefore);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           MULTIPLE SUBMISSION COMPETITION TESTS            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test multiple submitters competing for same task
    function testMultipleSubmissions_CompetitionScenario() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        // BOB submits first
        vm.prank(BOB);
        uint256 submission1 = submissionManager.submitWork(taskId, "QmBobsWork");

        // CHARLIE submits second
        vm.prank(CHARLIE);
        uint256 submission2 = submissionManager.submitWork(taskId, "QmCharliesWork");

        // Verify both submissions exist
        DataTypes.SubmissionInfo memory sub1 = submissionManager.getSubmission(submission1);
        DataTypes.SubmissionInfo memory sub2 = submissionManager.getSubmission(submission2);

        assertEq(sub1.submitter, BOB);
        assertEq(sub2.submitter, CHARLIE);
        assertEq(sub1.taskId, taskId);
        assertEq(sub2.taskId, taskId);

        // Get all submissions for task
        uint256[] memory submissions = submissionManager.getTaskSubmissions(taskId, 0, 10);
        assertEq(submissions.length, 2);
    }

    /// @notice Test that only one submission is adopted
    function testMultipleSubmissions_OnlyOneAdopted() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submission1 = submissionManager.submitWork(taskId, "QmBobsWork");

        vm.prank(CHARLIE);
        uint256 submission2 = submissionManager.submitWork(taskId, "QmCharliesWork");

        // Reviewer approves BOB's submission
        address reviewer = address(0x99);
        vm.prank(ADMIN);
        reputationManager.initializeUser(reviewer);

        vm.prank(reviewer);
        submissionManager.submitReview(submission1, DataTypes.ReviewOutcome.APPROVE, "Good work");

        // Verify submission1 is adopted
        DataTypes.SubmissionInfo memory sub1 = submissionManager.getSubmission(submission1);
        assertEq(uint256(sub1.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        // Verify task is completed
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.COMPLETED));
        assertEq(task.adoptedSubmissionId, submission1);

        // Verify submission2 is still under review (not adopted)
        DataTypes.SubmissionInfo memory sub2 = submissionManager.getSubmission(submission2);
        assertEq(uint256(sub2.status), uint256(DataTypes.SubmissionStatus.SUBMITTED));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           TASK CANCELLATION REFUND TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test cancelling task with active submissions should fail
    function testCancelTask_WithActiveSubmissions() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        // BOB submits work, task becomes ACTIVE
        vm.prank(BOB);
        submissionManager.submitWork(taskId, "QmBobsWork");

        // ALICE tries to cancel task but should fail (task is ACTIVE)
        vm.prank(ALICE);
        vm.expectRevert();
        taskManager.cancelTask(taskId, "Requirements changed");
    }

    /// @notice Test that submissions are blocked after task cancellation
    function testCancelTask_SubmissionsBlocked() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        // Cancel task
        vm.prank(ALICE);
        taskManager.cancelTask(taskId, "Changed mind");

        // BOB tries to submit
        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmBobsWork");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           TASK REWARD INCREASE TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test increasing task reward after publication
    function testIncreaseTaskReward_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        uint256 additionalReward = 0.5 ether;
        vm.deal(ALICE, additionalReward * 2);

        // Increase reward
        vm.prank(ALICE);
        taskManager.increaseTaskReward{value: additionalReward}(taskId, additionalReward);

        // Verify increased reward
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(task.reward, DEFAULT_TASK_REWARD + additionalReward);
    }

    /// @notice Test that non-publisher cannot increase reward
    function testIncreaseTaskReward_RevertWhenNotPublisher() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        vm.expectRevert();
        taskManager.increaseTaskReward{value: 0.5 ether}(taskId, 0.5 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           HELPER FUNCTIONS                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _createAndPublishTask(address publisher) internal returns (uint256 taskId) {
        vm.prank(publisher);
        taskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + DEFAULT_DEADLINE_OFFSET,
            DEFAULT_TASK_REWARD,
            address(0),
            address(0),
            address(0),
            address(mockAdoptionStrategy)
        );

        vm.deal(publisher, DEFAULT_TASK_REWARD * 2);
        vm.prank(publisher);
        taskManager.publishTask{value: DEFAULT_TASK_REWARD}(taskId);
    }
}
