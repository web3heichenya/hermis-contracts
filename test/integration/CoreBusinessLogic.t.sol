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

/// @title CoreBusinessLogicTest
/// @notice Critical tests for core crowdsourcing business logic
/// @dev Tests multi-submission competition, reviewer duplication, staking access, etc.
contract CoreBusinessLogicTest is Test {
    TaskManager internal taskManager;
    SubmissionManager internal submissionManager;
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;
    MockToken internal stakeToken;
    MockAdoptionStrategy internal mockStrategy;

    address internal constant ADMIN = address(0x1);
    address internal constant PUBLISHER = address(0x2);
    address internal constant SUBMITTER1 = address(0x3);
    address internal constant SUBMITTER2 = address(0x4);
    address internal constant SUBMITTER3 = address(0x5);
    address internal constant REVIEWER1 = address(0x6);
    address internal constant REVIEWER2 = address(0x7);

    function setUp() public {
        vm.deal(ADMIN, 100 ether);
        vm.deal(PUBLISHER, 100 ether);
        vm.deal(SUBMITTER1, 100 ether);
        vm.deal(SUBMITTER2, 100 ether);
        vm.deal(SUBMITTER3, 100 ether);
        vm.deal(REVIEWER1, 100 ether);
        vm.deal(REVIEWER2, 100 ether);

        // Deploy contracts
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
        vm.stopPrank();

        // Initialize users
        vm.startPrank(ADMIN);
        reputationManager.initializeUser(PUBLISHER);
        reputationManager.initializeUser(SUBMITTER1);
        reputationManager.initializeUser(SUBMITTER2);
        reputationManager.initializeUser(SUBMITTER3);
        reputationManager.initializeUser(REVIEWER1);
        reputationManager.initializeUser(REVIEWER2);
        vm.stopPrank();

        stakeToken.mint(SUBMITTER1, 100 ether);
        stakeToken.mint(SUBMITTER2, 100 ether);
    }

    /// @notice Test that only one submission can be adopted per task
    /// @dev Critical: Prevents double-payment by ensuring single winner
    function testMultipleSubmissions_OnlyOneAdopted() public {
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Competition Task",
            "Best solution wins",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            10 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 10 ether}(taskId);

        // Three submitters compete
        vm.prank(SUBMITTER1);
        uint256 submission1 = submissionManager.submitWork(taskId, "QmHash1");

        vm.prank(SUBMITTER2);
        uint256 submission2 = submissionManager.submitWork(taskId, "QmHash2");

        vm.prank(SUBMITTER3);
        uint256 submission3 = submissionManager.submitWork(taskId, "QmHash3");

        // First submission gets approved and adopted
        vm.prank(REVIEWER1);
        submissionManager.submitReview(submission1, DataTypes.ReviewOutcome.APPROVE, "Best solution");
        vm.prank(REVIEWER2);
        submissionManager.submitReview(submission1, DataTypes.ReviewOutcome.APPROVE, "Excellent");

        // Verify first submission is adopted
        DataTypes.SubmissionInfo memory sub1 = submissionManager.getSubmission(submission1);
        assertEq(uint256(sub1.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        // Verify task is completed with ONLY this submission
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.COMPLETED));
        assertEq(task.adoptedSubmissionId, submission1, "Only first submission should be adopted");

        // Verify other submissions are NOT adopted
        DataTypes.SubmissionInfo memory sub2 = submissionManager.getSubmission(submission2);
        DataTypes.SubmissionInfo memory sub3 = submissionManager.getSubmission(submission3);

        assertTrue(
            uint256(sub2.status) != uint256(DataTypes.SubmissionStatus.ADOPTED),
            "Second submission should not be adopted"
        );
        assertTrue(
            uint256(sub3.status) != uint256(DataTypes.SubmissionStatus.ADOPTED),
            "Third submission should not be adopted"
        );

        // Critical: Task has exactly ONE adopted submission ID
        // This prevents double-payment - only one winner gets the reward
    }

    /// @notice Test that reviewer cannot review the same submission twice
    /// @dev Critical: Prevents vote manipulation through duplicate reviews
    function testReviewerDuplication_Prevention() public {
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            5 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 5 ether}(taskId);

        vm.prank(SUBMITTER1);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmHash");

        // First review
        vm.prank(REVIEWER1);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        // Attempt second review from same reviewer (should revert)
        vm.prank(REVIEWER1);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Trying again");
    }

    /// @notice Test that AT_RISK users must stake to access system
    /// @dev Critical: Enforces staking requirements for low-reputation users
    function testStaking_RequiredForAccess() public {
        // Reduce reputation to AT_RISK level
        vm.prank(ADMIN);
        reputationManager.updateReputation(SUBMITTER1, -500, "Quality issues");

        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputation, 500);
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK));

        // Create a task
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            5 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 5 ether}(taskId);

        // AT_RISK user without stake should fail to submit
        vm.prank(SUBMITTER1);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmHash");

        // User stakes required amount
        uint256 requiredStake = reputationManager.getRequiredStakeAmount(SUBMITTER1);
        stakeToken.mint(SUBMITTER1, requiredStake);

        vm.prank(SUBMITTER1);
        stakeToken.approve(address(reputationManager), requiredStake);

        vm.prank(SUBMITTER1);
        reputationManager.stake(requiredStake, address(stakeToken));

        // Now submission should succeed
        vm.prank(SUBMITTER1);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmHash");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(submission.submitter, SUBMITTER1);
    }

    /// @notice Test that task publisher cannot submit to their own task
    /// @dev High: Prevents self-dealing and ensures fairness
    function testPublisherCannotSubmit_OwnTask() public {
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            5 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 5 ether}(taskId);

        // Publisher tries to submit to own task (should fail)
        vm.prank(PUBLISHER);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmHash");
    }

    /// @notice Test complete workflow from task creation to completion
    /// @dev Integration: Verifies entire crowdsourcing lifecycle works correctly
    function testFullLifecycle_TaskToCompletion() public {
        uint256 publisherBalanceBefore = PUBLISHER.balance;
        uint256 submitterBalanceBefore = SUBMITTER1.balance;

        // 1. Create task
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Full Lifecycle Task",
            "Complete workflow test",
            "Deliver working code",
            "development",
            block.timestamp + 7 days,
            10 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        DataTypes.TaskInfo memory task1 = taskManager.getTask(taskId);
        assertEq(uint256(task1.status), uint256(DataTypes.TaskStatus.DRAFT));

        // 2. Publish task
        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 10 ether}(taskId);

        DataTypes.TaskInfo memory task2 = taskManager.getTask(taskId);
        assertEq(uint256(task2.status), uint256(DataTypes.TaskStatus.PUBLISHED));

        // 3. Submit work
        vm.prank(SUBMITTER1);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWorkHash");

        DataTypes.SubmissionInfo memory sub1 = submissionManager.getSubmission(submissionId);
        assertEq(uint256(sub1.status), uint256(DataTypes.SubmissionStatus.SUBMITTED));

        // 4. Review work
        vm.prank(REVIEWER1);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Meets requirements");

        vm.prank(REVIEWER2);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good quality");

        // 5. Verify adoption and completion
        DataTypes.SubmissionInfo memory sub2 = submissionManager.getSubmission(submissionId);
        assertEq(uint256(sub2.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        DataTypes.TaskInfo memory task3 = taskManager.getTask(taskId);
        assertEq(uint256(task3.status), uint256(DataTypes.TaskStatus.COMPLETED));
        assertEq(task3.adoptedSubmissionId, submissionId);

        // 6. Verify rewards distributed
        uint256 submitterGain = SUBMITTER1.balance - submitterBalanceBefore;
        assertGt(submitterGain, 0, "Submitter should receive reward");

        uint256 publisherCost = publisherBalanceBefore - PUBLISHER.balance;
        assertGe(publisherCost, 10 ether, "Publisher should pay task reward");
    }
}
