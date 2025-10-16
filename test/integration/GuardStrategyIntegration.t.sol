// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Core contracts
import {TaskManager} from "../../src/core/TaskManager.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";

// Guards
import {GlobalGuard} from "../../src/guards/global/GlobalGuard.sol";
import {SubmissionGuard} from "../../src/guards/task/SubmissionGuard.sol";
import {ReviewGuard} from "../../src/guards/task/ReviewGuard.sol";

// Strategies
import {SimpleAdoptionStrategy} from "../../src/strategies/adoption/SimpleAdoptionStrategy.sol";
import {BasicRewardStrategy} from "../../src/strategies/reward/BasicRewardStrategy.sol";

// Libraries and interfaces
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Stake Token", "MST") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title GuardStrategyIntegrationTest
/// @notice Comprehensive integration test for Guards and Strategies with all core contracts
/// @dev Tests complete workflow with access control and reward distribution
contract GuardStrategyIntegrationTest is Test, IAdoptionStrategy {
    // Core contracts
    TaskManager internal taskManager;
    SubmissionManager internal submissionManager;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    Treasury internal treasury;
    HermisSBT internal hermisSBT;

    // Guards
    GlobalGuard internal globalGuard;
    SubmissionGuard internal submissionGuard;
    ReviewGuard internal reviewGuard;

    // Strategies
    SimpleAdoptionStrategy internal adoptionStrategy;
    BasicRewardStrategy internal rewardStrategy;

    // Tokens
    MockToken internal stakeToken;

    // Test users
    address internal constant ADMIN = address(0x1);
    address internal constant PUBLISHER = address(0x2);
    address internal constant DEVELOPER = address(0x3);
    address internal constant DEVELOPER2 = address(0x7);
    address internal constant REVIEWER1 = address(0x4);
    address internal constant REVIEWER2 = address(0x5);
    address internal constant NEW_USER = address(0x6);

    // Task and submission IDs
    uint256 internal taskId;
    uint256 internal submissionId;

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy core infrastructure
        _deployCoreContracts();

        // Deploy and configure guards
        _deployAndConfigureGuards();

        // Deploy and configure strategies
        _deployAndConfigureStrategies();

        // Initialize test users
        _initializeTestUsers();

        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  COMPLETE WORKFLOW TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testCompleteWorkflow_TaskLifecycleWithGuardsAndStrategies() public {
        console.log("=== Testing Complete Task Lifecycle with Guards and Strategies ===");

        // Step 1: Publisher creates and publishes task (should pass global guard)
        console.log("Step 1: Publisher creating task...");
        _createAndPublishTask();

        // Step 2: Developer submits work (should pass submission guard)
        console.log("Step 2: Developer submitting work...");
        _submitWork();

        // Step 3: Reviewers review submission (should pass review guard)
        console.log("Step 3: Reviewers reviewing submission...");
        _reviewSubmission();

        // Step 4: Adoption strategy evaluates and adopts submission
        console.log("Step 4: Adoption strategy evaluation...");
        _verifyAdoptionStrategyExecution();

        // Step 5: Reward strategy distributes rewards
        console.log("Step 5: Reward distribution...");
        _verifyRewardDistribution();

        console.log("=== Complete workflow test passed ===");
    }

    function testWorkflow_AccessControlEnforcement() public {
        console.log("=== Testing Access Control Enforcement ===");

        // Create task first
        _createAndPublishTask();

        // Test 1: NEW_USER (insufficient reputation) should be blocked by submission guard
        console.log("Test 1: NEW_USER submission should be blocked...");
        vm.prank(NEW_USER);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "poor-quality-content-hash");

        // Test 2: NEW_USER should be blocked by review guard
        console.log("Test 2: NEW_USER review should be blocked...");
        _submitWork(); // Developer submits first

        vm.prank(NEW_USER);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Unqualified review");

        console.log("=== Access control enforcement test passed ===");
    }

    function testWorkflow_DifferentAdoptionScenarios() public {
        console.log("=== Testing Different Adoption Scenarios ===");

        _createAndPublishTask();
        _submitWork();

        // Scenario 1: Submission gets adopted through approval threshold
        console.log("Scenario 1: Testing approval-based adoption...");
        _performReviews(2, 1); // 2 approvals, 1 rejection -> should adopt (66.7% approval >= 60%)

        DataTypes.SubmissionInfo memory submissionInfo = submissionManager.getSubmission(submissionId);
        assertEq(uint256(submissionInfo.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        // Scenario 2: Create new task and test rejection
        console.log("Scenario 2: Testing rejection-based removal...");
        uint256 taskId2 = _createSecondTask();
        uint256 submissionId2 = _submitWorkToTask(taskId2);
        _performReviewsForSubmission(submissionId2, 1, 2); // 1 approval, 2 rejections -> should reject (66.7% rejection >= 40%)

        submissionInfo = submissionManager.getSubmission(submissionId2);
        assertEq(uint256(submissionInfo.status), uint256(DataTypes.SubmissionStatus.REMOVED));

        console.log("=== Different adoption scenarios test passed ===");
    }

    function testWorkflow_RewardAccuracyModifiers() public {
        console.log("=== Testing Reward Accuracy Modifiers ===");

        _createAndPublishTask();
        _submitWork();

        // Review and adopt
        _reviewSubmission();

        // Test accurate reviewer reward (REVIEWER1 voted approve, submission was adopted)
        uint256 accurateReward = rewardStrategy.calculateReviewerReward(
            taskId,
            REVIEWER1,
            200 ether,
            2,
            true // accurate
        );

        // Test inaccurate reviewer reward (REVIEWER2 voted reject, submission was adopted)
        uint256 inaccurateReward = rewardStrategy.calculateReviewerReward(
            taskId,
            REVIEWER2,
            200 ether,
            2,
            false // inaccurate
        );

        // Accurate reviewer should get bonus
        assertTrue(accurateReward > inaccurateReward);
        console.log("Accurate reward:", accurateReward);
        console.log("Inaccurate reward:", inaccurateReward);

        console.log("=== Reward accuracy modifiers test passed ===");
    }

    function testWorkflow_SubmissionGuardUnlocksAfterReputationBoost() public {
        _createAndPublishTask();

        vm.prank(NEW_USER);
        vm.expectRevert();
        submissionManager.submitWork(taskId, "QmNewUserInitialAttempt");

        vm.startPrank(ADMIN);
        reputationManager.updateReputation(NEW_USER, 400, "Skill upgrade");
        reputationManager.addPendingCategoryScore(NEW_USER, "development", 820);
        vm.stopPrank();
        vm.prank(NEW_USER);
        reputationManager.claimCategoryScore("development", 820);

        vm.prank(NEW_USER);
        uint256 newSubmissionId = submissionManager.submitWork(taskId, "QmNewUserQualified");
        DataTypes.SubmissionInfo memory submissionInfo = submissionManager.getSubmission(newSubmissionId);
        assertEq(submissionInfo.submitter, NEW_USER);
        assertEq(submissionInfo.taskId, taskId);
    }

    function testWorkflow_MultipleSubmissionsAdoptHighestQuality() public {
        _createAndPublishTask();

        vm.prank(DEVELOPER);
        uint256 firstSubmissionId = submissionManager.submitWork(taskId, "QmInitialDelivery");

        vm.prank(DEVELOPER2);
        uint256 secondSubmissionId = submissionManager.submitWork(taskId, "QmImprovedDelivery");

        // Reject first submission through guard-reviewed process
        _performReviewsForSubmission(firstSubmissionId, 0, 3);
        DataTypes.SubmissionInfo memory first = submissionManager.getSubmission(firstSubmissionId);
        assertEq(uint256(first.status), uint256(DataTypes.SubmissionStatus.REMOVED));

        uint256 balanceBefore = DEVELOPER2.balance;

        // Adopt the higher quality second submission
        _performReviewsForSubmission(secondSubmissionId, 3, 0);

        DataTypes.SubmissionInfo memory second = submissionManager.getSubmission(secondSubmissionId);
        assertEq(uint256(second.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        DataTypes.TaskInfo memory taskInfo = taskManager.getTask(taskId);
        assertEq(taskInfo.adoptedSubmissionId, secondSubmissionId);
        assertGt(DEVELOPER2.balance, balanceBefore);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     GUARD INTEGRATION TESTS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGuardIntegration_GlobalGuardValidation() public {
        _createAndPublishTask();

        // Test global guard with different action types
        bytes memory publishAction = abi.encode("PUBLISH_TASK");
        bytes memory submitAction = abi.encode("SUBMIT_WORK");
        bytes memory reviewAction = abi.encode("REVIEW_SUBMISSION");

        // PUBLISHER should pass all actions (normal reputation)
        (bool success, ) = globalGuard.validateUser(PUBLISHER, publishAction);
        assertTrue(success);

        (success, ) = globalGuard.validateUser(PUBLISHER, submitAction);
        assertTrue(success);

        (success, ) = globalGuard.validateUser(PUBLISHER, reviewAction);
        assertTrue(success);

        // NEW_USER should fail high-risk actions
        (success, ) = globalGuard.validateUser(NEW_USER, publishAction);
        assertFalse(success);

        (success, ) = globalGuard.validateUser(NEW_USER, submitAction);
        assertFalse(success);
    }

    function testGuardIntegration_TaskSpecificGuards() public {
        _createAndPublishTask();

        // Test submission guard
        (bool success, ) = submissionGuard.validateUser(DEVELOPER, "");
        assertTrue(success);

        (success, ) = submissionGuard.validateUser(NEW_USER, "");
        assertFalse(success); // Insufficient reputation/skills

        // Test review guard
        (success, ) = reviewGuard.validateUser(REVIEWER1, "");
        assertTrue(success);

        (success, ) = reviewGuard.validateUser(NEW_USER, "");
        assertFalse(success); // Insufficient expertise
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   STRATEGY INTEGRATION TESTS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testStrategyIntegration_AdoptionDecisions() public {
        _createAndPublishTask();
        _submitWork();

        // Test adoption strategy evaluation
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(submissionId, 3, 1, 4, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission meets approval threshold");

        // Test completion criteria
        bool shouldComplete = adoptionStrategy.shouldCompleteTask(taskId, submissionId);
        assertTrue(shouldComplete);
    }

    function testStrategyIntegration_RewardCalculations() public {
        _createAndPublishTask();

        uint256 totalReward = 1000 ether;
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            taskId,
            totalReward,
            submissionId,
            2
        );

        // Verify distribution matches configuration
        assertEq(distribution.creatorShare, 700 ether); // 70%
        assertEq(distribution.reviewerShare, 200 ether); // 20%
        assertEq(distribution.platformShare, 100 ether); // 10%
        assertEq(distribution.publisherRefund, 0); // 0%

        // Test individual reviewer rewards
        uint256 accurateReward = rewardStrategy.calculateReviewerReward(
            taskId,
            REVIEWER1,
            distribution.reviewerShare,
            2,
            true
        );

        uint256 inaccurateReward = rewardStrategy.calculateReviewerReward(
            taskId,
            REVIEWER2,
            distribution.reviewerShare,
            2,
            false
        );

        assertTrue(accurateReward > inaccurateReward);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ERROR HANDLING TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testErrorHandling_InvalidGuardConfigurations() public {
        // Test invalid global guard config
        vm.prank(ADMIN);
        vm.expectRevert();
        globalGuard.updateGuardConfig(
            abi.encode(
                GlobalGuard.GlobalGuardConfig({
                    minReputationForNormal: 10001, // Invalid: > 1000.0
                    atRiskThreshold: 200,
                    baseStakeAmount: 1 ether,
                    enforceStakeForAtRisk: true,
                    allowBlacklistedUsers: false
                })
            )
        );

        // Test invalid strategy config
        vm.prank(ADMIN);
        vm.expectRevert();
        rewardStrategy.updateRewardConfig(
            abi.encode(
                BasicRewardStrategy.BasicRewardConfig({
                    creatorPercentage: 70,
                    reviewerPercentage: 20,
                    platformPercentage: 15, // Invalid: sum > 100%
                    accuracyBonus: 20,
                    accuracyPenalty: 10,
                    minReviewerReward: 0,
                    maxReviewerReward: 0
                })
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    HELPER FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deployCoreContracts() internal {
        // Deploy MockToken for staking
        stakeToken = new MockToken();

        // Deploy HermisSBT
        hermisSBT = new HermisSBT(
            ADMIN,
            "Hermis SBT",
            "HSBT",
            "https://api.hermis.network/metadata/",
            "https://api.hermis.network/contract-metadata/"
        );

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy ReputationManager with stake token
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Deploy AllowlistManager as upgradeable proxy
        AllowlistManager allowlistManagerImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, ADMIN);
        ERC1967Proxy allowlistManagerProxy = new ERC1967Proxy(address(allowlistManagerImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistManagerProxy));

        // Deploy TaskManager
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

        // Connect HermisSBT and ReputationManager
        hermisSBT.setReputationManager(address(reputationManager));
        reputationManager.setHermisSBT(address(hermisSBT));

        // Set up Treasury authorizations
        treasury.setAuthorizedContract(address(reputationManager), true);
        treasury.setAuthorizedContract(address(taskManager), true);
    }

    function _deployAndConfigureGuards() internal {
        // Deploy GlobalGuard
        globalGuard = new GlobalGuard(ADMIN, address(reputationManager));
        globalGuard.initializeGuard(
            abi.encode(
                GlobalGuard.GlobalGuardConfig({
                    minReputationForNormal: 600,
                    atRiskThreshold: 200,
                    baseStakeAmount: 1 ether,
                    enforceStakeForAtRisk: true,
                    allowBlacklistedUsers: false
                })
            )
        );

        // Deploy SubmissionGuard for development tasks
        submissionGuard = new SubmissionGuard(ADMIN, address(reputationManager));
        submissionGuard.initializeGuard(
            abi.encode(
                SubmissionGuard.SubmissionConfig({
                    minReputationScore: 500,
                    requireCategoryExpertise: true,
                    requiredCategory: "development",
                    minCategoryScore: 700,
                    maxFailedSubmissions: 3,
                    enforceSuccessRate: true,
                    minSuccessRate: 80
                })
            )
        );

        // Deploy ReviewGuard for development tasks
        reviewGuard = new ReviewGuard(ADMIN, address(reputationManager));
        reviewGuard.initializeGuard(
            abi.encode(
                ReviewGuard.ReviewConfig({
                    minReputationScore: 600,
                    requireCategoryExpertise: true,
                    requiredCategory: "development",
                    minCategoryScore: 750,
                    minReviewCount: 5,
                    enforceAccuracyRate: true,
                    minAccuracyRate: 85
                })
            )
        );

        // Note: TaskManager doesn't have global guard configuration yet
        // taskManager.updateGlobalGuard(address(globalGuard));
    }

    function _deployAndConfigureStrategies() internal {
        // Deploy SimpleAdoptionStrategy
        adoptionStrategy = new SimpleAdoptionStrategy(ADMIN);
        adoptionStrategy.initializeStrategy(
            abi.encode(
                SimpleAdoptionStrategy.SimpleAdoptionConfig({
                    minReviewsRequired: 3,
                    approvalThreshold: 60,
                    rejectionThreshold: 40,
                    expirationTime: 7 days,
                    allowTimeBasedAdoption: false,
                    autoAdoptionTime: 0
                })
            )
        );

        // Deploy BasicRewardStrategy
        rewardStrategy = new BasicRewardStrategy(ADMIN);
        rewardStrategy.initializeRewardStrategy(
            abi.encode(
                BasicRewardStrategy.BasicRewardConfig({
                    creatorPercentage: 70,
                    reviewerPercentage: 20,
                    platformPercentage: 10,
                    accuracyBonus: 20,
                    accuracyPenalty: 10,
                    minReviewerReward: 0,
                    maxReviewerReward: 0
                })
            )
        );

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

        // Configure Treasury
        treasury.setAuthorizedContract(address(submissionManager), true);

        // Authorize SubmissionManager to interact with ReputationManager
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        // Allow guards, strategies and tokens in AllowlistManager (no prank needed, already in setUp's prank)
        allowlistManager.allowGuard(address(globalGuard));
        allowlistManager.allowGuard(address(submissionGuard));
        allowlistManager.allowGuard(address(reviewGuard));
        allowlistManager.allowStrategy(address(adoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));

        // Authorize SubmissionManager to interact with TaskManager
        taskManager.setAuthorizedContract(address(submissionManager), true);

        // Note: TaskManager doesn't have submission manager configuration
        // taskManager.setSubmissionManager(address(submissionManager));
    }

    function _initializeTestUsers() internal {
        // Initialize PUBLISHER (task creator)
        reputationManager.initializeUser(PUBLISHER);
        reputationManager.updateReputation(PUBLISHER, -200, "Experienced publisher"); // 1000 - 200 = 800

        // Initialize DEVELOPER (experienced in development)
        reputationManager.initializeUser(DEVELOPER);
        reputationManager.updateReputation(DEVELOPER, -100, "Expert developer"); // 1000 - 100 = 900
        reputationManager.addPendingCategoryScore(DEVELOPER, "development", 950);
        vm.stopPrank();
        vm.prank(DEVELOPER);
        reputationManager.claimCategoryScore("development", 950);
        vm.startPrank(ADMIN);

        // Initialize REVIEWER1 (expert reviewer)
        reputationManager.initializeUser(REVIEWER1);
        reputationManager.updateReputation(REVIEWER1, -150, "Expert reviewer 1"); // 1000 - 150 = 850
        reputationManager.addPendingCategoryScore(REVIEWER1, "development", 900);
        vm.stopPrank();
        vm.prank(REVIEWER1);
        reputationManager.claimCategoryScore("development", 900);
        vm.startPrank(ADMIN);

        // Initialize REVIEWER2 (expert reviewer)
        reputationManager.initializeUser(REVIEWER2);
        reputationManager.updateReputation(REVIEWER2, -180, "Expert reviewer 2"); // 1000 - 180 = 820
        reputationManager.addPendingCategoryScore(REVIEWER2, "development", 880);
        vm.stopPrank();
        vm.prank(REVIEWER2);
        reputationManager.claimCategoryScore("development", 880);
        vm.startPrank(ADMIN);

        // Initialize DEVELOPER2 (alternative contributor)
        reputationManager.initializeUser(DEVELOPER2);
        reputationManager.updateReputation(DEVELOPER2, -120, "Skilled developer"); // 1000 - 120 = 880
        reputationManager.addPendingCategoryScore(DEVELOPER2, "development", 920);
        vm.stopPrank();
        vm.prank(DEVELOPER2);
        reputationManager.claimCategoryScore("development", 920);
        vm.startPrank(ADMIN);

        // Initialize NEW_USER (low reputation/skills)
        reputationManager.initializeUser(NEW_USER);
        reputationManager.updateReputation(NEW_USER, -700, "New user"); // 1000 - 700 = 300
        reputationManager.addPendingCategoryScore(NEW_USER, "development", 200);
        vm.stopPrank();
        vm.prank(NEW_USER);
        reputationManager.claimCategoryScore("development", 200);
        vm.startPrank(ADMIN);
    }

    function _createAndPublishTask() internal {
        vm.deal(PUBLISHER, 10 ether);
        vm.prank(PUBLISHER);

        taskId = taskManager.createTask(
            "Build a DeFi Protocol",
            "Create a comprehensive DeFi protocol with lending and borrowing features",
            "Technical implementation with Solidity smart contracts",
            "development",
            block.timestamp + 30 days,
            5 ether,
            address(0),
            address(submissionGuard),
            address(reviewGuard),
            address(adoptionStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 5 ether}(taskId);
    }

    function _createSecondTask() internal returns (uint256) {
        vm.deal(PUBLISHER, 10 ether);
        vm.prank(PUBLISHER);

        uint256 newTaskId = taskManager.createTask(
            "Design UI/UX",
            "Create modern UI/UX for DeFi application",
            "User interface and experience design requirements",
            "design",
            block.timestamp + 20 days,
            3 ether,
            address(0),
            address(submissionGuard),
            address(reviewGuard),
            address(adoptionStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 3 ether}(newTaskId);

        return newTaskId;
    }

    function _submitWork() internal {
        vm.prank(DEVELOPER);
        submissionId = submissionManager.submitWork(taskId, "QmDeFiProtocolImplementation123456789");
    }

    function _submitWorkToTask(uint256 _taskId) internal returns (uint256) {
        vm.prank(DEVELOPER);
        return submissionManager.submitWork(_taskId, "QmUIUXDesignImplementation123456789");
    }

    function _reviewSubmission() internal {
        vm.prank(REVIEWER1);
        submissionManager.submitReview(
            submissionId,
            DataTypes.ReviewOutcome.APPROVE,
            "Excellent implementation, meets all requirements"
        );

        vm.prank(REVIEWER2);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Code quality issues found");
    }

    function _performReviews(uint256 approvals, uint256 rejections) internal {
        // This is a simplified version - in practice you'd need multiple reviewers
        for (uint256 i = 0; i < approvals + rejections; i++) {
            address reviewer = address(uint160(0x1000 + i));

            // Initialize reviewer
            vm.prank(ADMIN);
            reputationManager.initializeUser(reviewer);
            vm.prank(ADMIN);
            reputationManager.updateReputation(reviewer, -200, "Qualified reviewer"); // 1000 - 200 = 800
            vm.prank(ADMIN);
            reputationManager.addPendingCategoryScore(reviewer, "development", 800);
            vm.prank(reviewer);
            reputationManager.claimCategoryScore("development", 800);

            DataTypes.ReviewOutcome outcome = i < approvals
                ? DataTypes.ReviewOutcome.APPROVE
                : DataTypes.ReviewOutcome.REJECT;

            vm.prank(reviewer);
            submissionManager.submitReview(submissionId, outcome, "Review comment");
        }
    }

    function _performReviewsForSubmission(uint256 _submissionId, uint256 approvals, uint256 rejections) internal {
        for (uint256 i = 0; i < approvals + rejections; i++) {
            address reviewer = address(uint160(0x2000 + i));

            vm.prank(ADMIN);
            reputationManager.initializeUser(reviewer);
            vm.prank(ADMIN);
            reputationManager.updateReputation(reviewer, 800, "Qualified reviewer");
            vm.prank(ADMIN);
            reputationManager.addPendingCategoryScore(reviewer, "development", 800);
            vm.prank(reviewer);
            reputationManager.claimCategoryScore("development", 800);

            DataTypes.ReviewOutcome outcome = i < approvals
                ? DataTypes.ReviewOutcome.APPROVE
                : DataTypes.ReviewOutcome.REJECT;

            vm.prank(reviewer);
            submissionManager.submitReview(_submissionId, outcome, "Review comment");
        }
    }

    function _verifyAdoptionStrategyExecution() internal view {
        DataTypes.SubmissionInfo memory submissionInfo = submissionManager.getSubmission(submissionId);
        // Ensure the helper retrieves the expected record so the struct is actually used.
        assertEq(submissionInfo.id, submissionId, "submission lookup mismatch");
        // Verify review counters updated as expected by the earlier steps in the workflow.
        assertEq(submissionInfo.approveCount, 1, "unexpected approval tally");
        assertEq(submissionInfo.rejectCount, 1, "unexpected rejection tally");
    }

    function _verifyRewardDistribution() internal view {
        uint256 totalReward = 5 ether; // Task reward
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            taskId,
            totalReward,
            submissionId,
            2
        );

        assertTrue(distribution.creatorShare > 0);
        assertTrue(distribution.reviewerShare > 0);
        assertTrue(distribution.platformShare > 0);
    }

    // IAdoptionStrategy implementation for test
    function evaluateSubmission(
        uint256 /* submissionId */,
        uint256 approveCount,
        uint256 /* rejectCount */,
        uint256 /* totalReviews */,
        uint256 /* timeSinceSubmission */
    ) external pure override returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) {
        if (approveCount >= 2) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Test adoption");
        }
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Not enough approvals");
    }

    function shouldCompleteTask(
        uint256,
        /* taskId */
        uint256 adoptedSubmissionId
    ) external pure override returns (bool shouldComplete) {
        return adoptedSubmissionId > 0;
    }

    function getStrategyConfig() external pure override returns (bytes memory config) {
        return "";
    }

    function updateStrategyConfig(bytes calldata /* newConfig */) external override {}

    function getStrategyMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return ("TestStrategy", "1.0.0", "Test strategy for integration tests");
    }
}
