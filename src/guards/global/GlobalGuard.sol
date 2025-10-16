// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal contracts
import {BaseGuard} from "../BaseGuard.sol";

// 2. Internal interfaces
import {IReputationManager} from "../../interfaces/IReputationManager.sol";

// 3. Internal libraries
import {DataTypes} from "../../libraries/DataTypes.sol";

/// @title GlobalGuard
/// @notice Global platform guard that validates user access based on reputation and staking requirements
/// @dev This guard implements platform-wide access control including:
///      - Reputation-based user status validation (NORMAL/AT_RISK/BLACKLISTED)
///      - Stake requirement enforcement for at-risk users
///      - Action-specific permission checks based on user status
///      - Configurable thresholds for reputation and staking
///      - Integration with ReputationManager for real-time status checks
/// @custom:security Enforces platform-wide access policies based on reputation
/// @custom:configuration Supports flexible configuration through GlobalGuardConfig struct
/// @author Hermis Team
contract GlobalGuard is BaseGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ReputationManager contract interface for accessing user reputation data
    /// @dev Used to validate user status and staking requirements
    IReputationManager public reputationManager;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration structure for global access control parameters
    /// @dev All reputation values use 10x precision (e.g., 600 = 60.0)
    struct GlobalGuardConfig {
        /// @notice Minimum reputation required for normal status (10x precision)
        uint256 minReputationForNormal;
        /// @notice Reputation threshold below which users are considered at-risk (10x precision)
        uint256 atRiskThreshold;
        /// @notice Base stake amount required for at-risk users (in wei)
        uint256 baseStakeAmount;
        /// @notice Whether to enforce staking requirements for at-risk users
        bool enforceStakeForAtRisk;
        /// @notice Whether to allow blacklisted users to perform any actions
        bool allowBlacklistedUsers;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the GlobalGuard with owner and ReputationManager
    /// @dev Sets up the guard with initial dependencies. Configuration must be set separately.
    /// @param owner Address that will have administrative control over the guard
    /// @param _reputationManager Address of the ReputationManager contract
    /// @custom:security Validates ReputationManager address is not zero
    constructor(address owner, address _reputationManager) BaseGuard(owner) {
        if (_reputationManager == address(0)) revert ReputationManagerNotSet();
        reputationManager = IReputationManager(_reputationManager);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the ReputationManager contract address
    /// @dev Allows updating the reputation source for validation checks
    /// @param newReputationManager New ReputationManager contract address
    /// @custom:security Only callable by owner, validates address is not zero
    function updateReputationManager(address newReputationManager) external onlyOwner {
        if (newReputationManager == address(0)) revert ReputationManagerNotSet();
        reputationManager = IReputationManager(newReputationManager);
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
            "GlobalGuard",
            "1.0.0",
            "Platform-wide guard that validates user access based on reputation status and staking requirements"
        );
    }

    /// @notice Gets the decoded global guard configuration
    /// @dev Decodes the raw bytes configuration into GlobalGuardConfig struct
    /// @return config Current global guard configuration parameters
    /// @custom:view This function is read-only and returns decoded configuration
    function getGlobalGuardConfig() external view returns (GlobalGuardConfig memory config) {
        bytes memory configData = _getDecodedConfig();
        if (configData.length > 0) {
            config = abi.decode(configData, (GlobalGuardConfig));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Performs comprehensive global platform validation
    /// @dev Validates user status, staking requirements, and action permissions.
    ///      Checks are performed in order: initialization, blacklist, at-risk stake, action-specific.
    /// @param user Address of the user to validate
    /// @param data Additional data containing action type encoded as string
    /// @return success True if all validation checks pass
    /// @return reason Human-readable explanation of validation result
    /// @custom:validation Performs multi-level validation based on configuration
    function _performValidation(
        address user,
        bytes calldata data
    ) internal view override returns (bool success, string memory reason) {
        GlobalGuardConfig memory config = abi.decode(_getDecodedConfig(), (GlobalGuardConfig));

        // Get user reputation info
        (uint256 reputation, DataTypes.UserStatus status, uint256 stakedAmount, , ) = reputationManager
            .getUserReputation(user);

        // Handle uninitialized users
        if (status == DataTypes.UserStatus.UNINITIALIZED) {
            return (false, "User not initialized");
        }

        // Handle blacklisted users
        if (status == DataTypes.UserStatus.BLACKLISTED) {
            if (!config.allowBlacklistedUsers) {
                return (false, "User is blacklisted");
            }
        }

        // Handle at-risk users
        if (status == DataTypes.UserStatus.AT_RISK) {
            if (config.enforceStakeForAtRisk) {
                uint256 requiredStake = reputationManager.getRequiredStakeAmount(user);
                if (stakedAmount < requiredStake) {
                    return (
                        false,
                        string(
                            abi.encodePacked(
                                "Insufficient stake for at-risk user: required ",
                                _toString(requiredStake),
                                ", current ",
                                _toString(stakedAmount)
                            )
                        )
                    );
                }
            }
        }

        // Decode action type for specific validations
        string memory action;
        if (data.length > 0) {
            action = abi.decode(data, (string));
        }

        // Perform action-specific validation
        if (bytes(action).length > 0) {
            (bool actionValid, string memory actionReason) = _validateAction(user, action, reputation, status);
            if (!actionValid) {
                return (false, actionReason);
            }
        }

        return (true, "Global access requirements met");
    }

    /// @notice Validates specific actions based on user status and reputation
    /// @dev Implements action-specific permission rules. High-risk actions require normal status.
    ///      Arbitration requires minimum reputation threshold.
    /// @param user User address performing the action (not used in current logic)
    /// @param action Action identifier string (e.g., "PUBLISH_TASK", "SUBMIT_WORK")
    /// @param reputation User's current reputation score (with 10x precision)
    /// @param status User's current platform status
    /// @return success Whether the action is allowed for the user
    /// @return reason Human-readable explanation of the decision
    /// @custom:pure This function is pure and performs deterministic validation
    function _validateAction(
        address user,
        string memory action,
        uint256 reputation,
        DataTypes.UserStatus status
    ) internal pure returns (bool success, string memory reason) {
        // Parameter reserved for future per-user policy extensions.
        user;
        bytes32 actionHash = keccak256(abi.encodePacked(action));

        // High-risk actions require normal status
        if (
            actionHash == keccak256("PUBLISH_TASK") ||
            actionHash == keccak256("SUBMIT_WORK") ||
            actionHash == keccak256("REVIEW_SUBMISSION")
        ) {
            if (status != DataTypes.UserStatus.NORMAL) {
                return (false, string(abi.encodePacked("Action '", action, "' requires normal user status")));
            }
        }

        // Arbitration actions require higher reputation
        if (actionHash == keccak256("REQUEST_ARBITRATION")) {
            if (reputation < 500) {
                // 50.0 reputation
                return (false, "Arbitration requires minimum 50.0 reputation");
            }
        }

        return (true, "Action allowed");
    }

    /// @notice Validates global guard configuration parameters
    /// @dev Ensures reputation thresholds are within valid ranges and properly ordered.
    ///      Reverts if configuration is invalid.
    /// @param config Encoded GlobalGuardConfig to validate
    /// @custom:validation Checks threshold ordering and maximum values
    function _validateConfig(bytes calldata config) internal pure override {
        if (config.length == 0) return;

        GlobalGuardConfig memory globalConfig = abi.decode(config, (GlobalGuardConfig));

        // Validate reputation thresholds
        if (globalConfig.minReputationForNormal > 10000) {
            // 1000.0 max
            revert InvalidGlobalThreshold(globalConfig.minReputationForNormal);
        }

        if (globalConfig.atRiskThreshold > globalConfig.minReputationForNormal) {
            revert InvalidGlobalThreshold(globalConfig.atRiskThreshold);
        }

        // baseStakeAmount can be any value, including 0
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
