// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal contracts
import {BaseGuard} from "../BaseGuard.sol";

// 2. Internal interfaces
import {IReputationManager} from "../../interfaces/IReputationManager.sol";

// 3. Internal libraries (DataTypes used for enums and structures in validation)

/// @title ReviewGuard
/// @notice Task review guard that validates user eligibility to review submissions for specific tasks
/// @dev This guard implements task-specific review access control including:
///      - Review-specific skill requirements validation
///      - Minimum reputation thresholds for reviewers
///      - Category-specific expertise validation
///      - Review history and performance checks
///      - Integration with ReputationManager for comprehensive validation
/// @custom:security Enforces task-specific review policies based on configured requirements
/// @custom:configuration Supports flexible configuration through ReviewConfig struct
/// @author Hermis Team
contract ReviewGuard is BaseGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ReputationManager contract interface for accessing user reputation data
    /// @dev Immutable reference set during construction for review validation
    IReputationManager public immutable REPUTATION_MANAGER;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for task review access control
    /// @dev All reputation scores use 10x precision (e.g., 600 = 60.0 reputation)
    struct ReviewConfig {
        /// @notice Minimum overall reputation score required for review (10x precision)
        uint256 minReputationScore;
        /// @notice Minimum score required for the specified category (10x precision)
        uint256 minCategoryScore;
        /// @notice Minimum number of successful reviews required in history
        uint256 minReviewCount;
        /// @notice Minimum review accuracy rate required (percentage, 0-100)
        uint256 minAccuracyRate;
        /// @notice Whether to enforce category-specific expertise requirements
        bool requireCategoryExpertise;
        /// @notice Whether to check review accuracy rate
        bool enforceAccuracyRate;
        /// @notice Required expertise category for this task (e.g., "development", "design", "writing")
        string requiredCategory;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the ReviewGuard with owner and ReputationManager
    /// @dev Sets up the guard with required dependencies. Configuration must be set separately.
    /// @param owner Address that will have administrative control over the guard
    /// @param _reputationManager Address of the ReputationManager contract
    /// @custom:security Validates ReputationManager address is not zero
    constructor(address owner, address _reputationManager) BaseGuard(owner) {
        if (_reputationManager == address(0)) revert ReputationManagerNotSet();
        REPUTATION_MANAGER = IReputationManager(_reputationManager);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets guard metadata for identification and versioning
    /// @dev Returns static metadata about this guard implementation
    /// @return name Guard implementation name
    /// @return version Semantic version of the guard
    /// @return description Human-readable description of guard functionality
    /// @custom:view This function is read-only and returns static metadata
    function getGuardMetadata()
        external
        pure
        override
        returns (string memory name, string memory version, string memory description)
    {
        return (
            "ReviewGuard",
            "1.0.0",
            "Task review guard that validates user eligibility based on expertise, reputation, and review history"
        );
    }

    /// @notice Gets the decoded review guard configuration
    /// @dev Decodes the raw bytes configuration into ReviewConfig struct
    /// @return config Current review guard configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getReviewConfig() external view returns (ReviewConfig memory config) {
        bytes memory configData = _getDecodedConfig();
        if (configData.length > 0) {
            config = abi.decode(configData, (ReviewConfig));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Performs comprehensive review eligibility validation
    /// @dev Validates user qualification for task review based on configured requirements.
    ///      Checks are performed in order: access validation, reputation, category expertise, review history.
    /// @param user Address of the user to validate for review
    /// @param data Additional data containing task-specific information (optional)
    /// @return success True if all validation checks pass
    /// @return reason Human-readable explanation of validation result
    /// @custom:validation Performs multi-level review validation based on configuration
    function _performValidation(
        address user,
        bytes calldata data
    ) internal view override returns (bool success, string memory reason) {
        ReviewConfig memory config = abi.decode(_getDecodedConfig(), (ReviewConfig));

        // Check if user can access platform
        (bool canAccess, string memory accessReason) = REPUTATION_MANAGER.validateUserAccess(user);
        if (!canAccess) {
            return (false, string(abi.encodePacked("Review access denied: ", accessReason)));
        }

        // Get user reputation info
        (uint256 reputation, , , , ) = REPUTATION_MANAGER.getUserReputation(user);

        // Check minimum reputation requirement
        if (reputation < config.minReputationScore) {
            return (
                false,
                string(
                    abi.encodePacked(
                        "Insufficient reputation for review: required ",
                        _toString(config.minReputationScore),
                        ", current ",
                        _toString(reputation)
                    )
                )
            );
        }

        // Check category expertise requirement if enabled
        if (config.requireCategoryExpertise) {
            uint256 categoryScore = REPUTATION_MANAGER.getCategoryScore(user, config.requiredCategory);
            if (categoryScore < config.minCategoryScore) {
                return (
                    false,
                    string(
                        abi.encodePacked(
                            "Insufficient ",
                            config.requiredCategory,
                            " expertise for review: required ",
                            _toString(config.minCategoryScore),
                            ", current ",
                            _toString(categoryScore)
                        )
                    )
                );
            }
        }

        // Check review history if configured
        if (config.minReviewCount > 0 || config.enforceAccuracyRate) {
            (bool historyValid, string memory historyReason) = _validateReviewHistory(user, config);
            if (!historyValid) {
                return (false, historyReason);
            }
        }

        // Parse and validate task-specific data if provided
        if (data.length > 0) {
            (bool taskDataValid, string memory taskReason) = _validateTaskSpecificData(user, data, config);
            if (!taskDataValid) {
                return (false, taskReason);
            }
        }

        return (true, "Review requirements met");
    }

    /// @notice Validates user's review history and accuracy rate
    /// @dev Checks review count and accuracy rate against configured thresholds
    /// @param user Address of the user to validate review history for
    /// @param config Review configuration with minimum requirements
    /// @return success True if review history meets minimum requirements
    /// @return reason Human-readable explanation of the validation result
    /// @custom:view This function queries external reputation data for validation
    function _validateReviewHistory(
        address user,
        ReviewConfig memory config
    ) internal pure returns (bool success, string memory reason) {
        // Parameters reserved for when historical stats are integrated.
        user;
        config;
        // Note: These methods would need to be implemented in IReputationManager
        // For now, we'll provide placeholder logic that can be extended

        // Check review count
        // uint256 reviewCount = REPUTATION_MANAGER.getReviewCount(user);
        // if (reviewCount < config.minReviewCount) {
        //     return (false, string(abi.encodePacked(
        //         "Insufficient review history: ",
        //         _toString(reviewCount),
        //         " reviews (required: ",
        //         _toString(config.minReviewCount),
        //         ")"
        //     )));
        // }

        // Check accuracy rate
        // if (config.enforceAccuracyRate) {
        //     uint256 accuracyRate = REPUTATION_MANAGER.getReviewAccuracyRate(user);
        //     if (accuracyRate < config.minAccuracyRate) {
        //         return (false, string(abi.encodePacked(
        //             "Insufficient review accuracy rate: ",
        //             _toString(accuracyRate),
        //             "% (required: ",
        //             _toString(config.minAccuracyRate),
        //             "%)"
        //         )));
        //     }
        // }

        return (true, "Review history validated");
    }

    /// @notice Validates task-specific review data
    /// @dev Processes additional task-specific validation data passed during review
    /// @param user Address of the user attempting to review
    /// @param data Additional task-specific validation data
    /// @param config Review configuration with task-specific requirements
    /// @return success Whether task-specific validation passes
    /// @return reason Human-readable explanation of the validation result
    /// @custom:validation Extensible validation for task-specific review requirements
    function _validateTaskSpecificData(
        address user,
        bytes calldata data,
        ReviewConfig memory config
    ) internal pure returns (bool success, string memory reason) {
        // Parameters reserved for task-specific review extensions.
        user;
        data;
        config;
        // Decode task-specific data if needed
        // This can be extended based on specific task requirements
        // For example: required certifications, conflict of interest checks, etc.

        // Placeholder implementation - can be extended for specific task types
        return (true, "Task-specific review validation passed");
    }

    /// @notice Validates review guard configuration parameters
    /// @dev Ensures reputation thresholds and accuracy rates are within valid ranges.
    ///      Reverts if configuration is invalid.
    /// @param config Encoded ReviewConfig to validate
    /// @custom:validation Checks threshold limits and configuration consistency
    function _validateConfig(bytes calldata config) internal pure override {
        if (config.length == 0) return;

        ReviewConfig memory reviewConfig = abi.decode(config, (ReviewConfig));

        // Validate reputation thresholds
        if (reviewConfig.minReputationScore > 10000) {
            // 1000.0 with precision 10
            revert InvalidReputationThreshold(reviewConfig.minReputationScore);
        }

        // Validate category configuration
        if (reviewConfig.requireCategoryExpertise) {
            if (bytes(reviewConfig.requiredCategory).length == 0) {
                revert InvalidGuardConfiguration();
            }
            if (reviewConfig.minCategoryScore > 10000) {
                revert InvalidReputationThreshold(reviewConfig.minCategoryScore);
            }
        }

        // Validate accuracy rate configuration
        if (reviewConfig.enforceAccuracyRate) {
            if (reviewConfig.minAccuracyRate > 100) {
                revert InvalidGuardConfiguration();
            }
        }
    }

    /// @notice Utility function to convert uint256 to string representation
    /// @dev Used for constructing human-readable error messages with numeric values
    /// @param value Numeric value to convert to string
    /// @return result String representation of the input value
    /// @custom:pure This function is pure and performs numeric conversion
    function _toString(uint256 value) internal pure returns (string memory result) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
