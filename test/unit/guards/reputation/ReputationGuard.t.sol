// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ReputationGuard} from "../../../../src/guards/reputation/ReputationGuard.sol";
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

/// @title ReputationGuardTest
/// @notice Comprehensive tests for ReputationGuard reputation-based access control
contract ReputationGuardTest is Test {
    ReputationGuard internal reputationGuard;
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    HermisSBT internal hermisSBT;
    MockToken internal stakeToken;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant CHARLIE = address(0x3);
    address internal constant DAVID = address(0x4);
    address internal constant ADMIN = address(0x10);

    function setUp() public {
        vm.deal(ADMIN, 100 ether);
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);
        vm.deal(DAVID, 100 ether);

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

        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        reputationGuard = new ReputationGuard(ADMIN, address(reputationManager));

        bytes memory config = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 500,
                requireCategoryScore: false,
                requiredCategory: "",
                minCategoryScore: 0
            })
        );

        vm.prank(ADMIN);
        reputationGuard.initializeGuard(config);

        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        vm.prank(ADMIN);
        reputationManager.initializeUser(CHARLIE);

        vm.prank(ADMIN);
        reputationManager.initializeUser(DAVID);

        stakeToken.mint(ALICE, 10000 ether);
        stakeToken.mint(BOB, 10000 ether);
        stakeToken.mint(CHARLIE, 10000 ether);
        stakeToken.mint(DAVID, 10000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           BASIC REPUTATION VALIDATION TESTS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test user with normal reputation passes validation
    function testValidateUser_NormalReputationPasses() public view {
        // ALICE has default 1000 reputation (10x precision)
        (bool isValid, string memory reason) = reputationGuard.validateUser(ALICE, "");
        assertTrue(isValid);
        assertEq(reason, "Reputation requirements met");
    }

    /// @notice Test user with insufficient reputation fails
    function testValidateUser_InsufficientReputation() public {
        // Reduce BOB's reputation below minimum (500)
        vm.prank(ADMIN);
        reputationManager.updateReputation(BOB, -600, "Penalty");

        (bool isValid, string memory reason) = reputationGuard.validateUser(BOB, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0);
    }

    /// @notice Test exact minimum reputation passes
    function testValidateUser_ExactMinimumReputation() public {
        // Set CHARLIE to exactly 500 reputation (AT_RISK status)
        vm.prank(ADMIN);
        reputationManager.updateReputation(CHARLIE, -500, "Adjust to minimum");

        // AT_RISK users need stake to pass validation
        // Required stake = 1000 * (600 - 500) / (600 - 100) = 200 ether
        vm.prank(CHARLIE);
        stakeToken.approve(address(reputationManager), 200 ether);
        vm.prank(CHARLIE);
        reputationManager.stake(200 ether, address(stakeToken));

        (bool isValid, string memory reason) = reputationGuard.validateUser(CHARLIE, "");
        assertTrue(isValid);
        assertEq(reason, "Reputation requirements met");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           BLACKLISTED USER TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test blacklisted user cannot pass validation
    function testValidateUser_BlacklistedUserBlocked() public {
        // Reduce CHARLIE to BLACKLISTED status (reputation = 0)
        vm.prank(ADMIN);
        reputationManager.updateReputation(CHARLIE, -1000, "Blacklist user");

        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(CHARLIE);
        assertEq(reputation, 0);
        assertEq(uint256(status), uint256(DataTypes.UserStatus.BLACKLISTED));

        (bool isValid, string memory reason) = reputationGuard.validateUser(CHARLIE, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           CATEGORY SCORE VALIDATION TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test category score requirement when enabled
    function testValidateUser_CategoryScoreRequired() public {
        // Enable category score requirement
        bytes memory newConfig = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 500,
                requireCategoryScore: true,
                requiredCategory: "development",
                minCategoryScore: 100
            })
        );

        vm.prank(ADMIN);
        reputationGuard.updateGuardConfig(newConfig);

        // ALICE has sufficient overall reputation but no category score
        (bool isValid, string memory reason) = reputationGuard.validateUser(ALICE, "");
        assertFalse(isValid);
        assertTrue(bytes(reason).length > 0);
    }

    /// @notice Test user passes with sufficient category score
    function testValidateUser_SufficientCategoryScore() public {
        // Add pending category score to ALICE
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 150);

        // Claim the category score
        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 150);

        // Enable category score requirement
        bytes memory newConfig = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 500,
                requireCategoryScore: true,
                requiredCategory: "development",
                minCategoryScore: 100
            })
        );

        vm.prank(ADMIN);
        reputationGuard.updateGuardConfig(newConfig);

        (bool isValid, string memory reason) = reputationGuard.validateUser(ALICE, "");
        assertTrue(isValid);
        assertEq(reason, "Reputation requirements met");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           CONFIGURATION UPDATE TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test updating minimum reputation requirement
    function testUpdateConfig_MinReputationChange() public {
        // ALICE has 1000 reputation, passes with min 500
        (bool isValid1, ) = reputationGuard.validateUser(ALICE, "");
        assertTrue(isValid1);

        // Increase minimum to 1100
        bytes memory newConfig = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 1100,
                requireCategoryScore: false,
                requiredCategory: "",
                minCategoryScore: 0
            })
        );

        vm.prank(ADMIN);
        reputationGuard.updateGuardConfig(newConfig);

        // Now ALICE fails
        (bool isValid2, ) = reputationGuard.validateUser(ALICE, "");
        assertFalse(isValid2);
    }

    /// @notice Test enabling category requirement
    function testUpdateConfig_EnableCategoryRequirement() public {
        // Initially passes without category requirement
        (bool isValid1, ) = reputationGuard.validateUser(BOB, "");
        assertTrue(isValid1);

        // Enable category requirement
        bytes memory newConfig = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 500,
                requireCategoryScore: true,
                requiredCategory: "design",
                minCategoryScore: 50
            })
        );

        vm.prank(ADMIN);
        reputationGuard.updateGuardConfig(newConfig);

        // Now fails without category score
        (bool isValid2, ) = reputationGuard.validateUser(BOB, "");
        assertFalse(isValid2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           EDGE CASE TESTS                                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test zero minimum reputation allows AT_RISK users with stake
    function testValidateUser_ZeroMinimumReputation() public {
        bytes memory config = abi.encode(
            ReputationGuard.ReputationConfig({
                minReputationScore: 0,
                requireCategoryScore: false,
                requiredCategory: "",
                minCategoryScore: 0
            })
        );

        vm.prank(ADMIN);
        reputationGuard.updateGuardConfig(config);

        // Set user to low reputation (AT_RISK status)
        vm.prank(ADMIN);
        reputationManager.updateReputation(DAVID, -900, "Very low reputation");

        // User with AT_RISK status needs stake
        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(DAVID);
        assertEq(reputation, 100);
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK));

        // Provide stake for AT_RISK user
        // Required stake = 1000 * (600 - 100) / (600 - 100) = 1000 ether
        vm.prank(DAVID);
        stakeToken.approve(address(reputationManager), 1000 ether);
        vm.prank(DAVID);
        reputationManager.stake(1000 ether, address(stakeToken));

        (bool isValid, ) = reputationGuard.validateUser(DAVID, "");
        assertTrue(isValid);
    }

    /// @notice Test user at reputation boundary
    function testValidateUser_ReputationBoundary() public {
        // Set minimum to 500
        // ALICE at exactly 500 should pass (with stake for AT_RISK status)
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Set to boundary");

        // Provide stake for AT_RISK user
        // Required stake = 1000 * (600 - 500) / (600 - 100) = 200 ether
        vm.prank(ALICE);
        stakeToken.approve(address(reputationManager), 200 ether);
        vm.prank(ALICE);
        reputationManager.stake(200 ether, address(stakeToken));

        (bool isValid1, ) = reputationGuard.validateUser(ALICE, "");
        assertTrue(isValid1);

        // ALICE at 499 should fail (below minimum)
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -1, "Below boundary");

        (bool isValid2, ) = reputationGuard.validateUser(ALICE, "");
        assertFalse(isValid2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           METADATA TESTS                                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetGuardMetadata() public view {
        (string memory name, string memory version, string memory description) = reputationGuard.getGuardMetadata();
        assertEq(name, "ReputationGuard");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }

    function testGetGuardConfig() public view {
        bytes memory config = reputationGuard.getGuardConfig();
        assertTrue(config.length > 0);

        ReputationGuard.ReputationConfig memory decoded = abi.decode(config, (ReputationGuard.ReputationConfig));
        assertEq(decoded.minReputationScore, 500);
        assertEq(decoded.requireCategoryScore, false);
    }

    function testGetReputationConfig() public view {
        ReputationGuard.ReputationConfig memory config = reputationGuard.getReputationConfig();
        assertEq(config.minReputationScore, 500);
        assertEq(config.requireCategoryScore, false);
        assertEq(bytes(config.requiredCategory).length, 0);
        assertEq(config.minCategoryScore, 0);
    }
}
