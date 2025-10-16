// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// 2. Internal interfaces
import {IGuard} from "../interfaces/IGuard.sol";

/// @title BaseGuard
/// @notice Abstract base contract for guard implementations in the Hermis ecosystem
/// @dev This abstract contract provides:
///      - Common initialization pattern for all guard implementations
///      - Configuration management with validation hooks
///      - Owner-controlled configuration updates
///      - Standardized validation interface for user permission checks
///      - Event emission for configuration changes
/// @custom:security All configuration changes are restricted to contract owner
/// @custom:abstract Child contracts must implement _performValidation and _validateConfig
/// @author Hermis Team
abstract contract BaseGuard is IGuard, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Encoded configuration data specific to each guard implementation
    /// @dev Stored as bytes to allow flexible configuration structures across different guards
    bytes private _guardConfig;

    /// @notice Flag indicating whether the guard has been initialized with configuration
    /// @dev Prevents usage before proper setup and double initialization
    bool private _initialized;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyInitialized() {
        if (!_initialized) revert GuardNotInitialized();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the base guard with owner address
    /// @dev Sets the owner but does not initialize configuration - that must be done separately
    /// @param owner Address that will have administrative control over the guard
    /// @custom:security Owner has exclusive access to configuration functions
    constructor(address owner) Ownable(owner) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the guard with initial configuration data
    /// @dev Can only be called once. Validates configuration before storing.
    ///      Child contracts define validation logic through _validateConfig.
    /// @param initialConfig Initial configuration data (format depends on guard implementation)
    /// @custom:security Only callable by owner and only once
    /// @custom:validation Calls _validateConfig to ensure configuration validity
    function initializeGuard(bytes calldata initialConfig) external onlyOwner {
        if (_initialized) revert InvalidGuardConfiguration();

        _validateConfig(initialConfig);
        _guardConfig = initialConfig;
        _initialized = true;

        emit GuardConfigurationUpdated("", initialConfig);
    }

    /// @notice Updates the guard configuration after initialization
    /// @dev Validates new configuration before updating. Emits event with old and new config.
    /// @param newConfig New configuration data to replace current configuration
    /// @custom:security Only callable by owner after initialization
    /// @custom:validation Calls _validateConfig to ensure new configuration validity
    function updateGuardConfig(bytes calldata newConfig) external override onlyOwner onlyInitialized {
        _validateConfig(newConfig);

        bytes memory oldConfig = _guardConfig;
        _guardConfig = newConfig;

        emit GuardConfigurationUpdated(oldConfig, newConfig);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates if a user meets the guard's requirements
    /// @dev Delegates to _performValidation which is implemented by child contracts.
    ///      The data parameter format depends on the specific guard implementation.
    /// @param user Address of the user to validate
    /// @param data Additional context data for validation (format varies by guard type)
    /// @return success True if user passes validation, false otherwise
    /// @return reason Human-readable explanation of the validation result
    /// @custom:view This function is read-only and performs validation checks
    function validateUser(
        address user,
        bytes calldata data
    ) external view override onlyInitialized returns (bool success, string memory reason) {
        return _performValidation(user, data);
    }

    /// @notice Gets the current guard configuration data
    /// @dev Returns raw bytes that must be decoded according to guard implementation
    /// @return config Current encoded configuration data
    /// @custom:view This function is read-only and returns raw configuration
    function getGuardConfig() external view override returns (bytes memory config) {
        return _guardConfig;
    }

    /// @notice Checks if the guard has been initialized with configuration
    /// @dev Used to ensure guard is properly set up before use
    /// @return initialized True if guard has been initialized, false otherwise
    /// @custom:view This function is read-only and provides initialization status
    function isInitialized() external view returns (bool initialized) {
        return _initialized;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Abstract function for performing guard-specific validation logic
    /// @dev Must be implemented by child contracts to define specific validation rules.
    ///      Called by validateUser after initialization check.
    /// @param user Address of the user to validate
    /// @param data Additional context data for validation (format defined by implementation)
    /// @return success True if validation passes, false otherwise
    /// @return reason Human-readable explanation of the validation result
    /// @custom:abstract Must be overridden by inheriting contracts
    function _performValidation(
        address user,
        bytes calldata data
    ) internal view virtual returns (bool success, string memory reason);

    /// @notice Abstract function for validating guard-specific configuration
    /// @dev Must be implemented by child contracts to ensure configuration validity.
    ///      Should revert if configuration is invalid.
    /// @param config Configuration data to validate (format defined by implementation)
    /// @custom:abstract Must be overridden by inheriting contracts
    /// @custom:validation Should revert with InvalidGuardConfiguration if invalid
    function _validateConfig(bytes calldata config) internal view virtual;

    /// @notice Utility function for child contracts to access raw configuration
    /// @dev Provides access to stored configuration for decoding in implementations
    /// @return Stored configuration data as bytes
    /// @custom:internal Only accessible to inheriting contracts
    function _getDecodedConfig() internal view returns (bytes memory) {
        return _guardConfig;
    }
}
