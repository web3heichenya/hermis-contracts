// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SubmissionManager} from "../../src/core/SubmissionManager.sol";
import {TaskManager} from "../../src/core/TaskManager.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {AllowlistManager} from "../../src/core/AllowlistManager.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {BasicRewardStrategy} from "../../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {IAdoptionStrategy} from "../../src/interfaces/IAdoptionStrategy.sol";

// Mock token contract
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock adoption strategy
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

    function updateStrategyConfig(bytes calldata newConfig) external pure override {
        newConfig;
    }

    function getStrategyMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return ("MockAdoptionStrategy", "1.0.0", "Mock strategy for testing");
    }
}

/**
 * @title SubmissionUpdateTest
 * @notice Tests for submission update and version increment functionality
 */
contract SubmissionUpdateTest is Test {
    SubmissionManager internal submissionManager;
    TaskManager internal taskManager;
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
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(ADMIN, 100 ether);

        treasury = new Treasury(ADMIN);
        stakeToken = new MockToken();

        hermisSBT = new HermisSBT(
            ADMIN,
            "Hermis SBT",
            "HSBT",
            "https://hermis.ai/metadata/",
            "https://hermis.ai/contract-metadata"
        );

        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        AllowlistManager allowlistManagerImpl = new AllowlistManager();
        bytes memory allowlistInitData = abi.encodeWithSelector(AllowlistManager.initialize.selector, ADMIN);
        ERC1967Proxy allowlistManagerProxy = new ERC1967Proxy(address(allowlistManagerImpl), allowlistInitData);
        allowlistManager = AllowlistManager(address(allowlistManagerProxy));

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

        rewardStrategy = new BasicRewardStrategy(ADMIN);
        bytes memory rewardConfig = abi.encode(
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
        rewardStrategy.initializeRewardStrategy(rewardConfig);

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
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        vm.prank(ADMIN);
        reputationManager.initializeUser(CHARLIE);

        mockAdoptionStrategy = new MockAdoptionStrategy();

        vm.startPrank(ADMIN);
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);
    }

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

    // Test: Basic submission update
    function testUpdate_Basic() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmInitialHash");

        vm.prank(BOB);
        uint256 newVersion = submissionManager.updateSubmission(submissionId, "QmNewHash");

        assertEq(newVersion, 2, "New version should be 2");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(submission.version, 2, "Submission version should be 2");
        assertEq(submission.contentHash, "QmNewHash", "Content hash should be updated");
    }

    // Test: Only submitter can update
    function testUpdate_OnlySubmitter() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmInitialHash");

        vm.prank(CHARLIE);
        vm.expectRevert();
        submissionManager.updateSubmission(submissionId, "QmNewHash");
    }

    // Test: Cannot update adopted submission
    function testUpdate_CannotUpdateAdopted() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmInitialHash");

        // Adopt submission via review
        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(uint256(submission.status), uint256(DataTypes.SubmissionStatus.ADOPTED));

        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.updateSubmission(submissionId, "QmNewHash");
    }

    // Test: Empty content hash
    function testUpdate_EmptyContentHash() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmInitialHash");

        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.updateSubmission(submissionId, "");
    }

    // Test: Multiple sequential updates
    function testUpdate_MultipleSequential() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmInitialHash");

        vm.startPrank(BOB);

        uint256 version2 = submissionManager.updateSubmission(submissionId, "QmHash2");
        assertEq(version2, 2, "Second version should be 2");

        uint256 version3 = submissionManager.updateSubmission(submissionId, "QmHash3");
        assertEq(version3, 3, "Third version should be 3");

        uint256 version4 = submissionManager.updateSubmission(submissionId, "QmHash4");
        assertEq(version4, 4, "Fourth version should be 4");

        DataTypes.SubmissionInfo memory submission = submissionManager.getSubmission(submissionId);
        assertEq(submission.version, 4, "Final version should be 4");
        assertEq(submission.contentHash, "QmHash4", "Final content hash should be QmHash4");

        vm.stopPrank();
    }

    // Test: Version increments correctly
    function testUpdate_VersionIncrement() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmV1");

        DataTypes.SubmissionInfo memory submission1 = submissionManager.getSubmission(submissionId);
        assertEq(submission1.version, 1);

        vm.prank(BOB);
        submissionManager.updateSubmission(submissionId, "QmV2");

        DataTypes.SubmissionInfo memory submission2 = submissionManager.getSubmission(submissionId);
        assertEq(submission2.version, 2);
    }
}
