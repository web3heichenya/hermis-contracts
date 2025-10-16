// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// 2. Internal interfaces
import {IAdoptionStrategy} from "../../interfaces/IAdoptionStrategy.sol";

// 3. Internal libraries
import {DataTypes} from "../../libraries/DataTypes.sol";

/// @title SimpleAdoptionStrategy
/// @notice Simple adoption strategy implementation that uses majority voting and time thresholds
/// @dev This strategy implements basic adoption rules including:
///      - Majority-based approval/rejection thresholds
///      - Time-based automatic status changes
///      - Configurable review requirements
///      - Simple completion criteria based on adoption status
/// @custom:security Owner-controlled configuration updates
/// @custom:strategy Uses simple majority voting with configurable thresholds
/// @author Hermis Team
contract SimpleAdoptionStrategy is IAdoptionStrategy, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Encoded configuration data for the adoption strategy
    /// @dev Stored as bytes to allow flexible configuration structures
    bytes private _strategyConfig;

    /// @notice Flag indicating whether the strategy has been initialized with configuration
    /// @dev Prevents usage before proper setup and double initialization
    bool private _initialized;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for simple adoption strategy
    /// @dev Defines thresholds and timeouts for adoption decisions
    struct SimpleAdoptionConfig {
        /// @notice Minimum number of reviews required before adoption decision can be made
        uint256 minReviewsRequired;
        /// @notice Percentage threshold for approval (0-100, e.g., 60 = 60%)
        uint256 approvalThreshold;
        /// @notice Percentage threshold for rejection (0-100, e.g., 60 = 60%)
        uint256 rejectionThreshold;
        /// @notice Time in seconds after which submission expires if no decision
        uint256 expirationTime;
        /// @notice Whether to allow automatic adoption based on time alone
        bool allowTimeBasedAdoption;
        /// @notice Time in seconds for automatic adoption if no reviews received
        uint256 autoAdoptionTime;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyInitialized() {
        if (!_initialized) revert InvalidStrategyConfiguration();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the SimpleAdoptionStrategy with owner address
    /// @dev Sets the owner but does not initialize configuration - that must be done separately
    /// @param owner Address that will have administrative control over the strategy
    /// @custom:security Owner has exclusive access to configuration functions
    constructor(address owner) Ownable(owner) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the strategy with initial configuration data
    /// @dev Can only be called once. Validates configuration before storing.
    /// @param initialConfig Initial configuration data encoded as SimpleAdoptionConfig
    /// @custom:security Only callable by owner and only once
    /// @custom:validation Validates configuration parameters before storing
    function initializeStrategy(bytes calldata initialConfig) external onlyOwner {
        if (_initialized) revert InvalidStrategyConfiguration();

        _validateConfig(initialConfig);
        _strategyConfig = initialConfig;
        _initialized = true;

        emit StrategyConfigurationUpdated("", initialConfig);
    }

    /// @notice Updates the adoption strategy configuration with new parameters
    /// @dev Validates new configuration before updating. Emits event with old and new config.
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by owner after initialization
    /// @custom:validation Validates new configuration before updating
    function updateStrategyConfig(bytes calldata newConfig) external override onlyOwner onlyInitialized {
        _validateConfig(newConfig);

        bytes memory oldConfig = _strategyConfig;
        _strategyConfig = newConfig;

        emit StrategyConfigurationUpdated(oldConfig, newConfig);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Evaluates whether a submission should change status based on reviews and timing
    /// @dev Implements simple majority voting with configurable thresholds and time limits
    /// @param submissionId ID of the submission being evaluated (not used in current logic)
    /// @param approveCount Total number of positive reviews received
    /// @param rejectCount Total number of negative reviews received
    /// @param totalReviews Total number of reviews submitted
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
    )
        external
        view
        override
        onlyInitialized
        returns (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason)
    {
        // Parameters currently unused but preserved for future per-submission configuration.
        submissionId;

        SimpleAdoptionConfig memory config = abi.decode(_strategyConfig, (SimpleAdoptionConfig));

        // Check for time-based expiration first
        if (timeSinceSubmission >= config.expirationTime) {
            return (DataTypes.SubmissionStatus.REMOVED, true, "Submission expired due to timeout");
        }

        // Check for automatic adoption based on time (if no reviews and enabled)
        if (config.allowTimeBasedAdoption && totalReviews == 0 && timeSinceSubmission >= config.autoAdoptionTime) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Auto-adopted due to no reviews within time limit");
        }

        // If we don't have minimum reviews, no status change
        if (totalReviews < config.minReviewsRequired) {
            return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "Insufficient reviews for decision");
        }

        // Calculate approval and rejection percentages
        uint256 approvalPercentage = (approveCount * 100) / totalReviews;
        uint256 rejectionPercentage = (rejectCount * 100) / totalReviews;

        // Check for adoption threshold
        if (approvalPercentage >= config.approvalThreshold) {
            return (DataTypes.SubmissionStatus.ADOPTED, true, "Submission meets approval threshold");
        }

        // Check for rejection threshold
        if (rejectionPercentage >= config.rejectionThreshold) {
            return (DataTypes.SubmissionStatus.REMOVED, true, "Submission meets rejection threshold");
        }

        // No threshold met, keep under review
        return (DataTypes.SubmissionStatus.UNDER_REVIEW, false, "No adoption threshold reached");
    }

    /// @notice Determines whether a task should be marked as completed based on adoption criteria
    /// @dev Simple implementation: task is complete if it has at least one adopted submission
    /// @param taskId ID of the task being evaluated (not used in current logic)
    /// @param adoptedSubmissionId ID of the submission that was adopted for the task
    /// @return shouldComplete Whether the task meets criteria to be marked as completed
    /// @custom:view This function is read-only and performs completion evaluation
    function shouldCompleteTask(
        uint256 taskId,
        uint256 adoptedSubmissionId
    ) external view override onlyInitialized returns (bool shouldComplete) {
        // Task ID is reserved for strategies that depend on task-level thresholds.
        taskId;
        // Simple strategy: task is complete if there's an adopted submission
        // More complex strategies could check adoption quality, multiple adoptions, etc.
        return adoptedSubmissionId > 0;
    }

    /// @notice Gets the current adoption strategy configuration data
    /// @dev Returns raw bytes that must be decoded as SimpleAdoptionConfig
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getStrategyConfig() external view override returns (bytes memory config) {
        return _strategyConfig;
    }

    /// @notice Gets the decoded adoption strategy configuration
    /// @dev Decodes the raw bytes configuration into SimpleAdoptionConfig struct
    /// @return config Current adoption strategy configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getSimpleAdoptionConfig() external view returns (SimpleAdoptionConfig memory config) {
        if (_strategyConfig.length > 0) {
            config = abi.decode(_strategyConfig, (SimpleAdoptionConfig));
        }
    }

    /// @notice Gets adoption strategy metadata for identification and versioning
    /// @dev Returns static metadata about this adoption strategy implementation
    /// @return name Strategy implementation name
    /// @return version Semantic version of the strategy
    /// @return description Human-readable description of strategy functionality
    /// @custom:view This function is read-only and returns static metadata
    function getStrategyMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return (
            "SimpleAdoptionStrategy",
            "1.0.0",
            "Simple majority-based adoption strategy with configurable thresholds and time limits"
        );
    }

    /// @notice Checks if the strategy has been initialized with configuration
    /// @dev Used to ensure strategy is properly set up before use
    /// @return initialized True if strategy has been initialized, false otherwise
    /// @custom:view This function is read-only and provides initialization status
    function isInitialized() external view returns (bool initialized) {
        return _initialized;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates adoption strategy configuration parameters
    /// @dev Ensures thresholds are within valid ranges and configuration is consistent
    /// @param config Encoded SimpleAdoptionConfig to validate
    /// @custom:validation Reverts if configuration is invalid
    function _validateConfig(bytes calldata config) internal pure {
        if (config.length == 0) revert InvalidStrategyConfiguration();

        SimpleAdoptionConfig memory adoptionConfig = abi.decode(config, (SimpleAdoptionConfig));

        // Validate thresholds are within 0-100 range
        if (adoptionConfig.approvalThreshold > 100) {
            revert InvalidStrategyConfiguration();
        }
        if (adoptionConfig.rejectionThreshold > 100) {
            revert InvalidStrategyConfiguration();
        }

        // Ensure thresholds don't overlap (would create conflicting decisions)
        if (adoptionConfig.approvalThreshold + adoptionConfig.rejectionThreshold > 100) {
            revert InvalidStrategyConfiguration();
        }

        // Validate minimum reviews is reasonable (at least 1)
        if (adoptionConfig.minReviewsRequired == 0) {
            revert InvalidStrategyConfiguration();
        }

        // Validate time parameters are reasonable
        if (adoptionConfig.expirationTime == 0) {
            revert InvalidStrategyConfiguration();
        }

        // If auto-adoption is enabled, auto-adoption time should be less than expiration time
        if (adoptionConfig.allowTimeBasedAdoption && adoptionConfig.autoAdoptionTime >= adoptionConfig.expirationTime) {
            revert InvalidStrategyConfiguration();
        }
    }
}
