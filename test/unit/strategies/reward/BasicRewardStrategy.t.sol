// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BasicRewardStrategy} from "../../../../src/strategies/reward/BasicRewardStrategy.sol";
import {DataTypes} from "../../../../src/libraries/DataTypes.sol";

/// @title BasicRewardStrategyTest
/// @notice Comprehensive test suite for BasicRewardStrategy contract
/// @dev Tests percentage-based reward distribution with accuracy modifiers
contract BasicRewardStrategyTest is Test {
    BasicRewardStrategy internal rewardStrategy;

    address internal constant ADMIN = address(0x1);
    address internal constant USER1 = address(0x2);
    address internal constant REVIEWER1 = address(0x3);
    address internal constant REVIEWER2 = address(0x4);

    event RewardStrategyConfigUpdated(bytes oldConfig, bytes newConfig);

    function setUp() public {
        vm.startPrank(ADMIN);

        // Deploy BasicRewardStrategy
        rewardStrategy = new BasicRewardStrategy(ADMIN);

        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeRewardStrategy_Success() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20, // 20% bonus
            accuracyPenalty: 10, // 10% penalty
            minReviewerReward: 0.01 ether,
            maxReviewerReward: 10 ether
        });

        bytes memory configData = abi.encode(config);

        vm.expectEmit(true, false, false, true);
        emit RewardStrategyConfigUpdated("", configData);

        rewardStrategy.initializeRewardStrategy(configData);

        assertTrue(rewardStrategy.isInitialized());
        assertEq(rewardStrategy.getRewardConfig(), configData);
    }

    function testInitializeRewardStrategy_RevertWhenAlreadyInitialized() public {
        vm.startPrank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 80,
            reviewerPercentage: 15,
            platformPercentage: 5,
            accuracyBonus: 10,
            accuracyPenalty: 5,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);
        rewardStrategy.initializeRewardStrategy(configData);

        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);

        vm.stopPrank();
    }

    function testInitializeRewardStrategy_RevertWhenNotOwner() public {
        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20,
            accuracyPenalty: 10,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);

        vm.prank(USER1);
        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CONFIGURATION TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testValidateConfig_ValidConfiguration() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 60,
            reviewerPercentage: 30,
            platformPercentage: 10,
            accuracyBonus: 25,
            accuracyPenalty: 15,
            minReviewerReward: 0.1 ether,
            maxReviewerReward: 5 ether
        });

        bytes memory configData = abi.encode(config);

        // Should not revert
        rewardStrategy.initializeRewardStrategy(configData);
    }

    function testValidateConfig_RevertWhenPercentagesNotSum100() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 15, // 70 + 20 + 15 = 105 > 100
            accuracyBonus: 20,
            accuracyPenalty: 10,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    function testValidateConfig_RevertWhenIndividualPercentageOver100() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 101, // > 100
            reviewerPercentage: 0,
            platformPercentage: 0,
            accuracyBonus: 20,
            accuracyPenalty: 10,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    function testValidateConfig_RevertWhenAccuracyModifiersOver100() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 101, // > 100
            accuracyPenalty: 10,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    function testValidateConfig_RevertWhenMinRewardExceedsMax() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20,
            accuracyPenalty: 10,
            minReviewerReward: 2 ether,
            maxReviewerReward: 1 ether // min > max
        });

        bytes memory configData = abi.encode(config);

        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                REWARD DISTRIBUTION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testCalculateRewardDistribution_StandardCase() public {
        _initializeWithDefaults();

        uint256 totalReward = 1000 ether;
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            1,
            totalReward,
            123,
            3
        );

        assertEq(distribution.creatorShare, 700 ether); // 70%
        assertEq(distribution.reviewerShare, 200 ether); // 20%
        assertEq(distribution.platformShare, 100 ether); // 10%
        assertEq(distribution.publisherRefund, 0); // Always 0 in basic strategy
    }

    function testCalculateRewardDistribution_WithRounding() public {
        _initializeWithDefaults();

        // Use amount that doesn't divide evenly
        uint256 totalReward = 1001 ether;
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            1,
            totalReward,
            123,
            3
        );

        // Should handle rounding gracefully
        uint256 totalDistributed = distribution.creatorShare +
            distribution.reviewerShare +
            distribution.platformShare +
            distribution.publisherRefund;

        assertLe(totalDistributed, totalReward);
        assertGe(totalDistributed, totalReward - 3); // Allow small rounding difference
    }

    function testCalculateRewardDistribution_ZeroReward() public {
        _initializeWithDefaults();

        vm.expectRevert();
        rewardStrategy.calculateRewardDistribution(1, 0, 123, 3);
    }

    function testCalculateRewardDistribution_RevertWhenNotInitialized() public {
        vm.expectRevert();
        rewardStrategy.calculateRewardDistribution(1, 1000 ether, 123, 3);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                REVIEWER REWARD TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testCalculateReviewerReward_AccurateReviewer() public {
        _initializeWithDefaults();

        uint256 totalReviewerReward = 200 ether;
        uint256 reviewerCount = 3;

        uint256 reward = rewardStrategy.calculateReviewerReward(
            1,
            REVIEWER1,
            totalReviewerReward,
            reviewerCount,
            true // accurate
        );

        // Base: 200/3 = 66.67 ether, with 20% bonus = ~80 ether
        uint256 baseReward = totalReviewerReward / reviewerCount;
        uint256 expectedReward = baseReward + (baseReward * 20) / 100;

        assertEq(reward, expectedReward);
    }

    function testCalculateReviewerReward_InaccurateReviewer() public {
        _initializeWithDefaults();

        uint256 totalReviewerReward = 200 ether;
        uint256 reviewerCount = 3;

        uint256 reward = rewardStrategy.calculateReviewerReward(
            1,
            REVIEWER1,
            totalReviewerReward,
            reviewerCount,
            false // inaccurate
        );

        // Base: 200/3 = 66.67 ether, with 10% penalty = ~60 ether
        uint256 baseReward = totalReviewerReward / reviewerCount;
        uint256 penalty = (baseReward * 10) / 100;
        uint256 expectedReward = baseReward - penalty;

        assertEq(reward, expectedReward);
    }

    function testCalculateReviewerReward_WithMinimumLimit() public {
        _initializeWithMinMaxLimits();

        uint256 totalReviewerReward = 0.06 ether; // Very small amount
        uint256 reviewerCount = 3;

        uint256 reward = rewardStrategy.calculateReviewerReward(
            1,
            REVIEWER1,
            totalReviewerReward,
            reviewerCount,
            false // inaccurate, would be very small
        );

        // Should be 0.018 ether (0.02 - 10% penalty)
        assertEq(reward, 0.018 ether);
    }

    function testCalculateReviewerReward_WithMaximumLimit() public {
        _initializeWithMinMaxLimits();

        uint256 totalReviewerReward = 100 ether; // Large amount
        uint256 reviewerCount = 1; // Single reviewer gets it all

        uint256 reward = rewardStrategy.calculateReviewerReward(
            1,
            REVIEWER1,
            totalReviewerReward,
            reviewerCount,
            true // accurate, would be very large
        );

        // Should be capped at maximum reward (10 ether)
        assertEq(reward, 10 ether);
    }

    function testCalculateReviewerReward_ZeroReviewers() public {
        _initializeWithDefaults();

        uint256 reward = rewardStrategy.calculateReviewerReward(1, REVIEWER1, 200 ether, 0, true);

        assertEq(reward, 0);
    }

    function testCalculateReviewerReward_ZeroTotalReward() public {
        _initializeWithDefaults();

        uint256 reward = rewardStrategy.calculateReviewerReward(1, REVIEWER1, 0, 3, true);

        assertEq(reward, 0);
    }

    function testCalculateReviewerReward_PenaltyExceedsBase() public {
        vm.prank(ADMIN);

        // Configure with high penalty
        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20,
            accuracyPenalty: 150, // 150% penalty - should be rejected
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);

        // Expect the initialization to revert due to invalid penalty
        vm.expectRevert();
        rewardStrategy.initializeRewardStrategy(configData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      METADATA TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetRewardMetadata() public view {
        (string memory name, string memory version, string memory description) = rewardStrategy.getRewardMetadata();

        assertEq(name, "BasicRewardStrategy");
        assertEq(version, "1.0.0");
        assertTrue(bytes(description).length > 0);
    }

    function testGetBasicRewardConfig() public {
        _initializeWithDefaults();

        BasicRewardStrategy.BasicRewardConfig memory config = rewardStrategy.getBasicRewardConfig();

        assertEq(config.creatorPercentage, 70);
        assertEq(config.reviewerPercentage, 20);
        assertEq(config.platformPercentage, 10);
        assertEq(config.accuracyBonus, 20);
        assertEq(config.accuracyPenalty, 10);
        assertEq(config.minReviewerReward, 0);
        assertEq(config.maxReviewerReward, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EDGE CASE TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testCalculateRewardDistribution_AllToOneCategory() public {
        vm.prank(ADMIN);

        // All reward goes to creator
        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 100,
            reviewerPercentage: 0,
            platformPercentage: 0,
            accuracyBonus: 0,
            accuracyPenalty: 0,
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);
        rewardStrategy.initializeRewardStrategy(configData);

        uint256 totalReward = 1000 ether;
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            1,
            totalReward,
            123,
            3
        );

        assertEq(distribution.creatorShare, 1000 ether);
        assertEq(distribution.reviewerShare, 0);
        assertEq(distribution.platformShare, 0);
        assertEq(distribution.publisherRefund, 0);
    }

    function testCalculateReviewerReward_ExactLimits() public {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 0,
            accuracyPenalty: 0,
            minReviewerReward: 1 ether,
            maxReviewerReward: 1 ether // min = max
        });

        bytes memory configData = abi.encode(config);
        rewardStrategy.initializeRewardStrategy(configData);

        // Any calculation should result in exactly 1 ether
        uint256 reward = rewardStrategy.calculateReviewerReward(1, REVIEWER1, 100 ether, 1, true);

        assertEq(reward, 1 ether);
    }

    function testCalculateRewardDistribution_LargeNumbers() public {
        _initializeWithDefaults();

        // Test with very large numbers
        uint256 totalReward = type(uint128).max; // Large but not overflow-prone
        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            1,
            totalReward,
            123,
            1000
        );

        // Should handle large numbers without overflow
        assertTrue(distribution.creatorShare > 0);
        assertTrue(distribution.reviewerShare > 0);
        assertTrue(distribution.platformShare > 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _initializeWithDefaults() internal {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20, // 20% bonus
            accuracyPenalty: 10, // 10% penalty
            minReviewerReward: 0,
            maxReviewerReward: 0
        });

        bytes memory configData = abi.encode(config);
        rewardStrategy.initializeRewardStrategy(configData);
    }

    function _initializeWithMinMaxLimits() internal {
        vm.prank(ADMIN);

        BasicRewardStrategy.BasicRewardConfig memory config = BasicRewardStrategy.BasicRewardConfig({
            creatorPercentage: 70,
            reviewerPercentage: 20,
            platformPercentage: 10,
            accuracyBonus: 20,
            accuracyPenalty: 10,
            minReviewerReward: 0.01 ether,
            maxReviewerReward: 10 ether
        });

        bytes memory configData = abi.encode(config);
        rewardStrategy.initializeRewardStrategy(configData);
    }
}
