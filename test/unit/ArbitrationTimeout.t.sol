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

/// @title ArbitrationAdvancedTest
/// @notice Advanced arbitration workflow tests
/// @dev Tests arbitration request and resolution mechanisms
contract ArbitrationAdvancedTest is Test {
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
    uint256 internal constant DEFAULT_ARBITRATION_FEE = 1 ether;

    function setUp() public {
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(ADMIN, 100 ether);

        treasury = new Treasury(ADMIN);
        stakeToken = new MockToken();
        feeToken = new MockToken();

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

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        taskManager.setAuthorizedContract(address(arbitrationManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(submissionManager), true);

        vm.prank(ADMIN);
        reputationManager.setAuthorizedContract(address(arbitrationManager), true);

        vm.prank(ADMIN);
        submissionManager.setAuthorizedContract(address(arbitrationManager), true);

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

        stakeToken.mint(ALICE, 100 ether);
        stakeToken.mint(BOB, 100 ether);
        stakeToken.mint(CHARLIE, 100 ether);

        feeToken.mint(ALICE, 100 ether);
        feeToken.mint(BOB, 100 ether);
        feeToken.mint(CHARLIE, 100 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           ARBITRATION FEE TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test setting arbitration fee
    function testArbitration_SetFee() public {
        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(DEFAULT_ARBITRATION_FEE);

        assertEq(arbitrationManager.getArbitrationFee(), DEFAULT_ARBITRATION_FEE);
    }

    /// @notice Test only owner can set fee
    function testArbitration_OnlyOwnerCanSetFee() public {
        vm.prank(ALICE);
        vm.expectRevert();
        arbitrationManager.setArbitrationFee(2 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           ARBITRATION REQUEST TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test user can request arbitration with sufficient fee
    function testArbitration_UserRequestWithFee() public {
        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(DEFAULT_ARBITRATION_FEE);

        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -500, "Test penalty");

        stakeToken.mint(BOB, 200 ether);
        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 200 ether);
        vm.prank(BOB);
        reputationManager.stake(200 ether, address(stakeToken));

        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        uint256 arbId = arbitrationManager.requestUserArbitration(BOB, "Disputing penalty", DEFAULT_ARBITRATION_FEE);

        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbId);
        assertEq(request.requester, BOB);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.PENDING));
    }

    /// @notice Test arbitration requires sufficient reputation
    function testArbitration_RequiresSufficientReputation() public {
        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(DEFAULT_ARBITRATION_FEE);

        // Reduce BOB's reputation too low
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -800, "Severe penalty");

        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        vm.expectRevert();
        arbitrationManager.requestUserArbitration(BOB, "Disputing penalty", DEFAULT_ARBITRATION_FEE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           ARBITRATION RESOLUTION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test admin can resolve arbitration
    function testArbitration_AdminResolve() public {
        uint256 arbId = _createUserArbitration(BOB);

        vm.prank(ADMIN);
        arbitrationManager.resolveArbitration(arbId, DataTypes.ArbitrationStatus.APPROVED, "Arbitration approved");

        DataTypes.ArbitrationRequest memory request = arbitrationManager.getArbitration(arbId);
        assertEq(uint256(request.status), uint256(DataTypes.ArbitrationStatus.APPROVED));
    }

    /// @notice Test non-admin cannot resolve
    function testArbitration_OnlyAdminCanResolve() public {
        uint256 arbId = _createUserArbitration(BOB);

        vm.prank(ALICE);
        vm.expectRevert();
        arbitrationManager.resolveArbitration(arbId, DataTypes.ArbitrationStatus.APPROVED, "Unauthorized");
    }

    /// @notice Test getting pending arbitrations
    function testArbitration_GetPending() public {
        _createUserArbitration(BOB);
        _createUserArbitration(CHARLIE);

        uint256[] memory pending = arbitrationManager.getPendingArbitrations(0, 10);
        assertEq(pending.length, 2);
    }

    /// @notice Test getting arbitrations by requester
    function testArbitration_GetByRequester() public {
        // First arbitration
        _createUserArbitration(BOB);

        // Second arbitration - reuse existing low reputation, just request again
        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(BOB);
        arbitrationManager.requestUserArbitration(BOB, "Second dispute", DEFAULT_ARBITRATION_FEE);

        uint256[] memory bobArbitrations = arbitrationManager.getArbitrationsByRequester(BOB, 0, 10);
        assertEq(bobArbitrations.length, 2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           HELPER FUNCTIONS                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _createUserArbitration(address user) internal returns (uint256) {
        // Reduce user reputation below 600 to allow arbitration, but keep above 500 for requester
        vm.prank(ADMIN);
        reputationManager.updateReputation(user, -500, "Penalty to enable arbitration");

        // Provide stake for AT_RISK user (reputation 500 is AT_RISK)
        stakeToken.mint(user, 200 ether);
        vm.prank(user);
        stakeToken.approve(address(reputationManager), 200 ether);
        vm.prank(user);
        reputationManager.stake(200 ether, address(stakeToken));

        vm.prank(ADMIN);
        arbitrationManager.setArbitrationFee(DEFAULT_ARBITRATION_FEE);

        vm.prank(user);
        feeToken.approve(address(arbitrationManager), DEFAULT_ARBITRATION_FEE);

        vm.prank(user);
        return arbitrationManager.requestUserArbitration(user, "Test dispute", DEFAULT_ARBITRATION_FEE);
    }
}
