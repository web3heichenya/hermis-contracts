// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SubmissionGuard} from "../../../../src/guards/task/SubmissionGuard.sol";
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

/// @title SubmissionGuardTest
/// @notice Comprehensive test suite for SubmissionGuard contract
/// @dev Tests task-specific submission access control
contract SubmissionGuardTest is Test {
    SubmissionGuard internal submissionGuard;
    ReputationManager internal reputationManager;
    HermisSBT internal hermisSBT;
    Treasury internal treasury;
    MockToken internal stakeToken;

    address internal constant ADMIN = address(0x1);
    address internal constant DEVELOPER = address(0x2);
    address internal constant DESIGNER = address(0x3);
    address internal constant NEW_USER = address(0x4);

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

        // Deploy SubmissionGuard
        submissionGuard = new SubmissionGuard(ADMIN, address(reputationManager));

        // Set authorizations
        treasury.setAuthorizedContract(address(reputationManager), true);

        // Initialize test users
        _initializeTestUsers();

        vm.stopPrank();
    }

    function _initializeTestUsers() internal {
        // Initialize developer with good development score
        reputationManager.initializeUser(DEVELOPER);
        reputationManager.updateReputation(DEVELOPER, -200, "Experienced developer"); // 1000 - 200 = 800
        reputationManager.addPendingCategoryScore(DEVELOPER, "development", 900);
        vm.stopPrank();
        vm.prank(DEVELOPER);
        reputationManager.claimCategoryScore("development", 900);
        vm.startPrank(ADMIN);

        // Initialize designer with good design score
        reputationManager.initializeUser(DESIGNER);
        reputationManager.updateReputation(DESIGNER, -250, "Experienced designer"); // 1000 - 250 = 750
        reputationManager.addPendingCategoryScore(DESIGNER, "design", 850);
        vm.stopPrank();
        vm.prank(DESIGNER);
        reputationManager.claimCategoryScore("design", 850);
        vm.startPrank(ADMIN);

        // Initialize new user with low scores
        reputationManager.initializeUser(NEW_USER);
        reputationManager.updateReputation(NEW_USER, -700, "New user"); // 1000 - 700 = 300
        reputationManager.addPendingCategoryScore(NEW_USER, "development", 200);
        vm.stopPrank();
        vm.prank(NEW_USER);
        reputationManager.claimCategoryScore("development", 200);
        vm.startPrank(ADMIN);

        // Give NEW_USER tokens and stake for AT_RISK status (reputation 300 requires 600 ether stake)
        stakeToken.mint(NEW_USER, 1000 ether);
        vm.stopPrank();
        vm.prank(NEW_USER);
        stakeToken.approve(address(reputationManager), 600 ether);
        vm.prank(NEW_USER);
        reputationManager.stake(600 ether, address(stakeToken));
        vm.startPrank(ADMIN);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeGuard_Success() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 500, // 50.0
            requireCategoryExpertise: true,
            requiredCategory: "development",
            minCategoryScore: 700, // 70.0
            maxFailedSubmissions: 3,
            enforceSuccessRate: true,
            minSuccessRate: 70 // 70%
        });

        bytes memory configData = abi.encode(config);

        vm.expectEmit(true, false, false, true);
        emit GuardConfigurationUpdated("", configData);

        submissionGuard.initializeGuard(configData);

        assertTrue(submissionGuard.isInitialized());
        assertEq(submissionGuard.getGuardConfig(), configData);
    }

    function testInitializeGuard_RevertWhenNotOwner() public {
        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 500,
            requireCategoryExpertise: false,
            requiredCategory: "",
            minCategoryScore: 0,
            maxFailedSubmissions: 5,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);

        vm.prank(DEVELOPER);
        vm.expectRevert();
        submissionGuard.initializeGuard(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CONFIGURATION TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateConfig_ValidConfiguration() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 600,
            requireCategoryExpertise: true,
            requiredCategory: "development",
            minCategoryScore: 700,
            maxFailedSubmissions: 3,
            enforceSuccessRate: true,
            minSuccessRate: 80
        });

        bytes memory configData = abi.encode(config);

        // Should not revert
        submissionGuard.initializeGuard(configData);
    }

    function testValidateConfig_RevertWhenInvalidReputationThreshold() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 10001, // > 1000.0 (10000 with precision)
            requireCategoryExpertise: false,
            requiredCategory: "",
            minCategoryScore: 0,
            maxFailedSubmissions: 3,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        submissionGuard.initializeGuard(configData);
    }

    function testValidateConfig_RevertWhenCategoryRequiredButEmpty() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 600,
            requireCategoryExpertise: true,
            requiredCategory: "", // Empty but required
            minCategoryScore: 700,
            maxFailedSubmissions: 3,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        submissionGuard.initializeGuard(configData);
    }

    function testValidateConfig_RevertWhenInvalidSuccessRate() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 600,
            requireCategoryExpertise: false,
            requiredCategory: "",
            minCategoryScore: 0,
            maxFailedSubmissions: 3,
            enforceSuccessRate: true,
            minSuccessRate: 101 // > 100%
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        submissionGuard.initializeGuard(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     VALIDATION TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateUser_QualifiedDeveloper_Success() public {
        _initializeGuardForDevelopment();

        (bool success, string memory reason) = submissionGuard.validateUser(DEVELOPER, "");

        assertTrue(success);
        assertEq(reason, "Submission requirements met");
    }

    function testValidateUser_InsufficientReputation_Failure() public {
        _initializeGuardForDevelopment();

        (bool success, string memory reason) = submissionGuard.validateUser(NEW_USER, "");

        assertFalse(success);
        assertTrue(bytes(reason).length > 0);
        // Should contain "Insufficient reputation for submission"
    }

    function testValidateUser_InsufficientCategoryExpertise_Failure() public {
        _initializeGuardForDevelopment();

        // DESIGNER has sufficient overall reputation but lacks development expertise
        (bool success, string memory reason) = submissionGuard.validateUser(DESIGNER, "");

        assertFalse(success);
        assertTrue(bytes(reason).length > 0);
        // Should contain "Insufficient development expertise for submission"
    }

    function testValidateUser_WithoutCategoryRequirement_Success() public {
        _initializeGuardBasic();

        // All users with sufficient reputation should pass
        (bool success, ) = submissionGuard.validateUser(DEVELOPER, "");
        assertTrue(success);

        (success, ) = submissionGuard.validateUser(DESIGNER, "");
        assertTrue(success);
    }

    function testValidateUser_WithTaskSpecificData() public {
        _initializeGuardForDevelopment();

        bytes memory taskData = abi.encode("specific_task_requirements");

        (bool success, string memory reason) = submissionGuard.validateUser(DEVELOPER, taskData);

        assertTrue(success);
        assertEq(reason, "Submission requirements met");
    }

    function testValidateUser_RevertWhenNotInitialized() public {
        vm.expectRevert();
        submissionGuard.validateUser(DEVELOPER, "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      METADATA TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetGuardMetadata() public view {
        (string memory name, string memory version, string memory description) = submissionGuard.getGuardMetadata();

        assertEq(name, "SubmissionGuard");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }

    function testGetSubmissionConfig() public {
        _initializeGuardForDevelopment();

        SubmissionGuard.SubmissionConfig memory config = submissionGuard.getSubmissionConfig();

        assertEq(config.minReputationScore, 500);
        assertTrue(config.requireCategoryExpertise);
        assertEq(config.requiredCategory, "development");
        assertEq(config.minCategoryScore, 700);
        assertEq(config.maxFailedSubmissions, 3);
        assertTrue(config.enforceSuccessRate);
        assertEq(config.minSuccessRate, 80);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EDGE CASE TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateUser_ExactThresholdValues() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 750, // Exactly DESIGNER's reputation
            requireCategoryExpertise: true,
            requiredCategory: "design",
            minCategoryScore: 850, // Exactly DESIGNER's design score
            maxFailedSubmissions: 0,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);
        submissionGuard.initializeGuard(configData);

        (bool success, ) = submissionGuard.validateUser(DESIGNER, "");
        assertTrue(success);
    }

    function testValidateUser_ZeroThresholds() public {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 0,
            requireCategoryExpertise: false,
            requiredCategory: "",
            minCategoryScore: 0,
            maxFailedSubmissions: 0,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);
        submissionGuard.initializeGuard(configData);

        // Even NEW_USER should pass with zero thresholds
        (bool success, ) = submissionGuard.validateUser(NEW_USER, "");
        assertTrue(success);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _initializeGuardForDevelopment() internal {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 500, // 50.0
            requireCategoryExpertise: true,
            requiredCategory: "development",
            minCategoryScore: 700, // 70.0
            maxFailedSubmissions: 3,
            enforceSuccessRate: true,
            minSuccessRate: 80 // 80%
        });

        bytes memory configData = abi.encode(config);
        submissionGuard.initializeGuard(configData);
    }

    function _initializeGuardBasic() internal {
        vm.prank(ADMIN);

        SubmissionGuard.SubmissionConfig memory config = SubmissionGuard.SubmissionConfig({
            minReputationScore: 500, // 50.0
            requireCategoryExpertise: false,
            requiredCategory: "",
            minCategoryScore: 0,
            maxFailedSubmissions: 5,
            enforceSuccessRate: false,
            minSuccessRate: 0
        });

        bytes memory configData = abi.encode(config);
        submissionGuard.initializeGuard(configData);
    }
}
