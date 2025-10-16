// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IAdoptionStrategy
/// @notice Interface for adoption strategy contracts that determine when submissions are adopted or removed based on review metrics
/// @dev This interface defines the standard adoption strategy functionality including:
///      - Submission status evaluation based on review outcomes and timing
///      - Task completion determination through adoption criteria
///      - Configuration management for strategy parameters
///      - Metadata provision for strategy identification and versioning
/// @custom:interface Defines standard adoption behavior for submission lifecycle management
/// @author Hermis Team
interface IAdoptionStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when adoption strategy configuration is invalid or malformed
    error InvalidStrategyConfiguration();

    /// @notice Error when strategy cannot be applied to the specified submission
    error StrategyNotApplicable(uint256 submissionId);

    /// @notice Error when there is insufficient review data to make an adoption decision
    error InsufficientReviewData(uint256 submissionId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a submission status changes due to adoption strategy evaluation
    /// @param submissionId ID of the submission whose status changed
    /// @param oldStatus Previous status of the submission before evaluation
    /// @param newStatus New status assigned to the submission after evaluation
    /// @param reason Human-readable explanation for the status change decision
    event SubmissionStatusChanged(
        uint256 indexed submissionId,
        DataTypes.SubmissionStatus oldStatus,
        DataTypes.SubmissionStatus newStatus,
        string reason
    );

    /// @notice Emitted when adoption strategy configuration is updated
    /// @param oldConfig Previous configuration data that was replaced
    /// @param newConfig New configuration data that was applied
    event StrategyConfigurationUpdated(bytes oldConfig, bytes newConfig);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    STRATEGY FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Evaluates whether a submission should change status based on accumulated reviews and timing
    /// @dev Implementation should consider review counts, ratios, and timing thresholds according to strategy.
    ///      Should handle edge cases like zero reviews or immediate time evaluations.
    /// @param submissionId ID of the submission to evaluate for status change
    /// @param approveCount Total number of positive reviews received
    /// @param rejectCount Total number of negative reviews received
    /// @param totalReviews Total number of reviews submitted (approve + reject + abstain)
    /// @param timeSinceSubmission Time elapsed since submission creation in seconds
    /// @return newStatus Recommended new status for the submission
    /// @return shouldChange Whether the status should be changed from current state
    /// @return reason Human-readable explanation for the status change decision
    /// @custom:view This function is read-only and performs adoption evaluation
    function evaluateSubmission(
        uint256 submissionId,
        uint256 approveCount,
        uint256 rejectCount,
        uint256 totalReviews,
        uint256 timeSinceSubmission
    ) external view returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason);

    /// @notice Determines whether a task should be marked as completed based on adoption criteria
    /// @dev Implementation should verify that adoption meets completion requirements and thresholds.
    ///      Should consider task-specific completion rules and adoption quality metrics.
    /// @param taskId ID of the task to check for completion
    /// @param adoptedSubmissionId ID of the submission that was adopted for the task
    /// @return shouldComplete Whether the task meets criteria to be marked as completed
    /// @custom:view This function is read-only and performs completion evaluation
    function shouldCompleteTask(
        uint256 taskId,
        uint256 adoptedSubmissionId
    ) external view returns (bool shouldComplete);

    /// @notice Gets the current adoption strategy configuration data
    /// @dev Returns raw bytes that must be decoded according to strategy implementation
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getStrategyConfig() external view returns (bytes memory config);

    /// @notice Updates the adoption strategy configuration with new parameters
    /// @dev Should validate configuration before updating and emit configuration change event
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by authorized addresses (typically owner)
    function updateStrategyConfig(bytes calldata newConfig) external;

    /// @notice Gets adoption strategy metadata for identification and versioning
    /// @dev Returns static metadata about the adoption strategy implementation
    /// @return name Strategy implementation name
    /// @return version Semantic version of the strategy
    /// @return description Human-readable description of strategy functionality
    /// @custom:view This function is read-only and returns static metadata
    function getStrategyMetadata()
        external
        pure
        returns (string memory name, string memory version, string memory description);
}
