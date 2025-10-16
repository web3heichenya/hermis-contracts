// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal contracts
import {BaseGuard} from "../BaseGuard.sol";

// 2. Internal interfaces
import {IReputationManager} from "../../interfaces/IReputationManager.sol";

/// @title ReputationGuard
/// @notice Reputation-based guard that validates users based on minimum score requirements
/// @dev This guard implements reputation-based access control including:
///      - Minimum overall reputation score validation
///      - Optional category-specific score requirements
///      - Integration with ReputationManager for real-time reputation checks
///      - Configurable thresholds for both global and category-specific reputation
///      - Support for category-based specialization validation
/// @custom:security Enforces reputation-based access policies with configurable thresholds
/// @custom:configuration Supports flexible configuration through ReputationConfig struct
/// @author Hermis Team
contract ReputationGuard is BaseGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ReputationManager contract interface for accessing user reputation data
    /// @dev Immutable reference set during construction for reputation score validation
    IReputationManager public immutable REPUTATION_MANAGER;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for reputation-based access control
    /// @dev All reputation scores use 10x precision (e.g., 600 = 60.0 reputation)
    struct ReputationConfig {
        /// @notice Minimum overall reputation score required for access (10x precision)
        uint256 minReputationScore;
        /// @notice Whether to enforce category-specific score requirements
        bool requireCategoryScore;
        /// @notice Category name for specialized score validation (e.g., "development", "design")
        string requiredCategory;
        /// @notice Minimum score required for the specified category (10x precision)
        uint256 minCategoryScore;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the ReputationGuard with owner and ReputationManager
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
            "ReputationGuard",
            "1.0.0",
            "Reputation-based guard that validates users based on minimum score requirements and optional category specialization"
        );
    }

    /// @notice Gets the decoded reputation guard configuration
    /// @dev Decodes the raw bytes configuration into ReputationConfig struct
    /// @return config Current reputation guard configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getReputationConfig() external view returns (ReputationConfig memory config) {
        bytes memory configData = _getDecodedConfig();
        if (configData.length > 0) {
            config = abi.decode(configData, (ReputationConfig));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Performs comprehensive reputation-based validation
    /// @dev Validates user reputation against configured minimum thresholds.
    ///      Checks are performed in order: access validation, overall reputation, category-specific score.
    /// @param user Address of the user to validate
    /// @param data Additional validation data (not used in current implementation)
    /// @return success True if all validation checks pass
    /// @return reason Human-readable explanation of validation result
    /// @custom:validation Performs multi-level reputation validation based on configuration
    function _performValidation(
        address user,
        bytes calldata data
    ) internal view override returns (bool success, string memory reason) {
        // Additional validation data is reserved for future extensions.
        data;
        ReputationConfig memory config = abi.decode(_getDecodedConfig(), (ReputationConfig));

        // Check if user can access platform
        (bool canAccess, string memory accessReason) = REPUTATION_MANAGER.validateUserAccess(user);
        if (!canAccess) {
            return (false, string(abi.encodePacked("Access denied: ", accessReason)));
        }

        // Get user reputation info
        (uint256 reputation, , , , ) = REPUTATION_MANAGER.getUserReputation(user);

        // Check minimum reputation requirement
        if (reputation < config.minReputationScore) {
            return (
                false,
                string(
                    abi.encodePacked(
                        "Insufficient reputation: required ",
                        _toString(config.minReputationScore),
                        ", current ",
                        _toString(reputation)
                    )
                )
            );
        }

        // Check category score requirement if enabled
        if (config.requireCategoryScore) {
            uint256 categoryScore = REPUTATION_MANAGER.getCategoryScore(user, config.requiredCategory);
            if (categoryScore < config.minCategoryScore) {
                return (
                    false,
                    string(
                        abi.encodePacked(
                            "Insufficient ",
                            config.requiredCategory,
                            " category score: required ",
                            _toString(config.minCategoryScore),
                            ", current ",
                            _toString(categoryScore)
                        )
                    )
                );
            }
        }

        return (true, "Reputation requirements met");
    }

    /// @notice Validates reputation guard configuration parameters
    /// @dev Ensures reputation thresholds are within valid ranges and category requirements are properly set.
    ///      Reverts if configuration is invalid.
    /// @param config Encoded ReputationConfig to validate
    /// @custom:validation Checks threshold limits and category configuration consistency
    function _validateConfig(bytes calldata config) internal pure override {
        if (config.length == 0) return;

        ReputationConfig memory repConfig = abi.decode(config, (ReputationConfig));

        if (repConfig.minReputationScore > 10000) {
            // 1000.0 with precision 10
            revert InvalidReputationThreshold(repConfig.minReputationScore);
        }

        if (repConfig.requireCategoryScore) {
            if (bytes(repConfig.requiredCategory).length == 0) {
                revert InvalidGuardConfiguration();
            }
            if (repConfig.minCategoryScore > 10000) {
                revert InvalidReputationThreshold(repConfig.minCategoryScore);
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
