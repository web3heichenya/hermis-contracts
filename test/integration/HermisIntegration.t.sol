// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {ArbitrationManager} from "../../src/core/ArbitrationManager.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
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
        if (totalReviews >= 2 && approveCount > rejectCount) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Majority approved");
        } else if (totalReviews >= 2 && rejectCount > approveCount) {
            return (DataTypes.SubmissionStatus.REMOVED, true, "Majority rejected");
        }
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Needs more reviews");
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

contract StrictAdoptionStrategy is IAdoptionStrategy {
    function evaluateSubmission(
        uint256 submissionId,
        uint256 approveCount,
        uint256 rejectCount,
        uint256 totalReviews,
        uint256 timeSinceSubmission
    ) external pure override returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) {
        submissionId;
        timeSinceSubmission;
        if (totalReviews >= 3 && approveCount > rejectCount) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Majority approved");
        } else if (totalReviews >= 3 && rejectCount > approveCount) {
            return (DataTypes.SubmissionStatus.REMOVED, true, "Majority rejected");
        }
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Needs more reviews");
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
        return ("StrictAdoptionStrategy", "1.0.0", "Strict adoption strategy requiring 3 reviews");
    }
}

/// @title HermisIntegrationTest
/// @notice Integration test for the complete Hermis platform workflow
contract HermisIntegrationTest is Test {
    // Core contracts
    TaskManager internal taskManager;
    SubmissionManager internal submissionManager;
    ArbitrationManager internal arbitrationManager;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    Treasury internal treasury;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;

    // Mock contracts
    MockToken internal stakeToken;
    MockToken internal feeToken;
    MockAdoptionStrategy internal mockAdoptionStrategy;
    StrictAdoptionStrategy internal strictAdoptionStrategy;

    // Test accounts
    address internal constant ADMIN = address(0x10);
    address internal constant PUBLISHER = address(0x11);
    address internal constant SUBMITTER1 = address(0x12);
    address internal constant SUBMITTER2 = address(0x13);
    address internal constant REVIEWER1 = address(0x14);
    address internal constant REVIEWER2 = address(0x15);

    // Test constants
    uint256 internal constant DEFAULT_TASK_REWARD = 10 ether;
    uint256 internal constant DEFAULT_ARBITRATION_FEE = 1 ether;

    function setUp() public {
        // Fund test accounts
        vm.deal(ADMIN, 1000 ether);
        vm.deal(PUBLISHER, 100 ether);
        vm.deal(SUBMITTER1, 100 ether);
        vm.deal(SUBMITTER2, 100 ether);
        vm.deal(REVIEWER1, 100 ether);
        vm.deal(REVIEWER2, 100 ether);

        // Deploy mock tokens
        stakeToken = new MockToken();
        feeToken = new MockToken();
        mockAdoptionStrategy = new MockAdoptionStrategy();
        strictAdoptionStrategy = new StrictAdoptionStrategy();

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

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
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowStrategy(address(strictAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

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

        // Deploy ArbitrationManager as upgradeable proxy
        ArbitrationManager arbitrationManagerImpl = new ArbitrationManager();
        bytes memory arbitrationManagerInitData = abi.encodeWithSelector(
            ArbitrationManager.initialize.selector,
            ADMIN,
            address(reputationManager),
            address(submissionManager),
            address(treasury),
            address(feeToken)
        );
        ERC1967Proxy arbitrationManagerProxy = new ERC1967Proxy(
            address(arbitrationManagerImpl),
            arbitrationManagerInitData
        );
        arbitrationManager = ArbitrationManager(address(arbitrationManagerProxy));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        // Set Treasury authorizations
        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(arbitrationManager), true);

        // Set cross-contract authorizations
        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(reputationManager), true);

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(arbitrationManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(taskManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(arbitrationManager), true);

        vm.prank(ADMIN);
        submissionManager.setAuthorizedContract(address(arbitrationManager), true);

        // Initialize users
        vm.prank(ADMIN);
        reputationManager.initializeUser(PUBLISHER);

        vm.prank(ADMIN);
        reputationManager.initializeUser(SUBMITTER1);

        vm.prank(ADMIN);
        reputationManager.initializeUser(SUBMITTER2);

        vm.prank(ADMIN);
        reputationManager.initializeUser(REVIEWER1);

        vm.prank(ADMIN);
        reputationManager.initializeUser(REVIEWER2);

        // Give users tokens
        stakeToken.mint(PUBLISHER, 50 ether);
        stakeToken.mint(SUBMITTER1, 50 ether);
        stakeToken.mint(SUBMITTER2, 50 ether);
        stakeToken.mint(REVIEWER1, 50 ether);
        stakeToken.mint(REVIEWER2, 50 ether);

        feeToken.mint(SUBMITTER1, 10 ether);
        feeToken.mint(SUBMITTER2, 10 ether);
    }

    /// @notice Test the core Hermis system integration: contracts work together correctly
    function testSystemIntegration_Success() public {
        console.log("=== Starting Hermis System Integration Test ===");

        // Step 1: Verify task creation works
        console.log("Step 1: Testing task creation...");
        vm.prank(PUBLISHER);
        uint256 taskId = taskManager.createTask(
            "Build Web3 Frontend",
            "Create a React frontend for our DeFi protocol",
            "Must use TypeScript, integrate with MetaMask, responsive design",
            "frontend",
            block.timestamp + 7 days,
            DEFAULT_TASK_REWARD,
            address(0), // ETH reward
            address(0), // No submission guard
            address(0), // No review guard
            address(mockAdoptionStrategy)
        );

        // Verify task was created
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);
        assertEq(task.publisher, PUBLISHER);
        assertEq(task.title, "Build Web3 Frontend");
        assertEq(uint256(task.status), uint256(DataTypes.TaskStatus.DRAFT));
        assertEq(task.adoptionStrategy, address(mockAdoptionStrategy));

        // Step 2: Verify MockAdoptionStrategy integration
        console.log("Step 2: Testing adoption strategy integration...");
        (string memory name, string memory version, string memory description) = mockAdoptionStrategy
            .getStrategyMetadata();
        assertEq(name, "MockAdoptionStrategy");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);

        // Test strategy evaluation logic
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = mockAdoptionStrategy
            .evaluateSubmission(1, 2, 0, 2, 0); // 2 approvals out of 2 reviews
        assertTrue(shouldChange);
        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertEq(reason, "Majority approved");

        // Step 3: Verify user initialization and SBT minting
        console.log("Step 3: Testing user initialization and SBTs...");
        assertTrue(hermisSBT.hasSBT(PUBLISHER));
        assertTrue(hermisSBT.hasSBT(SUBMITTER1));
        assertTrue(hermisSBT.hasSBT(SUBMITTER2));

        // Check SBT properties
        uint256 publisherTokenId = hermisSBT.getUserTokenId(PUBLISHER);
        assertEq(hermisSBT.ownerOf(publisherTokenId), PUBLISHER);
        assertTrue(publisherTokenId > 0);

        // Step 4: Verify reputation system integration
        console.log("Step 4: Testing reputation system...");
        (
            uint256 reputation,
            DataTypes.UserStatus status,
            uint256 stakedAmount,
            bool canUnstake,
            uint256 unlockTime
        ) = reputationManager.getUserReputation(PUBLISHER);

        assertEq(reputation, 1000); // Initial reputation
        assertEq(uint256(status), uint256(DataTypes.UserStatus.NORMAL));
        assertEq(stakedAmount, 0);
        assertFalse(canUnstake);
        assertEq(unlockTime, 0);

        // Step 5: Verify reward strategy integration
        console.log("Step 5: Testing reward strategy...");
        bytes memory strategyConfig = rewardStrategy.getRewardConfig();
        assertTrue(strategyConfig.length > 0);

        (string memory strategyName, string memory strategyVersion, string memory strategyDesc) = rewardStrategy
            .getRewardMetadata();
        assertEq(strategyName, "BasicRewardStrategy");
        assertEq(strategyVersion, "1.0.0");
        assertTrue(bytes(strategyDesc).length > 0);

        // Test reward calculation
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            taskId,
            1000,
            1,
            2 // 1000 total reward, submission 1 adopted, 2 reviewers
        );

        assertEq(distribution.creatorShare, 700); // 70% of 1000
        assertEq(distribution.reviewerShare, 200); // 20% of 1000
        assertEq(distribution.platformShare, 100); // 10% of 1000
        assertEq(distribution.publisherRefund, 0); // 0% of 1000

        // Step 6: Verify Treasury integration
        console.log("Step 6: Testing Treasury integration...");
        assertFalse(treasury.paused());
        assertEq(treasury.getTotalBalance(address(0)), 0); // No ETH deposited yet

        // Step 7: Test contract authorization setup
        console.log("Step 7: Verifying contract authorizations...");
        // These should not revert since we set up authorizations in setUp
        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true); // Should not revert

        console.log("=== Hermis System Integration Test Passed! ===");
    }

    /// @notice Test arbitration workflow when reputation is at risk
    function testArbitrationWorkflow_UserReputationAtRisk() public {
        console.log("=== Starting Arbitration Workflow Test ===");

        // Step 1: Reduce a user's reputation to at-risk level (but keep above arbitration minimum)
        vm.prank(ADMIN);
        reputationManager.updateReputation(SUBMITTER1, -450, "Quality issues with previous work");

        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputation, 550); // 1000 - 450
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK));

        // Add stake for AT_RISK user (reputation 550 requires 100 ether stake)
        stakeToken.mint(SUBMITTER1, 100 ether);
        vm.prank(SUBMITTER1);
        stakeToken.approve(address(reputationManager), 100 ether);
        vm.prank(SUBMITTER1);
        reputationManager.stake(100 ether, address(stakeToken));

        // Step 2: Lower arbitration fee to make test economical
        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(1 ether);
        assertEq(arbitrationManager.getArbitrationFee(), 1 ether);

        // Step 3: User requests arbitration and deposits fee
        uint256 balanceBeforeRequest = feeToken.balanceOf(SUBMITTER1);

        vm.startPrank(SUBMITTER1);
        feeToken.approve(address(arbitrationManager), 1 ether);
        uint256 arbitrationId = arbitrationManager.requestUserArbitration(
            SUBMITTER1,
            "Disputing recent penalty due to mitigating evidence",
            1 ether
        );
        vm.stopPrank();

        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(request.requester, SUBMITTER1);
        assertEq(request.depositAmount, 1 ether);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.PENDING));
        assertEq(treasury.getBalance(address(feeToken), "arbitration", arbitrationId), 1 ether);

        uint256[] memory pending = arbitrationManager.getPendingArbitrations(0, 10);
        assertEq(pending.length, 1);
        assertEq(pending[0], arbitrationId);

        // Step 4: Admin resolves arbitration in favour of the requester
        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(
            arbitrationId,
            DataTypes.ArbitrationStatus.APPROVED,
            "Evidence confirms mitigating factors"
        );

        request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.APPROVED));

        // Step 5: Execute arbitration to restore reputation and refund fee
        (reputation, status, , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputation, 550); // No change since reputation was already above minimum threshold
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK)); // Status based on reputation, not stake

        assertEq(treasury.getBalance(address(feeToken), "arbitration", arbitrationId), 0);
        assertEq(feeToken.balanceOf(SUBMITTER1), balanceBeforeRequest);

        console.log("=== Arbitration Workflow Test Passed ===");
    }

    function testArbitrationWorkflow_SubmissionStatusRestoration() public {
        console.log("=== Starting Submission Arbitration Workflow Test ===");

        vm.deal(PUBLISHER, DEFAULT_TASK_REWARD * 2);
        vm.prank(PUBLISHER);
        uint256 contestedTaskId = taskManager.createTask(
            "Contested Task",
            "Task subject to arbitration",
            "Deliver audited contract",
            "development",
            block.timestamp + 5 days,
            DEFAULT_TASK_REWARD,
            address(0),
            address(0),
            address(0),
            address(strictAdoptionStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: DEFAULT_TASK_REWARD}(contestedTaskId);

        vm.prank(SUBMITTER1);
        uint256 contestedSubmissionId = submissionManager.submitWork(contestedTaskId, "QmContestedSubmission");

        // Remove submission through negative reviews
        vm.prank(REVIEWER1);
        submissionManager.submitReview(contestedSubmissionId, DataTypes.ReviewOutcome.REJECT, "Needs work");
        vm.prank(REVIEWER2);
        submissionManager.submitReview(contestedSubmissionId, DataTypes.ReviewOutcome.REJECT, "Low quality");

        address reviewer3 = address(0xA11);
        _configureReviewer(reviewer3);
        vm.prank(reviewer3);
        submissionManager.submitReview(
            contestedSubmissionId,
            DataTypes.ReviewOutcome.REJECT,
            "Does not meet requirements"
        );
        DataTypes.SubmissionInfo memory removedSubmission = submissionManager.getSubmission(contestedSubmissionId);
        assertEq(uint256(removedSubmission.status), uint256(DataTypes.SubmissionStatus.REMOVED));

        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(1 ether);

        vm.startPrank(SUBMITTER1);
        feeToken.approve(address(arbitrationManager), 1 ether);
        uint256 arbitrationId = arbitrationManager.requestSubmissionArbitration(
            contestedSubmissionId,
            "Submission unfairly removed",
            1 ether
        );
        vm.stopPrank();

        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.PENDING));
        assertEq(request.targetId, contestedSubmissionId);
        assertEq(treasury.getBalance(address(feeToken), "arbitration", arbitrationId), 1 ether);

        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(
            arbitrationId,
            DataTypes.ArbitrationStatus.APPROVED,
            "Submission warrants reinstatement"
        );

        removedSubmission = submissionManager.getSubmission(contestedSubmissionId);
        assertEq(uint256(removedSubmission.status), uint256(DataTypes.SubmissionStatus.NORMAL));
        assertEq(treasury.getBalance(address(feeToken), "arbitration", arbitrationId), 0);

        uint256[] memory pendingAfter = arbitrationManager.getPendingArbitrations(0, 10);
        assertEq(pendingAfter.length, 0);

        console.log("=== Submission Arbitration Workflow Test Passed ===");
    }

    function testArbitrationWorkflow_RejectionPenalizesRequester() public {
        console.log("=== Starting Arbitration Rejection Penalty Test ===");

        vm.prank(ADMIN);
        reputationManager.updateReputation(SUBMITTER1, -450, "Reduce reputation for dispute");
        (uint256 reputationBefore, , , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputationBefore, 550);

        // Add stake for AT_RISK user (reputation 550 requires 100 ether stake)
        stakeToken.mint(SUBMITTER1, 100 ether);
        vm.prank(SUBMITTER1);
        stakeToken.approve(address(reputationManager), 100 ether);
        vm.prank(SUBMITTER1);
        reputationManager.stake(100 ether, address(stakeToken));

        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(1 ether);

        vm.startPrank(SUBMITTER1);
        feeToken.approve(address(arbitrationManager), 1 ether);
        uint256 arbitrationId = arbitrationManager.requestUserArbitration(
            SUBMITTER1,
            "Requesting review of penalty",
            1 ether
        );
        vm.stopPrank();

        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(
            arbitrationId,
            DataTypes.ArbitrationStatus.REJECTED,
            "Insufficient evidence"
        );

        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.REJECTED));

        (uint256 reputationAfter, , , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputationAfter, reputationBefore - 100);

        assertEq(treasury.getBalance(address(feeToken), "arbitration", arbitrationId), 1 ether);

        uint256[] memory pendingAfter = arbitrationManager.getPendingArbitrations(0, 10);
        assertEq(pendingAfter.length, 0);

        console.log("=== Arbitration Rejection Penalty Test Passed ===");
    }

    function testArbitrationRequest_RevertsForAdoptedSubmission() public {
        console.log("=== Starting Arbitration Request Validation Test ===");

        vm.deal(PUBLISHER, DEFAULT_TASK_REWARD * 2);
        vm.prank(PUBLISHER);
        uint256 adoptedTaskId = taskManager.createTask(
            "Adopted Submission Task",
            "Task destined for adoption",
            "Deliver production-ready contract",
            "development",
            block.timestamp + 7 days,
            DEFAULT_TASK_REWARD,
            address(0),
            address(0),
            address(0),
            address(mockAdoptionStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: DEFAULT_TASK_REWARD}(adoptedTaskId);

        vm.prank(SUBMITTER1);
        uint256 adoptedSubmissionId = submissionManager.submitWork(adoptedTaskId, "QmAdoptedSubmission");

        // Gather approvals to ensure adoption
        vm.prank(REVIEWER1);
        submissionManager.submitReview(adoptedSubmissionId, DataTypes.ReviewOutcome.APPROVE, "Excellent");
        vm.prank(REVIEWER2);
        submissionManager.submitReview(adoptedSubmissionId, DataTypes.ReviewOutcome.APPROVE, "Meets all requirements");

        DataTypes.SubmissionInfo memory adoptedSubmission = submissionManager.getSubmission(adoptedSubmissionId);
        assertEq(uint256(adoptedSubmission.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(1 ether);

        vm.startPrank(SUBMITTER1);
        feeToken.approve(address(arbitrationManager), 1 ether);
        vm.expectRevert();
        arbitrationManager.requestSubmissionArbitration(
            adoptedSubmissionId,
            "Should not allow arbitration for adopted submission",
            1 ether
        );
        vm.stopPrank();

        console.log("=== Arbitration Request Validation Test Passed ===");
    }

    function testArbitrationRequest_RevertsForLowReputationUser() public {
        console.log("=== Starting Arbitration Eligibility Test ===");

        vm.prank(ADMIN);
        reputationManager.updateReputation(SUBMITTER2, -800, "Severe penalty");
        (uint256 reputation, , , , ) = reputationManager.getUserReputation(SUBMITTER2);
        assertLt(reputation, 500);

        vm.startPrank(SUBMITTER2);
        feeToken.approve(address(arbitrationManager), 1 ether);
        vm.expectRevert();
        arbitrationManager.requestUserArbitration(
            SUBMITTER2,
            "Attempting arbitration without sufficient reputation",
            1 ether
        );
        vm.stopPrank();

        console.log("=== Arbitration Eligibility Test Passed ===");
    }

    function _configureReviewer(address reviewer) internal {
        vm.prank(ADMIN);
        reputationManager.initializeUser(reviewer);
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(reviewer, "development", 900);
        vm.prank(reviewer);
        reputationManager.claimCategoryScore("development", 900);
    }

    /// @notice Test staking mechanism for at-risk users
    function testStakingMechanism() public {
        console.log("=== Starting Staking Mechanism Test ===");

        // Step 1: Reduce user reputation to require staking
        vm.prank(ADMIN);
        reputationManager.updateReputation(SUBMITTER1, -500, "Quality issues require staking");

        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(reputation, 500);
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK));

        // Step 2: User stakes to improve status
        vm.prank(SUBMITTER1);
        stakeToken.approve(address(reputationManager), 5 ether);

        vm.prank(SUBMITTER1);
        reputationManager.stake(5 ether, address(stakeToken));

        // Step 3: Verify staking was successful
        (, , uint256 stakedAmount, , ) = reputationManager.getUserReputation(SUBMITTER1);
        assertEq(stakedAmount, 5 ether);

        console.log("=== Staking Mechanism Test Passed ===");
    }

    function testRewardDistribution_WithErc20Funding() public {
        console.log("=== Starting ERC20 Reward Distribution Test ===");

        // Publisher creates ERC20-denominated task
        vm.prank(PUBLISHER);
        uint256 erc20TaskId = taskManager.createTask(
            "ERC20 Reward Task",
            "Deliver audited smart contracts",
            "Provide full test coverage and deployment scripts",
            "development",
            block.timestamp + 5 days,
            DEFAULT_TASK_REWARD,
            address(stakeToken),
            address(0),
            address(0),
            address(mockAdoptionStrategy)
        );

        uint256 publisherBalanceBefore = stakeToken.balanceOf(PUBLISHER);

        // Fund treasury with ERC20 reward during publish
        vm.startPrank(PUBLISHER);
        stakeToken.approve(address(taskManager), DEFAULT_TASK_REWARD);
        taskManager.publishTask(erc20TaskId);
        vm.stopPrank();

        assertEq(publisherBalanceBefore - stakeToken.balanceOf(PUBLISHER), DEFAULT_TASK_REWARD);
        assertEq(treasury.getBalance(address(stakeToken), "task", erc20TaskId), DEFAULT_TASK_REWARD);

        // Submit work and gather approvals
        vm.prank(SUBMITTER1);
        uint256 submissionId = submissionManager.submitWork(erc20TaskId, "QmERC20SubmissionHash");

        uint256 submitterBalanceBefore = stakeToken.balanceOf(SUBMITTER1);
        uint256 reviewer1BalanceBefore = stakeToken.balanceOf(REVIEWER1);
        uint256 reviewer2BalanceBefore = stakeToken.balanceOf(REVIEWER2);

        vm.prank(REVIEWER1);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Strong delivery");
        vm.prank(REVIEWER2);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Meets criteria");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(uint256(submission.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        BasicRewardStrategy.BasicRewardConfig memory config = abi.decode(
            rewardStrategy.getRewardConfig(),
            (BasicRewardStrategy.BasicRewardConfig)
        );

        uint256 expectedCreatorShare = (DEFAULT_TASK_REWARD * config.creatorPercentage) / 100;
        uint256 baseReviewerShare = (DEFAULT_TASK_REWARD * config.reviewerPercentage) / 100;
        // Both reviewers are accurate (APPROVE + submission adopted), so they get accuracy bonus
        uint256 expectedReviewerShare = baseReviewerShare + (baseReviewerShare * config.accuracyBonus) / 100;
        uint256 expectedPlatformShare = (DEFAULT_TASK_REWARD * config.platformPercentage) / 100;
        // Remaining task balance after creator and reviewer rewards (extra reviewer rewards paid from task balance)
        uint256 expectedTaskBalance = DEFAULT_TASK_REWARD - expectedCreatorShare - expectedReviewerShare;

        assertEq(stakeToken.balanceOf(SUBMITTER1) - submitterBalanceBefore, expectedCreatorShare);

        uint256 reviewer1Gain = stakeToken.balanceOf(REVIEWER1) - reviewer1BalanceBefore;
        uint256 reviewer2Gain = stakeToken.balanceOf(REVIEWER2) - reviewer2BalanceBefore;
        assertEq(reviewer1Gain + reviewer2Gain, expectedReviewerShare);

        assertEq(treasury.getBalance(address(stakeToken), "task", erc20TaskId), expectedTaskBalance);
        assertEq(treasury.getPlatformFeeBalance(address(stakeToken)), expectedPlatformShare);

        DataTypes.TaskInfo memory completedTask = taskManager.getTask(erc20TaskId);
        assertEq(uint256(completedTask.status), uint256(DataTypes.TaskStatus.COMPLETED));

        console.log("=== ERC20 Reward Distribution Test Passed ===");
    }
}
