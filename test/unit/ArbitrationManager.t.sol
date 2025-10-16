// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ArbitrationManager} from "../../src/core/ArbitrationManager.sol";
import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
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

contract ArbitrationManagerTest is Test {
    ArbitrationManager internal arbitrationManager;
    SubmissionManager internal submissionManager;
    TaskManager internal taskManager;
    Treasury internal treasury;
    ReputationManager internal reputationManager;
    AllowlistManager internal allowlistManager;
    HermisSBT internal hermisSBT;
    BasicRewardStrategy internal rewardStrategy;
    MockToken internal stakeToken;
    MockToken internal feeToken;
    MockAdoptionStrategy internal mockAdoptionStrategy;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant CHARLIE = address(0x3);
    address internal constant ADMIN = address(0x10);

    uint256 internal constant DEFAULT_TASK_REWARD = 1 ether;
    uint256 internal constant DEFAULT_DEADLINE_OFFSET = 7 days;
    uint256 internal constant DEFAULT_ARBITRATION_FEE = 100 ether;

    function setUp() public {
        // Fund test accounts
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(ADMIN, 100 ether);

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy mock tokens
        stakeToken = new MockToken();
        feeToken = new MockToken();

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

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(taskManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(arbitrationManager), true);

        // Authorize contracts to interact with each other
        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(arbitrationManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(arbitrationManager), true);

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

        // Allow mock contracts in AllowlistManager
        vm.startPrank(ADMIN);
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        // Give users some tokens
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);

        feeToken.mint(ALICE, 1000 ether);
        feeToken.mint(BOB, 1000 ether);
        feeToken.mint(CHARLIE, 1000 ether);
    }

    function testRequestUserArbitration_Success() public {
        // Reduce BOB's reputation below threshold (600) for arbitration eligibility
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        // BOB is now AT_RISK and needs to stake to access the system
        stakeToken.mint(BOB, 1000 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        // Give BOB fee tokens and approve
        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        uint256 arbitrationId = arbitrationManager.requestUserArbitration(
            BOB,
            "Reputation penalty was unfair",
            DEFAULT_ARBITRATION_FEE
        );

        // Verify arbitration was created
        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(request.requester, BOB);
        assertEq(uint256(request.arbitrationType), uint256(DataTypes.ArbitrationType.USER_REPUTATION));
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.PENDING));
        assertEq(address(uint160(request.targetId)), BOB);
        assertEq(request.evidence, "Reputation penalty was unfair");
    }

    function testRequestUserArbitration_RevertWhenHighReputation() public {
        // ALICE has normal reputation, should not be able to request arbitration
        vm.prank(ALICE);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(ALICE);
        vm.expectRevert();
        arbitrationManager.requestUserArbitration(ALICE, "Test request", DEFAULT_ARBITRATION_FEE);
    }

    function testRequestSubmissionArbitration_Success() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmBobsWork123");

        // Give BOB fee tokens and approve
        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        uint256 arbitrationId = arbitrationManager.requestSubmissionArbitration(
            submissionId,
            "Submission was unfairly rejected",
            DEFAULT_ARBITRATION_FEE
        );

        // Verify arbitration was created
        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(request.requester, BOB);
        assertEq(uint256(request.arbitrationType), uint256(DataTypes.ArbitrationType.SUBMISSION_STATUS));
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.PENDING));
        assertEq(request.targetId, submissionId);
        assertEq(request.evidence, "Submission was unfairly rejected");
    }

    function testResolveArbitration_ApproveUserReputation() public {
        // Reduce BOB's reputation below threshold (600) for arbitration eligibility
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        // BOB is now AT_RISK and needs to stake to access the system
        stakeToken.mint(BOB, 1000 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        // Create arbitration request
        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        uint256 arbitrationId = arbitrationManager.requestUserArbitration(
            BOB,
            "Reputation penalty was unfair",
            DEFAULT_ARBITRATION_FEE
        );

        // Admin resolves arbitration favorably
        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(
            arbitrationId,
            DataTypes.ArbitrationStatus.APPROVED,
            "Penalty was indeed excessive"
        );

        // Verify resolution
        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.APPROVED));
        // Resolution reason is emitted in event, not stored in struct
    }

    function testResolveArbitration_RejectUserReputation() public {
        // Reduce BOB's reputation below threshold (600) for arbitration eligibility
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        // BOB is now AT_RISK and needs to stake to access the system
        stakeToken.mint(BOB, 1000 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        // Create arbitration request
        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        uint256 arbitrationId = arbitrationManager.requestUserArbitration(
            BOB,
            "Reputation penalty was unfair",
            DEFAULT_ARBITRATION_FEE
        );

        // Admin resolves arbitration unfavorably
        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(
            arbitrationId,
            DataTypes.ArbitrationStatus.REJECTED,
            "Penalty was justified"
        );

        // Verify resolution
        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbitrationId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.REJECTED));
        // Resolution reason is emitted in event, not stored in struct
    }

    function testCanRequestArbitration_UserReputation() public {
        // Normal user should not be able to request arbitration
        vm.prank(ALICE);
        (bool canRequest, string memory reason) = arbitrationManager.canRequestArbitration(
            DataTypes.ArbitrationType.USER_REPUTATION,
            uint256(uint160(ALICE))
        );
        assertFalse(canRequest);
        assertTrue(bytes(reason).length > 0);

        // Reduce ALICE's reputation below the threshold (600) for arbitration eligibility
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Test penalty");

        // ALICE is now AT_RISK and needs to stake to access the system
        stakeToken.mint(ALICE, 1000 ether);
        vm.prank(ALICE);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(ALICE);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        // Now ALICE should be able to request arbitration
        vm.prank(ALICE);
        (canRequest, reason) = arbitrationManager.canRequestArbitration(
            DataTypes.ArbitrationType.USER_REPUTATION,
            uint256(uint160(ALICE))
        );
        assertTrue(canRequest);
    }

    function testGetPendingArbitrations() public {
        // Create multiple arbitration requests
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        // BOB is now AT_RISK and needs to stake to access the system
        stakeToken.mint(BOB, 1000 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE * 2);

        vm.prank(BOB);
        arbitrationManager.requestUserArbitration(BOB, "First request", DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        arbitrationManager.requestUserArbitration(BOB, "Second request", DEFAULT_ARBITRATION_FEE);

        uint256[] memory pending = arbitrationManager.getPendingArbitrations(0, 10);
        assertEq(pending.length, 2);
    }

    function testGetArbitrationsByUser() public {
        // Create arbitration request
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        // BOB is now AT_RISK and needs to stake to access the system
        stakeToken.mint(BOB, 1000 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken)); // Required stake for reputation 500

        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        arbitrationManager.requestUserArbitration(BOB, "Test request", DEFAULT_ARBITRATION_FEE);

        uint256[] memory userArbitrations = arbitrationManager.getArbitrationsByRequester(BOB, 0, 10);
        assertEq(userArbitrations.length, 1);
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
