// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IGuard
/// @notice Interface for guard contracts that provide user access validation and permission control
/// @dev This interface defines the standard guard contract functionality including:
///      - User validation against configurable criteria
///      - Configuration management with validation hooks
///      - Metadata provision for guard identification and versioning
///      - Event emission for validation results and configuration changes
/// @custom:interface Defines standard guard behavior for access control systems
/// @author Hermis Team
interface IGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when guard validation fails for a user
    error GuardValidationFailed(address user, string reason);

    /// @notice Error when guard is used before proper initialization
    error GuardNotInitialized();

    /// @notice Error when guard configuration is invalid or malformed
    error InvalidGuardConfiguration();

    /// @notice Error when ReputationManager address is not set or invalid
    error ReputationManagerNotSet();

    /// @notice Error when configuration thresholds are invalid
    error InvalidGlobalThreshold(uint256 threshold);

    /// @notice Error when reputation threshold configuration is invalid
    error InvalidReputationThreshold(uint256 threshold);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a user successfully passes guard validation
    /// @param user Address of the user who successfully passed validation
    /// @param data Additional context data that was used for validation
    event GuardValidationPassed(address indexed user, bytes data);

    /// @notice Emitted when guard configuration is updated
    /// @param oldConfig Previous configuration data that was replaced
    /// @param newConfig New configuration data that was applied
    event GuardConfigurationUpdated(bytes oldConfig, bytes newConfig);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      GUARD FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates if a user meets the guard's access requirements
    /// @dev Implementation should perform all necessary checks based on guard configuration.
    ///      Data format depends on specific guard implementation requirements.
    /// @param user Address of the user to validate
    /// @param data Additional context data for validation (format varies by guard type)
    /// @return success True if user passes validation, false otherwise
    /// @return reason Human-readable explanation of the validation result
    /// @custom:view This function is read-only and performs validation checks
    function validateUser(address user, bytes calldata data) external view returns (bool success, string memory reason);

    /// @notice Gets the current guard configuration data
    /// @dev Returns raw bytes that must be decoded according to guard implementation
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getGuardConfig() external view returns (bytes memory config);

    /// @notice Updates the guard configuration with new parameters
    /// @dev Should validate configuration before updating and emit configuration change event
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by authorized addresses (typically owner)
    function updateGuardConfig(bytes calldata newConfig) external;

    /// @notice Gets guard metadata for identification and versioning
    /// @dev Returns static metadata about the guard implementation
    /// @return name Guard implementation name
    /// @return version Semantic version of the guard
    /// @return description Human-readable description of guard functionality
    /// @custom:view This function is read-only and returns static metadata
    function getGuardMetadata()
        external
        pure
        returns (string memory name, string memory version, string memory description);
}
