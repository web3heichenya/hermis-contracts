// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {GlobalGuard} from "../../../../src/guards/global/GlobalGuard.sol";
import {ReputationManager} from "../../../../src/core/ReputationManager.sol";
import {HermisSBT} from "../../../../src/core/HermisSBT.sol";
import {Treasury} from "../../../../src/core/Treasury.sol";
import {DataTypes} from "../../../../src/libraries/DataTypes.sol";
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

/// @title GlobalGuardTest
/// @notice Comprehensive test suite for GlobalGuard contract
/// @dev Tests platform-wide access control based on reputation and staking
contract GlobalGuardTest is Test {
    GlobalGuard internal globalGuard;
    ReputationManager internal reputationManager;
    HermisSBT internal hermisSBT;
    Treasury internal treasury;
    MockToken internal stakeToken;

    address internal constant ADMIN = address(0x1);
    address internal constant USER1 = address(0x2);
    address internal constant USER2 = address(0x3);
    address internal constant USER_BLACKLISTED = address(0x4);
    address internal constant USER_AT_RISK = address(0x5);

    event GuardConfigurationUpdated(bytes oldConfig, bytes newConfig);

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy MockToken
        stakeToken = new MockToken();

        // Deploy HermisSBT
        hermisSBT = new HermisSBT(
            ADMIN,
            "Hermis SBT",
            "HSBT",
            "https://api.hermis.network/metadata/",
            "https://api.hermis.network/contract-metadata/"
        );

        // Deploy ReputationManager with Treasury and StakeToken
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Deploy GlobalGuard
        globalGuard = new GlobalGuard(ADMIN, address(reputationManager));

        // Set authorizations
        treasury.setAuthorizedContract(address(reputationManager), true);

        // Mint tokens to test users
        stakeToken.mint(USER1, 10 ether);
        stakeToken.mint(USER2, 10 ether);
        stakeToken.mint(USER_AT_RISK, 1000 ether);
        stakeToken.mint(USER_BLACKLISTED, 10 ether);

        // Initialize test users
        _initializeTestUsers();

        vm.stopPrank();
    }

    function _initializeTestUsers() internal {
        // Initialize normal user
        reputationManager.initializeUser(USER1);
        reputationManager.updateReputation(USER1, -300, "Normal user"); // 70.0 reputation (1000 - 300)

        // Initialize normal user 2
        reputationManager.initializeUser(USER2);
        reputationManager.updateReputation(USER2, -350, "Normal user 2"); // 65.0 reputation (1000 - 350)

        // Initialize blacklisted user
        reputationManager.initializeUser(USER_BLACKLISTED);
        reputationManager.updateReputation(USER_BLACKLISTED, -1000, "Blacklisted user"); // 0 reputation (1000 - 1000)

        // Initialize at-risk user
        reputationManager.initializeUser(USER_AT_RISK);
        reputationManager.updateReputation(USER_AT_RISK, -800, "At-risk user"); // 20.0 reputation (1000 - 800)
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeGuard_Success() public {
        vm.prank(ADMIN);

        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600, // 60.0
            atRiskThreshold: 200, // 20.0
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);

        vm.expectEmit(true, false, false, true);
        emit GuardConfigurationUpdated("", configData);

        globalGuard.initializeGuard(configData);

        assertTrue(globalGuard.isInitialized());
        assertEq(globalGuard.getGuardConfig(), configData);
    }

    function testInitializeGuard_RevertWhenAlreadyInitialized() public {
        vm.startPrank(ADMIN);

        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600,
            atRiskThreshold: 200,
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);
        globalGuard.initializeGuard(configData);

        vm.expectRevert();
        globalGuard.initializeGuard(configData);

        vm.stopPrank();
    }

    function testInitializeGuard_RevertWhenNotOwner() public {
        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600,
            atRiskThreshold: 200,
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);

        vm.prank(USER1);
        vm.expectRevert();
        globalGuard.initializeGuard(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CONFIGURATION TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateConfig_ValidConfiguration() public {
        vm.prank(ADMIN);

        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600,
            atRiskThreshold: 200,
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);

        // Should not revert
        globalGuard.initializeGuard(configData);
    }

    function testValidateConfig_RevertWhenInvalidThresholds() public {
        vm.prank(ADMIN);

        // Test: minReputationForNormal > 1000.0 (10000 with precision)
        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 10001,
            atRiskThreshold: 200,
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        globalGuard.initializeGuard(configData);
    }

    function testValidateConfig_RevertWhenAtRiskThresholdTooHigh() public {
        vm.prank(ADMIN);

        // Test: atRiskThreshold > minReputationForNormal
        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600,
            atRiskThreshold: 700, // Higher than minReputationForNormal
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        globalGuard.initializeGuard(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     VALIDATION TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateUser_NormalUser_Success() public {
        _initializeGuardWithDefaults();

        bytes memory actionData = abi.encode("PUBLISH_TASK");

        (bool success, string memory reason) = globalGuard.validateUser(USER1, actionData);

        assertTrue(success);
        assertEq(reason, "Global access requirements met");
    }

    function testValidateUser_BlacklistedUser_Failure() public {
        _initializeGuardWithDefaults();

        bytes memory actionData = abi.encode("PUBLISH_TASK");

        (bool success, string memory reason) = globalGuard.validateUser(USER_BLACKLISTED, actionData);

        assertFalse(success);
        assertEq(reason, "User is blacklisted");
    }

    function testValidateUser_AtRiskUser_WithSufficientStake() public {
        _initializeGuardWithDefaults();

        // Add stake for at-risk user (reputation 200 requires 800 ether stake)
        vm.startPrank(USER_AT_RISK);
        stakeToken.approve(address(reputationManager), 800 ether);
        reputationManager.stake(800 ether, address(stakeToken));
        vm.stopPrank();

        bytes memory actionData = abi.encode("VIEW_TASK");

        (bool success, string memory reason) = globalGuard.validateUser(USER_AT_RISK, actionData);

        assertTrue(success);
        assertEq(reason, "Global access requirements met");
    }

    function testValidateUser_AtRiskUser_WithInsufficientStake() public {
        _initializeGuardWithDefaults();

        bytes memory actionData = abi.encode("SUBMIT_WORK");

        (bool success, string memory reason) = globalGuard.validateUser(USER_AT_RISK, actionData);

        assertFalse(success);
        assertTrue(bytes(reason).length > 0);
        // Should contain "Insufficient stake for at-risk user"
    }

    function testValidateUser_ActionSpecific_HighRiskActions() public {
        _initializeGuardWithDefaults();

        // Give AT_RISK user sufficient stake
        vm.startPrank(USER_AT_RISK);
        stakeToken.approve(address(reputationManager), 800 ether);
        reputationManager.stake(800 ether, address(stakeToken));
        vm.stopPrank();

        // Test high-risk actions that require normal status
        string[3] memory highRiskActions = ["PUBLISH_TASK", "SUBMIT_WORK", "REVIEW_SUBMISSION"];

        for (uint256 i = 0; i < highRiskActions.length; i++) {
            bytes memory actionData = abi.encode(highRiskActions[i]);

            // Normal user should succeed
            (bool success, ) = globalGuard.validateUser(USER1, actionData);
            assertTrue(success);

            // At-risk user should fail (even with stake, action validation comes after stake validation)
            (success, ) = globalGuard.validateUser(USER_AT_RISK, actionData);
            assertFalse(success);
        }
    }

    function testValidateUser_ArbitrationAction_ReputationRequirement() public {
        _initializeGuardWithDefaults();

        // Give USER_AT_RISK sufficient stake so we can test arbitration reputation requirements
        vm.startPrank(USER_AT_RISK);
        stakeToken.approve(address(reputationManager), 800 ether);
        reputationManager.stake(800 ether, address(stakeToken));
        vm.stopPrank();

        bytes memory actionData = abi.encode("REQUEST_ARBITRATION");

        // USER1 has 70.0 reputation (700), should succeed
        (bool success, ) = globalGuard.validateUser(USER1, actionData);
        assertTrue(success);

        // USER2 has 65.0 reputation (650), should succeed
        (success, ) = globalGuard.validateUser(USER2, actionData);
        assertTrue(success);

        // USER_AT_RISK has 20.0 reputation (200), should fail
        string memory reason;
        (success, reason) = globalGuard.validateUser(USER_AT_RISK, actionData);
        assertFalse(success);
        assertEq(reason, "Arbitration requires minimum 50.0 reputation");
    }

    function testValidateUser_RevertWhenNotInitialized() public {
        bytes memory actionData = abi.encode("PUBLISH_TASK");

        vm.expectRevert();
        globalGuard.validateUser(USER1, actionData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      METADATA TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetGuardMetadata() public view {
        (string memory name, string memory version, string memory description) = globalGuard.getGuardMetadata();

        assertEq(name, "GlobalGuard");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }

    function testGetGlobalGuardConfig() public {
        _initializeGuardWithDefaults();

        GlobalGuard.GlobalGuardConfig memory config = globalGuard.getGlobalGuardConfig();

        assertEq(config.minReputationForNormal, 600);
        assertEq(config.atRiskThreshold, 200);
        assertEq(config.baseStakeAmount, 1 ether);
        assertTrue(config.enforceStakeForAtRisk);
        assertFalse(config.allowBlacklistedUsers);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   REPUTATION MANAGER TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testUpdateReputationManager_Success() public {
        // Deploy new ReputationManager
        ReputationManager newReputationManager = new ReputationManager(ADMIN, address(0), address(0));

        vm.prank(ADMIN);
        globalGuard.updateReputationManager(address(newReputationManager));

        assertEq(address(globalGuard.reputationManager()), address(newReputationManager));
    }

    function testUpdateReputationManager_RevertWhenNotOwner() public {
        address newReputationManager = address(0x999);

        vm.prank(USER1);
        vm.expectRevert();
        globalGuard.updateReputationManager(newReputationManager);
    }

    function testUpdateReputationManager_RevertWhenZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        globalGuard.updateReputationManager(address(0));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _initializeGuardWithDefaults() internal {
        vm.prank(ADMIN);

        GlobalGuard.GlobalGuardConfig memory config = GlobalGuard.GlobalGuardConfig({
            minReputationForNormal: 600, // 60.0
            atRiskThreshold: 200, // 20.0
            baseStakeAmount: 1 ether,
            enforceStakeForAtRisk: true,
            allowBlacklistedUsers: false
        });

        bytes memory configData = abi.encode(config);
        globalGuard.initializeGuard(configData);
    }
}
