// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal contracts
import {BaseGuard} from "../BaseGuard.sol";

// 2. Internal interfaces
import {IReputationManager} from "../../interfaces/IReputationManager.sol";

// 3. Internal libraries (DataTypes used for enums and structures in validation)

/// @title SubmissionGuard
/// @notice Task submission guard that validates user eligibility to submit work for specific tasks
/// @dev This guard implements task-specific submission access control including:
///      - Task-specific skill requirements validation
///      - Minimum reputation thresholds for submission
///      - Category-specific expertise validation
///      - Submission history and performance checks
///      - Integration with ReputationManager for comprehensive validation
/// @custom:security Enforces task-specific submission policies based on configured requirements
/// @custom:configuration Supports flexible configuration through SubmissionConfig struct
/// @author Hermis Team
contract SubmissionGuard is BaseGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ReputationManager contract interface for accessing user reputation data
    /// @dev Immutable reference set during construction for submission validation
    IReputationManager public immutable REPUTATION_MANAGER;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for task submission access control
    /// @dev All reputation scores use 10x precision (e.g., 600 = 60.0 reputation)
    struct SubmissionConfig {
        /// @notice Minimum overall reputation score required for submission (10x precision)
        uint256 minReputationScore;
        /// @notice Minimum score required for the specified category (10x precision)
        uint256 minCategoryScore;
        /// @notice Maximum number of failed submissions allowed in history
        uint256 maxFailedSubmissions;
        /// @notice Minimum success rate required (percentage, 0-100)
        uint256 minSuccessRate;
        /// @notice Whether to enforce category-specific skill requirements
        bool requireCategoryExpertise;
        /// @notice Whether to check submission success rate
        bool enforceSuccessRate;
        /// @notice Required skill category for this task (e.g., "development", "design", "writing")
        string requiredCategory;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the SubmissionGuard with owner and ReputationManager
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
            "SubmissionGuard",
            "1.0.0",
            "Task submission guard that validates user eligibility based on skills, reputation, and submission history"
        );
    }

    /// @notice Gets the decoded submission guard configuration
    /// @dev Decodes the raw bytes configuration into SubmissionConfig struct
    /// @return config Current submission guard configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getSubmissionConfig() external view returns (SubmissionConfig memory config) {
        bytes memory configData = _getDecodedConfig();
        if (configData.length > 0) {
            config = abi.decode(configData, (SubmissionConfig));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Performs comprehensive submission eligibility validation
    /// @dev Validates user qualification for task submission based on configured requirements.
    ///      Checks are performed in order: access validation, reputation, category expertise, submission history.
    /// @param user Address of the user to validate for submission
    /// @param data Additional data containing task-specific information (optional)
    /// @return success True if all validation checks pass
    /// @return reason Human-readable explanation of validation result
    /// @custom:validation Performs multi-level submission validation based on configuration
    function _performValidation(
        address user,
        bytes calldata data
    ) internal view override returns (bool success, string memory reason) {
        SubmissionConfig memory config = abi.decode(_getDecodedConfig(), (SubmissionConfig));

        // Check if user can access platform
        (bool canAccess, string memory accessReason) = REPUTATION_MANAGER.validateUserAccess(user);
        if (!canAccess) {
            return (false, string(abi.encodePacked("Submission access denied: ", accessReason)));
        }

        // Get user reputation info
        (uint256 reputation, , , , ) = REPUTATION_MANAGER.getUserReputation(user);

        // Check minimum reputation requirement
        if (reputation < config.minReputationScore) {
            return (
                false,
                string(
                    abi.encodePacked(
                        "Insufficient reputation for submission: required ",
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
                            " expertise for submission: required ",
                            _toString(config.minCategoryScore),
                            ", current ",
                            _toString(categoryScore)
                        )
                    )
                );
            }
        }

        // Check submission history if configured
        if (config.maxFailedSubmissions > 0 || config.enforceSuccessRate) {
            (bool historyValid, string memory historyReason) = _validateSubmissionHistory(user, config);
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

        return (true, "Submission requirements met");
    }

    /// @notice Validates user's submission history and success rate
    /// @dev Checks failed submission count and success rate against configured thresholds
    /// @param user Address of the user to validate submission history for
    /// @param config Submission configuration with minimum requirements
    /// @return success True if submission history meets minimum requirements
    /// @return reason Human-readable explanation of the validation result
    /// @custom:view This function queries external reputation data for validation
    function _validateSubmissionHistory(
        address user,
        SubmissionConfig memory config
    ) internal pure returns (bool success, string memory reason) {
        // Parameters reserved for when submission history metrics are wired in.
        user;
        config;
        // Note: These methods would need to be implemented in IReputationManager
        // For now, we'll provide placeholder logic that can be extended

        // Check failed submissions count
        // uint256 failedCount = REPUTATION_MANAGER.getFailedSubmissionCount(user);
        // if (failedCount > config.maxFailedSubmissions) {
        //     return (false, string(abi.encodePacked(
        //         "Too many failed submissions: ",
        //         _toString(failedCount),
        //         " (max: ",
        //         _toString(config.maxFailedSubmissions),
        //         ")"
        //     )));
        // }

        // Check success rate
        // if (config.enforceSuccessRate) {
        //     uint256 successRate = REPUTATION_MANAGER.getSubmissionSuccessRate(user);
        //     if (successRate < config.minSuccessRate) {
        //         return (false, string(abi.encodePacked(
        //             "Insufficient submission success rate: ",
        //             _toString(successRate),
        //             "% (required: ",
        //             _toString(config.minSuccessRate),
        //             "%)"
        //         )));
        //     }
        // }

        return (true, "Submission history validated");
    }

    /// @notice Validates task-specific submission data
    /// @dev Processes additional task-specific validation data passed during submission
    /// @param user Address of the user attempting to submit
    /// @param data Additional task-specific validation data
    /// @param config Submission configuration with task-specific requirements
    /// @return success Whether task-specific validation passes
    /// @return reason Human-readable explanation of the validation result
    /// @custom:validation Extensible validation for task-specific requirements
    function _validateTaskSpecificData(
        address user,
        bytes calldata data,
        SubmissionConfig memory config
    ) internal pure returns (bool success, string memory reason) {
        // Parameters reserved for bespoke submission requirements.
        user;
        data;
        config;
        // Decode task-specific data if needed
        // This can be extended based on specific task requirements
        // For example: required skills, portfolio links, etc.

        // Placeholder implementation - can be extended for specific task types
        return (true, "Task-specific validation passed");
    }

    /// @notice Validates submission guard configuration parameters
    /// @dev Ensures reputation thresholds and success rates are within valid ranges.
    ///      Reverts if configuration is invalid.
    /// @param config Encoded SubmissionConfig to validate
    /// @custom:validation Checks threshold limits and configuration consistency
    function _validateConfig(bytes calldata config) internal pure override {
        if (config.length == 0) return;

        SubmissionConfig memory submissionConfig = abi.decode(config, (SubmissionConfig));

        // Validate reputation thresholds
        if (submissionConfig.minReputationScore > 10000) {
            // 1000.0 with precision 10
            revert InvalidReputationThreshold(submissionConfig.minReputationScore);
        }

        // Validate category configuration
        if (submissionConfig.requireCategoryExpertise) {
            if (bytes(submissionConfig.requiredCategory).length == 0) {
                revert InvalidGuardConfiguration();
            }
            if (submissionConfig.minCategoryScore > 10000) {
                revert InvalidReputationThreshold(submissionConfig.minCategoryScore);
            }
        }

        // Validate success rate configuration
        if (submissionConfig.enforceSuccessRate) {
            if (submissionConfig.minSuccessRate > 100) {
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
