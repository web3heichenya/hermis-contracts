// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IRewardStrategy
/// @notice Interface for reward distribution strategy contracts that handle task completion rewards
/// @dev This interface defines the standard reward strategy functionality including:
///      - Reward distribution calculation based on task parameters
///      - Individual reviewer reward computation with accuracy considerations
///      - Configuration management for strategy parameters
///      - Metadata provision for strategy identification and versioning
/// @custom:interface Defines standard reward distribution behavior for task completion
/// @author Hermis Team
interface IRewardStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when reward strategy configuration is invalid or malformed
    error InvalidRewardConfiguration();

    /// @notice Error when available reward amount is insufficient for required distribution
    error InsufficientRewardAmount(uint256 required, uint256 available);

    /// @notice Error when reward calculation fails for a specific task
    error RewardCalculationFailed(uint256 taskId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when reward distribution is calculated for a task
    /// @param taskId ID of the task for which rewards were calculated
    /// @param totalReward Total reward amount being distributed
    /// @param creatorShare Amount allocated to the submission creator
    /// @param reviewerShare Amount allocated to reviewers for their participation
    /// @param platformShare Amount allocated to the platform for operational costs
    event RewardCalculated(
        uint256 indexed taskId,
        uint256 totalReward,
        uint256 creatorShare,
        uint256 reviewerShare,
        uint256 platformShare
    );

    /// @notice Emitted when reward strategy configuration is updated
    /// @param oldConfig Previous configuration data for the reward strategy
    /// @param newConfig New configuration data replacing the old settings
    event RewardStrategyConfigUpdated(bytes oldConfig, bytes newConfig);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    REWARD FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Calculates reward distribution for a completed task based on strategy parameters
    /// @dev Implementation should distribute total reward according to strategy configuration.
    ///      Should handle edge cases like zero rewards or zero reviewers gracefully.
    /// @param taskId ID of the completed task
    /// @param totalReward Total reward amount to distribute among participants
    /// @param adoptedSubmissionId ID of the submission that was adopted
    /// @param reviewerCount Number of reviewers who participated in the task
    /// @return distribution Reward distribution breakdown with calculated amounts
    /// @custom:view This function is read-only and performs reward calculations
    function calculateRewardDistribution(
        uint256 taskId,
        uint256 totalReward,
        uint256 adoptedSubmissionId,
        uint256 reviewerCount
    ) external view returns (DataTypes.RewardDistribution memory distribution);

    /// @notice Calculates individual reviewer reward with accuracy considerations
    /// @dev Implementation should consider reviewer accuracy and apply appropriate bonuses or penalties.
    ///      Should handle edge cases and ensure reward doesn't exceed available amount.
    /// @param taskId ID of the task being rewarded
    /// @param reviewerId Address of the reviewer receiving the reward
    /// @param totalReviewerReward Total reward amount allocated to all reviewers
    /// @param reviewerCount Total number of reviewers who participated
    /// @param reviewAccuracy Whether the reviewer's assessment matched the final outcome
    /// @return reward Individual reviewer reward amount
    /// @custom:view This function is read-only and performs reviewer reward calculations
    function calculateReviewerReward(
        uint256 taskId,
        address reviewerId,
        uint256 totalReviewerReward,
        uint256 reviewerCount,
        bool reviewAccuracy
    ) external view returns (uint256 reward);

    /// @notice Gets the current reward strategy configuration data
    /// @dev Returns raw bytes that must be decoded according to strategy implementation
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getRewardConfig() external view returns (bytes memory config);

    /// @notice Updates the reward strategy configuration with new parameters
    /// @dev Should validate configuration before updating and emit configuration change event
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by authorized addresses (typically owner)
    function updateRewardConfig(bytes calldata newConfig) external;

    /// @notice Gets reward strategy metadata for identification and versioning
    /// @dev Returns static metadata about the reward strategy implementation
    /// @return name Strategy implementation name
    /// @return version Semantic version of the strategy
    /// @return description Human-readable description of strategy functionality
    /// @custom:view This function is read-only and returns static metadata
    function getRewardMetadata()
        external
        pure
        returns (string memory name, string memory version, string memory description);
}
