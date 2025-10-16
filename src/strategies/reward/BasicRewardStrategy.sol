// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// 2. Internal interfaces
import {IRewardStrategy} from "../../interfaces/IRewardStrategy.sol";

// 3. Internal libraries
import {DataTypes} from "../../libraries/DataTypes.sol";

/// @title BasicRewardStrategy
/// @notice Basic reward distribution strategy implementation with configurable percentages
/// @dev This strategy implements simple reward distribution rules including:
///      - Configurable percentage splits between creator, reviewers, and platform
///      - Accuracy-based reviewer bonuses and penalties
///      - Equal distribution among reviewers with accuracy adjustments
///      - Platform fee collection with configurable rates
/// @custom:security Owner-controlled configuration updates
/// @custom:strategy Uses percentage-based distribution with accuracy modifiers
/// @author Hermis Team
contract BasicRewardStrategy is IRewardStrategy, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Encoded configuration data for the reward strategy
    /// @dev Stored as bytes to allow flexible configuration structures
    bytes private _rewardConfig;

    /// @notice Flag indicating whether the strategy has been initialized with configuration
    /// @dev Prevents usage before proper setup and double initialization
    bool private _initialized;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for basic reward distribution strategy
    /// @dev Defines percentage splits and accuracy modifiers for reward calculation
    struct BasicRewardConfig {
        /// @notice Percentage of total reward allocated to the task creator (0-100)
        uint256 creatorPercentage;
        /// @notice Percentage of total reward allocated to reviewers (0-100)
        uint256 reviewerPercentage;
        /// @notice Percentage of total reward allocated to platform (0-100)
        uint256 platformPercentage;
        /// @notice Bonus percentage for accurate reviewers (0-100)
        uint256 accuracyBonus;
        /// @notice Penalty percentage for inaccurate reviewers (0-100)
        uint256 accuracyPenalty;
        /// @notice Minimum reward amount per reviewer (in wei)
        uint256 minReviewerReward;
        /// @notice Maximum reward amount per reviewer (in wei)
        uint256 maxReviewerReward;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyInitialized() {
        if (!_initialized) revert InvalidRewardConfiguration();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the BasicRewardStrategy with owner address
    /// @dev Sets the owner but does not initialize configuration - that must be done separately
    /// @param owner Address that will have administrative control over the strategy
    /// @custom:security Owner has exclusive access to configuration functions
    constructor(address owner) Ownable(owner) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the strategy with initial configuration data
    /// @dev Can only be called once. Validates configuration before storing.
    /// @param initialConfig Initial configuration data encoded as BasicRewardConfig
    /// @custom:security Only callable by owner and only once
    /// @custom:validation Validates configuration parameters before storing
    function initializeRewardStrategy(bytes calldata initialConfig) external onlyOwner {
        if (_initialized) revert InvalidRewardConfiguration();

        _validateConfig(initialConfig);
        _rewardConfig = initialConfig;
        _initialized = true;

        emit RewardStrategyConfigUpdated("", initialConfig);
    }

    /// @notice Updates the reward strategy configuration with new parameters
    /// @dev Validates new configuration before updating. Emits event with old and new config.
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by owner after initialization
    /// @custom:validation Validates new configuration before updating
    function updateRewardConfig(bytes calldata newConfig) external override onlyOwner onlyInitialized {
        _validateConfig(newConfig);

        bytes memory oldConfig = _rewardConfig;
        _rewardConfig = newConfig;

        emit RewardStrategyConfigUpdated(oldConfig, newConfig);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Calculates reward distribution for a completed task based on strategy parameters
    /// @dev Distributes total reward according to configured percentages between creator, reviewers, and platform
    /// @param taskId ID of the task (not used in current implementation)
    /// @param totalReward Total reward amount to distribute among participants
    /// @param adoptedSubmissionId ID of the adopted submission (not used in current implementation)
    /// @param reviewerCount Number of reviewers that participated (not used in current implementation)
    /// @return distribution Reward distribution breakdown with calculated amounts
    /// @custom:view This function is read-only and performs reward calculations
    function calculateRewardDistribution(
        uint256 taskId,
        uint256 totalReward,
        uint256 adoptedSubmissionId,
        uint256 reviewerCount
    ) external view override onlyInitialized returns (DataTypes.RewardDistribution memory distribution) {
        // Parameters preserved for strategies that vary payouts per task or submission.
        taskId;
        adoptedSubmissionId;
        reviewerCount;
        BasicRewardConfig memory config = abi.decode(_rewardConfig, (BasicRewardConfig));

        if (totalReward == 0) {
            revert InsufficientRewardAmount(1, 0);
        }

        // Calculate base allocations according to percentages
        distribution.creatorShare = (totalReward * config.creatorPercentage) / 100;
        distribution.reviewerShare = (totalReward * config.reviewerPercentage) / 100;
        distribution.platformShare = (totalReward * config.platformPercentage) / 100;
        distribution.publisherRefund = 0; // No refund in basic strategy

        // Ensure the sum doesn't exceed total reward due to rounding
        uint256 calculatedTotal = distribution.creatorShare +
            distribution.reviewerShare +
            distribution.platformShare +
            distribution.publisherRefund;

        if (calculatedTotal > totalReward) {
            // Adjust platform share to account for rounding
            distribution.platformShare =
                totalReward -
                distribution.creatorShare -
                distribution.reviewerShare -
                distribution.publisherRefund;
        }

        // Note: Events cannot be emitted from view functions
        // RewardCalculated event should be emitted by the calling contract
    }

    /// @notice Calculates individual reviewer reward with accuracy considerations
    /// @dev Applies accuracy bonuses or penalties and ensures fair distribution among reviewers
    /// @param taskId ID of the task (not used in current implementation)
    /// @param reviewerId Address of the reviewer (not used in current implementation)
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
    ) external view override onlyInitialized returns (uint256 reward) {
        // Parameters kept for advanced reviewer-specific calculations.
        taskId;
        reviewerId;
        BasicRewardConfig memory config = abi.decode(_rewardConfig, (BasicRewardConfig));

        if (reviewerCount == 0) return 0;
        if (totalReviewerReward == 0) return 0;

        // Calculate base reward per reviewer
        uint256 baseReward = totalReviewerReward / reviewerCount;

        // Apply accuracy modifier
        if (reviewAccuracy) {
            // Apply accuracy bonus
            reward = baseReward + (baseReward * config.accuracyBonus) / 100;
        } else {
            // Apply accuracy penalty
            uint256 penalty = (baseReward * config.accuracyPenalty) / 100;
            reward = baseReward > penalty ? baseReward - penalty : 0;
        }

        // Enforce minimum and maximum limits
        if (config.minReviewerReward > 0 && reward < config.minReviewerReward) {
            reward = config.minReviewerReward;
        }
        if (config.maxReviewerReward > 0 && reward > config.maxReviewerReward) {
            reward = config.maxReviewerReward;
        }

        // Ensure total doesn't exceed available amount (simple check)
        if (reward > totalReviewerReward) {
            reward = totalReviewerReward;
        }
    }

    /// @notice Gets the current reward strategy configuration data
    /// @dev Returns raw bytes that must be decoded as BasicRewardConfig
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getRewardConfig() external view override returns (bytes memory config) {
        return _rewardConfig;
    }

    /// @notice Gets the decoded reward strategy configuration
    /// @dev Decodes the raw bytes configuration into BasicRewardConfig struct
    /// @return config Current reward strategy configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getBasicRewardConfig() external view returns (BasicRewardConfig memory config) {
        if (_rewardConfig.length > 0) {
            config = abi.decode(_rewardConfig, (BasicRewardConfig));
        }
    }

    /// @notice Gets reward strategy metadata for identification and versioning
    /// @dev Returns static metadata about this reward strategy implementation
    /// @return name Strategy implementation name
    /// @return version Semantic version of the strategy
    /// @return description Human-readable description of strategy functionality
    /// @custom:view This function is read-only and returns static metadata
    function getRewardMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return (
            "BasicRewardStrategy",
            "1.0.0",
            "Basic percentage-based reward distribution strategy with accuracy bonuses and penalties"
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

    /// @notice Validates reward strategy configuration parameters
    /// @dev Ensures percentages sum to 100 and all parameters are within valid ranges
    /// @param config Encoded BasicRewardConfig to validate
    /// @custom:validation Reverts if configuration is invalid
    function _validateConfig(bytes calldata config) internal pure {
        if (config.length == 0) revert InvalidRewardConfiguration();

        BasicRewardConfig memory rewardConfig = abi.decode(config, (BasicRewardConfig));

        // Validate that percentages sum to 100
        if (rewardConfig.creatorPercentage + rewardConfig.reviewerPercentage + rewardConfig.platformPercentage != 100) {
            revert InvalidRewardConfiguration();
        }

        // Validate individual percentages are within bounds
        if (
            rewardConfig.creatorPercentage > 100 ||
            rewardConfig.reviewerPercentage > 100 ||
            rewardConfig.platformPercentage > 100
        ) {
            revert InvalidRewardConfiguration();
        }

        // Validate accuracy modifiers are reasonable
        if (rewardConfig.accuracyBonus > 100 || rewardConfig.accuracyPenalty > 100) {
            revert InvalidRewardConfiguration();
        }

        // Validate min/max reward constraints
        if (rewardConfig.maxReviewerReward > 0 && rewardConfig.minReviewerReward > rewardConfig.maxReviewerReward) {
            revert InvalidRewardConfiguration();
        }
    }
}
