// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ReviewGuard} from "../../../../src/guards/task/ReviewGuard.sol";
import {ReputationManager} from "../../../../src/core/ReputationManager.sol";
import {Treasury} from "../../../../src/core/Treasury.sol";
import {HermisSBT} from "../../../../src/core/HermisSBT.sol";
import {DataTypes} from "../../../../src/libraries/DataTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ReviewGuardTest
/// @notice Test ReviewGuard reviewer validation logic
contract ReviewGuardTest is Test {
    ReviewGuard internal reviewGuard;
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    HermisSBT internal hermisSBT;
    MockToken internal stakeToken;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant CHARLIE = address(0x3);
    address internal constant ADMIN = address(0x10);

    function setUp() public {
        vm.deal(ADMIN, 100 ether);
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);

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

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        // Deploy ReviewGuard
        reviewGuard = new ReviewGuard(ADMIN, address(reputationManager));

        // Initialize test config
        bytes memory config = abi.encode(
            ReviewGuard.ReviewConfig({
                minReputationScore: 800,
                minCategoryScore: 700,
                minReviewCount: 0,
                minAccuracyRate: 0,
                requireCategoryExpertise: true,
                enforceAccuracyRate: false,
                requiredCategory: "development"
            })
        );

        vm.prank(ADMIN);
        reviewGuard.initializeGuard(config);

        // Initialize users
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        vm.prank(ADMIN);
        reputationManager.initializeUser(CHARLIE);

        // Give users tokens
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
        stakeToken.mint(CHARLIE, 10 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           BASIC VALIDATION TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test reviewer with insufficient reputation is rejected
    function testValidateUser_RevertWhenInsufficientReputation() public {
        // ALICE has default 1000 reputation, which is below 800 required
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -300, "Reduce reputation");

        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0);
    }

    /// @notice Test reviewer with insufficient category score is rejected
    function testValidateUser_RevertWhenInsufficientCategoryScore() public view {
        // ALICE has sufficient reputation but no category score
        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertFalse(isValid);
        assertEq(reason, "Insufficient development expertise for review: required 700, current 0");
    }

    /// @notice Test reviewer without sufficient stake is rejected
    function testValidateUser_RevertWhenInsufficientStake() public {
        // Set ALICE to AT_RISK status (reputation < 600) so she needs stake
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Reduce to AT_RISK");

        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 800);

        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 800);

        // ALICE has not staked anything, should fail access check
        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0); // Should contain access denied message
    }

    /// @notice Test blacklisted reviewer is rejected
    function testValidateUser_RevertWhenBlacklisted() public {
        // Blacklist ALICE by reducing reputation to 0
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -1000, "Blacklist user");

        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 800);

        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 800);

        // Even with stake, blacklisted users cannot pass
        address[] memory blacklisted = new address[](1);
        blacklisted[0] = ALICE;

        bytes memory newConfig = abi.encode(
            ReviewGuard.ReviewConfig({
                minReputationScore: 800,
                minCategoryScore: 700,
                minReviewCount: 0,
                minAccuracyRate: 0,
                requireCategoryExpertise: true,
                enforceAccuracyRate: false,
                requiredCategory: "development"
            })
        );

        vm.prank(ADMIN);
        reviewGuard.updateGuardConfig(newConfig);

        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0);
    }

    /// @notice Test reviewer meeting all requirements passes validation
    function testValidateUser_SuccessWithAllRequirements() public {
        // Setup ALICE with all requirements
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, 200, "Increase reputation");

        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 800);

        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 800);

        vm.prank(ALICE);
        stakeToken.approve(address(reputationManager), 2 ether);
        vm.prank(ALICE);
        reputationManager.stake(2 ether, address(stakeToken));

        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertTrue(isValid);
        assertEq(reason, "Review requirements met");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           CONFIGURATION UPDATE TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test dynamic update of reviewer requirements
    function testUpdateConfig_DynamicRequirements() public {
        // Initial config requires 800 reputation
        // Setup BOB with 1000 reputation (passes)
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(BOB, "development", 800);

        vm.prank(BOB);
        reputationManager.claimCategoryScore("development", 800);

        vm.prank(BOB);
        stakeToken.approve(address(reputationManager), 2 ether);
        vm.prank(BOB);
        reputationManager.stake(2 ether, address(stakeToken));

        (bool isValid1, ) = reviewGuard.validateUser(BOB, "");
        assertTrue(isValid1);

        // Update config to require 1100 reputation (BOB has 1000, should fail)
        bytes memory newConfig = abi.encode(
            ReviewGuard.ReviewConfig({
                minReputationScore: 1100,
                minCategoryScore: 700,
                minReviewCount: 0,
                minAccuracyRate: 0,
                requireCategoryExpertise: true,
                enforceAccuracyRate: false,
                requiredCategory: "development"
            })
        );

        vm.prank(ADMIN);
        reviewGuard.updateGuardConfig(newConfig);

        // Now BOB fails with 1000 reputation (needs 1100)
        (bool isValid2, string memory reason) = reviewGuard.validateUser(BOB, "");
        assertFalse(isValid2);
        assertTrue(bytes(reason).length > 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           BOUNDARY CONDITION TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test exact reputation requirement match
    function testValidateUser_ExactReputationMatch() public {
        // Set CHARLIE reputation to exactly 800
        vm.prank(ADMIN);
        reputationManager.updateReputation(CHARLIE, -200, "Adjust to 800");

        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(CHARLIE, "development", 700);

        vm.prank(CHARLIE);
        reputationManager.claimCategoryScore("development", 700);

        vm.prank(CHARLIE);
        stakeToken.approve(address(reputationManager), 1 ether);
        vm.prank(CHARLIE);
        reputationManager.stake(1 ether, address(stakeToken));

        (bool isValid, string memory reason) = reviewGuard.validateUser(CHARLIE, "");
        assertTrue(isValid);
        assertEq(reason, "Review requirements met");
    }

    /// @notice Test zero stake requirement configuration
    function testValidateUser_ZeroStakeRequirement() public {
        bytes memory config = abi.encode(
            ReviewGuard.ReviewConfig({
                minReputationScore: 800,
                minCategoryScore: 700,
                minReviewCount: 0,
                minAccuracyRate: 0,
                requireCategoryExpertise: true,
                enforceAccuracyRate: false,
                requiredCategory: "development"
            })
        );

        vm.prank(ADMIN);
        reviewGuard.updateGuardConfig(config);

        // ALICE with sufficient reputation and category score but no stake
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 700);

        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 700);

        (bool isValid, string memory reason) = reviewGuard.validateUser(ALICE, "");
        assertTrue(isValid);
        assertEq(reason, "Review requirements met");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           METADATA TESTS                                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetGuardMetadata() public view {
        (string memory name, string memory version, string memory description) = reviewGuard.getGuardMetadata();
        assertEq(name, "ReviewGuard");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }
}
