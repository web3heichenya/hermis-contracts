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
        return ("MockAdoptionStrategy", "1.0.0", "Mock strategy");
    }
}

/// @title ReviewAccuracyTest
/// @notice Test review accuracy and reviewer reputation impacts
contract ReviewAccuracyTest is Test {
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
    address internal constant DAVID = address(0x4);
    address internal constant EVE = address(0x5);
    address internal constant ADMIN = address(0x10);

    uint256 internal constant DEFAULT_TASK_REWARD = 1 ether;
    uint256 internal constant DEFAULT_DEADLINE_OFFSET = 7 days;

    function setUp() public {
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(DAVID, 100 ether);
        vm.deal(EVE, 100 ether);
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
        vm.prank(ADMIN);
        reputationManager.initializeUser(DAVID);
        vm.prank(ADMIN);
        reputationManager.initializeUser(EVE);

        mockAdoptionStrategy = new MockAdoptionStrategy();

        vm.startPrank(ADMIN);
        allowlistManager.allowStrategy(address(mockAdoptionStrategy));
        allowlistManager.allowToken(address(stakeToken));
        vm.stopPrank();

        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);
        stakeToken.mint(DAVID, 10 ether);
        stakeToken.mint(EVE, 10 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           REVIEW SUBMISSION TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test successful review submission
    function testReview_SuccessfulSubmission() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        uint256 reviewId = submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good work");

        DataTypes.ReviewInfo memory review = submissionManager.getReview(reviewId);
        assertEq(review.reviewer, CHARLIE);
        assertEq(uint256(review.outcome), uint256(DataTypes.ReviewOutcome.APPROVE));
    }

    /// @notice Test cannot review own submission
    function testReview_CannotReviewOwnSubmission() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(BOB);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Self review");
    }

    /// @notice Test cannot review twice
    function testReview_CannotReviewTwice() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "First review");

        vm.prank(CHARLIE);
        vm.expectRevert();
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Second review");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           REVIEW COUNTING TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test approve count increments
    function testReview_ApproveCountIncrements() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        DataTypes.SubmissionInfo memory sub1 = submissionManager.getSubmission(submissionId);
        assertEq(sub1.approveCount, 0);

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Approve");

        DataTypes.SubmissionInfo memory sub2 = submissionManager.getSubmission(submissionId);
        assertEq(sub2.approveCount, 1);
    }

    /// @notice Test reject count increments
    function testReview_RejectCountIncrements() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Reject");

        DataTypes.SubmissionInfo memory sub = submissionManager.getSubmission(submissionId);
        assertEq(sub.rejectCount, 1);
    }

    /// @notice Test multiple reviews counting
    function testReview_MultipleReviewsCounting() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(DAVID);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(EVE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Bad");

        DataTypes.SubmissionInfo memory sub = submissionManager.getSubmission(submissionId);
        assertEq(sub.approveCount, 2);
        assertEq(sub.rejectCount, 1);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           REVIEW ADOPTION TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test submission adopted with majority approval
    function testReview_AdoptedWithMajorityApproval() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(DAVID);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(EVE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        DataTypes.SubmissionInfo memory sub = submissionManager.getSubmission(submissionId);
        assertEq(uint256(sub.status), uint256(DataTypes.SubmissionStatus.ADOPTED));
    }

    /// @notice Test submission removed with majority rejection
    function testReview_RemovedWithMajorityRejection() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Bad");

        vm.prank(DAVID);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Bad");

        vm.prank(EVE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.REJECT, "Bad");

        DataTypes.SubmissionInfo memory sub = submissionManager.getSubmission(submissionId);
        assertEq(uint256(sub.status), uint256(DataTypes.SubmissionStatus.REMOVED));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           REVIEW RETRIEVAL TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test get submission reviews
    function testReview_GetSubmissionReviews() public {
        uint256 taskId = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 submissionId = submissionManager.submitWork(taskId, "QmWork");

        vm.prank(CHARLIE);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(DAVID);
        submissionManager.submitReview(submissionId, DataTypes.ReviewOutcome.APPROVE, "Good");

        uint256[] memory reviews = submissionManager.getSubmissionReviews(submissionId, 0, 10);
        assertEq(reviews.length, 2);
    }

    /// @notice Test get reviewer reviews
    function testReview_GetReviewerReviews() public {
        uint256 taskId1 = _createAndPublishTask(ALICE);
        uint256 taskId2 = _createAndPublishTask(ALICE);

        vm.prank(BOB);
        uint256 sub1 = submissionManager.submitWork(taskId1, "QmWork1");

        vm.prank(BOB);
        uint256 sub2 = submissionManager.submitWork(taskId2, "QmWork2");

        vm.prank(CHARLIE);
        submissionManager.submitReview(sub1, DataTypes.ReviewOutcome.APPROVE, "Good");

        vm.prank(CHARLIE);
        submissionManager.submitReview(sub2, DataTypes.ReviewOutcome.APPROVE, "Good");

        uint256[] memory charlieReviews = submissionManager.getReviewerReviews(CHARLIE, 0, 10);
        assertEq(charlieReviews.length, 2);
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

    function _getReputation(address user) internal view returns (uint256) {
        (uint256 reputation, , , , ) = reputationManager.getUserReputation(user);
        return reputation;
    }
}
