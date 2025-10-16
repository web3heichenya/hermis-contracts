// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SimpleAdoptionStrategy} from "../../../../src/strategies/adoption/SimpleAdoptionStrategy.sol";
import {DataTypes} from "../../../../src/libraries/DataTypes.sol";

/// @title SimpleAdoptionStrategyTest
/// @notice Comprehensive test suite for SimpleAdoptionStrategy contract
/// @dev Tests submission adoption logic with majority voting and time limits
contract SimpleAdoptionStrategyTest is Test {
    SimpleAdoptionStrategy internal adoptionStrategy;

    address internal constant ADMIN = address(0x1);
    address internal constant USER1 = address(0x2);

    event StrategyConfigurationUpdated(bytes oldConfig, bytes newConfig);

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy SimpleAdoptionStrategy
        adoptionStrategy = new SimpleAdoptionStrategy(ADMIN);

        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeStrategy_Success() public {
        vm.prank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60, // 60%
            rejectionThreshold: 40, // 40%
            expirationTime: 7 days,
            allowTimeBasedAdoption: true,
            autoAdoptionTime: 3 days
        });

        bytes memory configData = abi.encode(config);

        vm.expectEmit(true, false, false, true);
        emit StrategyConfigurationUpdated("", configData);

        adoptionStrategy.initializeStrategy(configData);

        assertTrue(adoptionStrategy.isInitialized());
        assertEq(adoptionStrategy.getStrategyConfig(), configData);
    }

    function testInitializeStrategy_RevertWhenAlreadyInitialized() public {
        vm.startPrank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);
        adoptionStrategy.initializeStrategy(configData);

        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);

        vm.stopPrank();
    }

    function testInitializeStrategy_RevertWhenNotOwner() public {
        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);

        vm.prank(USER1);
        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CONFIGURATION TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateConfig_ValidConfiguration() public {
        vm.prank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 5,
            approvalThreshold: 70,
            rejectionThreshold: 30,
            expirationTime: 14 days,
            allowTimeBasedAdoption: true,
            autoAdoptionTime: 7 days
        });

        bytes memory configData = abi.encode(config);

        // Should not revert
        adoptionStrategy.initializeStrategy(configData);
    }

    function testValidateConfig_RevertWhenInvalidThresholds() public {
        vm.prank(ADMIN);

        // Test: approvalThreshold > 100
        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 101,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);
    }

    function testValidateConfig_RevertWhenOverlappingThresholds() public {
        vm.prank(ADMIN);

        // Test: approvalThreshold + rejectionThreshold > 100
        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60,
            rejectionThreshold: 50, // 60 + 50 > 100
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);
    }

    function testValidateConfig_RevertWhenZeroMinReviews() public {
        vm.prank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 0, // Invalid
            approvalThreshold: 60,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);
    }

    function testValidateConfig_RevertWhenInvalidTimeConfiguration() public {
        vm.prank(ADMIN);

        // Test: autoAdoptionTime >= expirationTime when auto-adoption is enabled
        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: true,
            autoAdoptionTime: 8 days // Should be < expirationTime
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        adoptionStrategy.initializeStrategy(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  EVALUATION TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testEvaluateSubmission_Adoption_Success() public {
        _initializeWithDefaults();

        // 4 total reviews: 3 approve (75%), 1 reject (25%)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 3, 1, 4, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission meets approval threshold");
    }

    function testEvaluateSubmission_Rejection_Success() public {
        _initializeWithDefaults();

        // 5 total reviews: 1 approve (20%), 3 reject (60%)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 1, 3, 5, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.REMOVED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission meets rejection threshold");
    }

    function testEvaluateSubmission_InsufficientReviews() public {
        _initializeWithDefaults();

        // Only 2 reviews, but minimum is 3
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 2, 0, 2, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.UNDER_REVIEW));
        assertFalse(shouldChange);
        assertEq(reason, "Insufficient reviews for decision");
    }

    function testEvaluateSubmission_NoThresholdMet() public {
        _initializeWithDefaults();

        // 5 total reviews: 2 approve (40%), 1 reject (20%), 2 abstain
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 2, 1, 5, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.UNDER_REVIEW));
        assertFalse(shouldChange);
        assertEq(reason, "No adoption threshold reached");
    }

    function testEvaluateSubmission_TimeBasedExpiration() public {
        _initializeWithDefaults();

        // Time exceeds expiration time (7 days)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 2, 1, 3, 8 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.REMOVED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission expired due to timeout");
    }

    function testEvaluateSubmission_AutoAdoption() public {
        _initializeWithAutoAdoption();

        // No reviews but time exceeds auto-adoption time (3 days)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 0, 0, 0, 4 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
        assertEq(reason, "Auto-adopted due to no reviews within time limit");
    }

    function testEvaluateSubmission_ExactThresholdValues() public {
        _initializeWithDefaults();

        // Exact threshold: 3 out of 5 = 60% (exactly approval threshold)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 3, 2, 5, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission meets approval threshold");
    }

    function testEvaluateSubmission_RevertWhenNotInitialized() public {
        vm.expectRevert();
        adoptionStrategy.evaluateSubmission(1, 3, 1, 4, 1 days);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   COMPLETION TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testShouldCompleteTask_WithAdoptedSubmission() public {
        _initializeWithDefaults();

        bool shouldComplete = adoptionStrategy.shouldCompleteTask(1, 123);

        assertTrue(shouldComplete);
    }

    function testShouldCompleteTask_WithoutAdoptedSubmission() public {
        _initializeWithDefaults();

        bool shouldComplete = adoptionStrategy.shouldCompleteTask(1, 0);

        assertFalse(shouldComplete);
    }

    function testShouldCompleteTask_RevertWhenNotInitialized() public {
        vm.expectRevert();
        adoptionStrategy.shouldCompleteTask(1, 123);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      METADATA TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetStrategyMetadata() public view {
        (string memory name, string memory version, string memory description) = adoptionStrategy.getStrategyMetadata();

        assertEq(name, "SimpleAdoptionStrategy");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }

    function testGetSimpleAdoptionConfig() public {
        _initializeWithDefaults();

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = adoptionStrategy.getSimpleAdoptionConfig();

        assertEq(config.minReviewsRequired, 3);
        assertEq(config.approvalThreshold, 60);
        assertEq(config.rejectionThreshold, 40);
        assertEq(config.expirationTime, 7 days);
        assertFalse(config.allowTimeBasedAdoption);
        assertEq(config.autoAdoptionTime, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EDGE CASE TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testEvaluateSubmission_MaximumThresholds() public {
        vm.prank(ADMIN);

        // Edge case: 50% approval + 50% rejection = 100% (valid)
        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 2,
            approvalThreshold: 50,
            rejectionThreshold: 50,
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);
        adoptionStrategy.initializeStrategy(configData);

        // Test approval
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, ) = adoptionStrategy.evaluateSubmission(
            1,
            1,
            1,
            2,
            1 days
        );

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
    }

    function testEvaluateSubmission_ZeroReviews_NoAutoAdoption() public {
        _initializeWithDefaults();

        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 0, 0, 0, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.UNDER_REVIEW));
        assertFalse(shouldChange);
        assertEq(reason, "Insufficient reviews for decision");
    }

    function testEvaluateSubmission_LargeNumberOfReviews() public {
        _initializeWithDefaults();

        // 1000 reviews: 610 approve (61%), 390 reject (39%)
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = adoptionStrategy
            .evaluateSubmission(1, 610, 390, 1000, 1 days);

        assertEq(uint256(newStatus), uint256(DataTypes.SubmissionStatus.ADOPTED));
        assertTrue(shouldChange);
        assertEq(reason, "Submission meets approval threshold");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _initializeWithDefaults() internal {
        vm.prank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60, // 60%
            rejectionThreshold: 40, // 40%
            expirationTime: 7 days,
            allowTimeBasedAdoption: false,
            autoAdoptionTime: 0
        });

        bytes memory configData = abi.encode(config);
        adoptionStrategy.initializeStrategy(configData);
    }

    function _initializeWithAutoAdoption() internal {
        vm.prank(ADMIN);

        SimpleAdoptionStrategy.SimpleAdoptionConfig memory config = SimpleAdoptionStrategy.SimpleAdoptionConfig({
            minReviewsRequired: 3,
            approvalThreshold: 60,
            rejectionThreshold: 40,
            expirationTime: 7 days,
            allowTimeBasedAdoption: true,
            autoAdoptionTime: 3 days
        });

        bytes memory configData = abi.encode(config);
        adoptionStrategy.initializeStrategy(configData);
    }
}
