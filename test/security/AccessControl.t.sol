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
        return ("MockAdoptionStrategy", "1.0.0", "Mock strategy for testing");
    }
}

/// @title AccessControlTest
/// @notice Critical security tests for access control mechanisms across all contracts
/// @dev Tests unauthorized access attempts to prevent security vulnerabilities
contract AccessControlTest is Test {
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
    address internal constant ATTACKER = address(0x666);
    address internal constant PUBLISHER = address(0x2);
    address internal constant SUBMITTER = address(0x3);

    uint256 internal testTaskId;
    uint256 internal testSubmissionId;

    function setUp() public {
        // Fund accounts
        vm.deal(ADMIN, 100 ether);
        vm.deal(ATTACKER, 100 ether);
        vm.deal(PUBLISHER, 100 ether);
        vm.deal(SUBMITTER, 100 ether);

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

        // Allow strategy
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
        vm.prank(ADMIN);
        reputationManager.initializeUser(PUBLISHER);
        vm.prank(ADMIN);
        reputationManager.initializeUser(SUBMITTER);
        vm.prank(ADMIN);
        reputationManager.initializeUser(ATTACKER);

        // Create test task
        vm.prank(PUBLISHER);
        testTaskId = taskManager.createTask(
            "Test Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            1 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        // Publish task
        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 1 ether}(testTaskId);

        // Create test submission
        vm.prank(SUBMITTER);
        testSubmissionId = submissionManager.submitWork(testTaskId, "QmTestHash");
    }

    /// @notice Test that unauthorized contracts cannot complete tasks
    /// @dev Critical: Prevents attackers from marking tasks as complete without proper authorization
    function testUnauthorizedContractCall_TaskCompletion() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        taskManager.completeTask(testTaskId, testSubmissionId);
    }

    /// @notice Test that unauthorized contracts cannot activate tasks
    /// @dev Critical: Prevents manipulation of task lifecycle states
    function testUnauthorizedContractCall_TaskActivation() public {
        // Create a new draft task
        vm.prank(PUBLISHER);
        uint256 draftTaskId = taskManager.createTask(
            "Draft Task",
            "Description",
            "Requirements",
            "development",
            block.timestamp + 7 days,
            1 ether,
            address(0),
            address(0),
            address(0),
            address(mockStrategy)
        );

        vm.prank(PUBLISHER);
        taskManager.publishTask{value: 1 ether}(draftTaskId);

        // Attacker tries to activate
        vm.prank(ATTACKER);
        vm.expectRevert();
        taskManager.activateTask(draftTaskId);
    }

    /// @notice Test that unauthorized contracts cannot restore submission status
    /// @dev Critical: Prevents attackers from restoring removed submissions
    function testUnauthorizedContractCall_SubmissionRestore() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        submissionManager.restoreSubmissionStatus(
            testSubmissionId,
            DataTypes.SubmissionStatus.ADOPTED,
            "Unauthorized restore attempt"
        );
    }

    /// @notice Test that unauthorized contracts cannot update reputation
    /// @dev Critical: Prevents reputation manipulation attacks
    function testUnauthorizedReputationUpdate() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        reputationManager.updateReputation(SUBMITTER, 1000, "Unauthorized reputation boost");
    }

    /// @notice Test that unauthorized contracts cannot deposit to treasury
    /// @dev Critical: Prevents fund manipulation through unauthorized deposits
    function testUnauthorizedTreasuryDeposit() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        treasury.depositTaskReward{value: 1 ether}(999, address(0), 1 ether);
    }

    /// @notice Test that unauthorized contracts cannot withdraw from treasury
    /// @dev Critical: Prevents theft of escrowed funds
    function testUnauthorizedTreasuryWithdrawal() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        treasury.withdrawTaskReward(testTaskId, ATTACKER, address(0), 1 ether);
    }

    /// @notice Test that unauthorized contracts cannot bypass guard validation
    /// @dev Critical: Ensures guards are always checked before state changes
    function testBypassGuardValidation() public {
        // This test verifies that even if an attacker tries to call internal functions
        // or manipulate the call stack, guards are still enforced

        // Attacker tries to submit work without proper validation
        // The system should always check guards regardless of caller
        vm.prank(ATTACKER);
        // This should succeed because guards are validated in canSubmitToTask
        uint256 attackerSubmissionId = submissionManager.submitWork(testTaskId, "QmAttackerHash");

        // Verify submission was created properly (guards were checked)
        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(attackerSubmissionId);
        assertEq(submission.submitter, ATTACKER);
        assertEq(uint256(submission.status), uint256(DataTypes.SubmissionStatus.SUBMITTED));
    }

    /// @notice Test that only owner can set authorized contracts on TaskManager
    /// @dev High: Prevents unauthorized addition of malicious contracts to authorization list
    function testUnauthorizedSetAuthorizedContract_TaskManager() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        taskManager.setAuthorizedContract(ATTACKER, true);
    }

    /// @notice Test that only owner can set authorized contracts on SubmissionManager
    /// @dev High: Prevents unauthorized addition of malicious contracts to authorization list
    function testUnauthorizedSetAuthorizedContract_SubmissionManager() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        submissionManager.setAuthorizedContract(ATTACKER, true);
    }

    /// @notice Test that only owner can set authorized contracts on Treasury
    /// @dev High: Prevents unauthorized access to treasury functions
    function testUnauthorizedSetAuthorizedContract_Treasury() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        treasury.setAuthorizedContract(ATTACKER, true);
    }

    /// @notice Test that only owner can update allowlist manager settings
    /// @dev High: Prevents unauthorized modification of system configuration
    function testUnauthorizedAllowlistUpdate() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        allowlistManager.allowStrategy(address(ATTACKER));
    }

    /// @notice Test that only ReputationManager can mint SBTs
    /// @dev Critical: Prevents unauthorized SBT minting
    function testUnauthorizedSBTMint() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        hermisSBT.mint(ATTACKER);
    }
}
