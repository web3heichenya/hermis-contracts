// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IHermisCore
/// @notice Main interface for Hermis platform core functionality and system coordination
/// @dev This interface defines the core platform management functionality including:
///      - Platform initialization and configuration management
///      - System pause/unpause controls for emergency situations
///      - Contract registry for modular architecture management
///      - Global access validation and permission controls
/// @custom:interface Defines standard core platform behavior for system coordination
/// @author Hermis Team
interface IHermisCore {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when attempting operations while platform is paused
    error PlatformPaused();

    /// @notice Error when caller lacks required permissions for the operation
    error UnauthorizedAccess(address caller);

    /// @notice Error when provided configuration parameters are invalid
    error InvalidConfiguration();

    /// @notice Error when attempting to access an unregistered contract
    error ContractNotRegistered(address contractAddr);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when platform operations are paused by administrator
    /// @param admin Address of the administrator who paused the platform
    event PlatformPausedEvent(address indexed admin);

    /// @notice Emitted when platform operations are resumed by administrator
    /// @param admin Address of the administrator who unpaused the platform
    event PlatformUnpaused(address indexed admin);

    /// @notice Emitted when global platform configuration is updated
    /// @param oldConfig Previous global configuration that was replaced
    /// @param newConfig New global configuration that was applied
    event GlobalConfigUpdated(DataTypes.GlobalConfig oldConfig, DataTypes.GlobalConfig newConfig);

    /// @notice Emitted when a new contract is registered in the platform registry
    /// @param name Unique string identifier for the registered contract
    /// @param contractAddr Address of the contract that was registered
    event ContractRegistered(string indexed name, address indexed contractAddr);

    /// @notice Emitted when a registered contract address is updated
    /// @param name String identifier of the contract that was updated
    /// @param oldAddr Previous contract address that was replaced
    /// @param newAddr New contract address that was set
    event ContractUpdated(string indexed name, address indexed oldAddr, address indexed newAddr);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CORE FUNCTIONS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the Hermis platform with core contracts and configuration
    /// @dev Sets up the platform with initial configuration and core contract addresses.
    ///      Should validate all contract addresses and configuration parameters.
    /// @param config Initial global configuration including fees, thresholds, and system parameters
    /// @param treasury Address of the treasury contract for fund management
    /// @param sbtContract Address of the Soulbound Token contract for user credentials
    /// @custom:security Only callable during initial deployment setup
    function initialize(DataTypes.GlobalConfig calldata config, address treasury, address sbtContract) external;

    /// @notice Pauses all platform operations for emergency situations
    /// @dev Stops all non-administrative functions across the platform.
    ///      Used for emergency stops or maintenance periods.
    /// @custom:security Only callable by authorized administrators
    function pausePlatform() external;

    /// @notice Resumes platform operations after a pause
    /// @dev Re-enables all platform functions that were paused.
    ///      Should verify system integrity before resuming operations.
    /// @custom:security Only callable by authorized administrators
    function unpausePlatform() external;

    /// @notice Updates global platform configuration with new parameters
    /// @dev Validates and applies new configuration settings across the platform.
    ///      Should emit events for configuration changes.
    /// @param newConfig New global configuration including updated fees, thresholds, and parameters
    /// @custom:security Only callable by authorized administrators
    function updateGlobalConfig(DataTypes.GlobalConfig calldata newConfig) external;

    /// @notice Registers a core platform contract in the system registry
    /// @dev Adds a new contract to the platform's modular architecture registry.
    ///      Should validate contract interface compatibility.
    /// @param name Unique string identifier for the contract (e.g., "TaskManager", "ReputationManager")
    /// @param contractAddr Address of the contract to register
    /// @custom:security Only callable by authorized administrators
    function registerContract(string calldata name, address contractAddr) external;

    /// @notice Updates a registered contract address for system upgrades
    /// @dev Replaces an existing contract address in the registry with a new implementation.
    ///      Should validate new contract interface compatibility.
    /// @param name String identifier of the contract to update
    /// @param newAddr New contract address to replace the existing one
    /// @custom:security Only callable by authorized administrators
    function updateContract(string calldata name, address newAddr) external;

    /// @notice Gets the current global platform configuration
    /// @dev Returns the complete global configuration structure.
    /// @return config Current global configuration including all fees, thresholds, and parameters
    /// @custom:view This function is read-only and returns configuration data
    function getGlobalConfig() external view returns (DataTypes.GlobalConfig memory config);

    /// @notice Gets the address of a registered contract by name
    /// @dev Retrieves contract address from the platform registry.
    /// @param name String identifier of the contract to retrieve
    /// @return contractAddr Address of the registered contract (zero address if not found)
    /// @custom:view This function is read-only and returns registry data
    function getContract(string calldata name) external view returns (address contractAddr);

    /// @notice Checks whether the platform is currently paused
    /// @dev Returns the current pause status for operational checks.
    /// @return True if platform operations are paused, false if operational
    /// @custom:view This function is read-only and returns pause status
    function paused() external view returns (bool);

    /// @notice Gets the current platform version for compatibility checking
    /// @dev Returns semantic version string for client compatibility verification.
    /// @return version Current platform version in semantic versioning format (e.g., "1.0.0")
    /// @custom:view This function is read-only and returns static version data
    function getVersion() external pure returns (string memory version);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   VALIDATION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates user access permissions using the global guard system
    /// @dev Checks user eligibility for specific actions using configured guard contracts.
    ///      Should integrate with reputation and staking requirements.
    /// @param user Address of the user requesting access
    /// @param action String identifier for the action being requested (e.g., "submit", "review")
    /// @param data Additional context data for validation (format depends on guard implementation)
    /// @return canAccess Whether the user is permitted to perform the action
    /// @return reason Human-readable explanation if access is denied
    /// @custom:view This function is read-only and performs access validation
    function validateUserAccess(
        address user,
        string calldata action,
        bytes calldata data
    ) external view returns (bool canAccess, string memory reason);

    /// @notice Validates contract integration compatibility with platform interfaces
    /// @dev Checks if a contract implements required interfaces for platform integration.
    ///      Used for validating guard contracts, strategies, and other modular components.
    /// @param contractAddr Address of the contract to validate for platform compatibility
    /// @param interfaceId ERC-165 interface identifier to check for compliance
    /// @return isValid Whether the contract implements the required interface
    /// @custom:view This function is read-only and performs interface validation
    function validateContract(address contractAddr, bytes4 interfaceId) external view returns (bool isValid);
}
