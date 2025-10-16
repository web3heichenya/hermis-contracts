// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IAllowlistManager
/// @notice Interface for managing whitelists of approved Guards, Strategies, and Tokens in the Hermis platform
/// @dev This interface defines the standard allowlist management functionality including:
///      - Guard contract validation for submission and review guards
///      - Strategy contract validation for adoption and reward strategies
///      - Token contract validation for reward tokens
///      - Admin functions for adding/removing approved contracts
/// @custom:security Critical security component - only platform-verified contracts should be whitelisted
/// @author Hermis Team
interface IAllowlistManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when a guard contract is not in the allowlist
    error GuardNotAllowed(address guard);

    /// @notice Error when a strategy is not in the allowlist
    error StrategyNotAllowed(address strategy);

    /// @notice Error when a reward token is not in the allowlist
    error TokenNotAllowed(address token);

    /// @notice Error when trying to add a zero address to allowlist
    error InvalidAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a guard is added to the allowlist
    /// @param guard Address of the guard contract
    /// @param addedBy Address of the admin who added the guard
    event GuardAllowed(address indexed guard, address indexed addedBy);

    /// @notice Emitted when a guard is removed from the allowlist
    /// @param guard Address of the guard contract
    /// @param removedBy Address of the admin who removed the guard
    event GuardDisallowed(address indexed guard, address indexed removedBy);

    /// @notice Emitted when a strategy is added to the allowlist
    /// @param strategy Address of the strategy contract
    /// @param addedBy Address of the admin who added the strategy
    event StrategyAllowed(address indexed strategy, address indexed addedBy);

    /// @notice Emitted when a strategy is removed from the allowlist
    /// @param strategy Address of the strategy contract
    /// @param removedBy Address of the admin who removed the strategy
    event StrategyDisallowed(address indexed strategy, address indexed removedBy);

    /// @notice Emitted when a reward token is added to the allowlist
    /// @param token Address of the token contract (address(0) for native ETH)
    /// @param addedBy Address of the admin who added the token
    event TokenAllowed(address indexed token, address indexed addedBy);

    /// @notice Emitted when a reward token is removed from the allowlist
    /// @param token Address of the token contract
    /// @param removedBy Address of the admin who removed the token
    event TokenDisallowed(address indexed token, address indexed removedBy);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   VALIDATION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates if a guard contract is in the allowlist
    /// @dev Returns true if guard is approved, false otherwise. address(0) is always allowed (no guard).
    /// @param guard Address of the guard contract to validate
    /// @return isAllowed Whether the guard is in the allowlist
    function isGuardAllowed(address guard) external view returns (bool isAllowed);

    /// @notice Validates if a strategy (adoption or reward) is in the allowlist
    /// @dev Returns true if strategy is approved, false otherwise.
    ///      Both adoption and reward strategies share the same allowlist.
    /// @param strategy Address of the strategy contract to validate
    /// @return isAllowed Whether the strategy is in the allowlist
    function isStrategyAllowed(address strategy) external view returns (bool isAllowed);

    /// @notice Validates if a reward token is in the allowlist
    /// @dev Returns true if token is approved, false otherwise. address(0) is always allowed (native ETH).
    /// @param token Address of the token contract to validate
    /// @return isAllowed Whether the token is in the allowlist
    function isTokenAllowed(address token) external view returns (bool isAllowed);

    /// @notice Validates all task configuration parameters at once
    /// @dev Comprehensive validation for task creation. Returns detailed error reasons.
    /// @param submissionGuard Address of the submission guard (address(0) allowed)
    /// @param reviewGuard Address of the review guard (address(0) allowed)
    /// @param adoptionStrategy Address of the adoption strategy
    /// @param rewardToken Address of the reward token (address(0) for ETH)
    /// @return isValid Whether all parameters are valid
    /// @return reason Error reason if validation fails
    function validateTaskConfig(
        address submissionGuard,
        address reviewGuard,
        address adoptionStrategy,
        address rewardToken
    ) external view returns (bool isValid, string memory reason);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Adds a guard to the allowlist
    /// @dev Only callable by contract owner/admin. Validates guard is not zero address.
    /// @param guard Address of the guard contract to add
    /// @custom:security Only add guards that have been thoroughly audited and tested
    function allowGuard(address guard) external;

    /// @notice Removes a guard from the allowlist
    /// @dev Only callable by contract owner/admin.
    /// @param guard Address of the guard contract to remove
    function disallowGuard(address guard) external;

    /// @notice Adds a strategy to the allowlist
    /// @dev Only callable by contract owner/admin. Validates strategy is not zero address.
    ///      Works for both adoption and reward strategies.
    /// @param strategy Address of the strategy contract to add
    /// @custom:security Only add strategies that have been thoroughly audited and tested
    function allowStrategy(address strategy) external;

    /// @notice Removes a strategy from the allowlist
    /// @dev Only callable by contract owner/admin.
    /// @param strategy Address of the strategy contract to remove
    function disallowStrategy(address strategy) external;

    /// @notice Adds a reward token to the allowlist
    /// @dev Only callable by contract owner/admin. address(0) represents native ETH.
    /// @param token Address of the token contract to add (address(0) for ETH)
    /// @custom:security Only add tokens that are verified and trusted
    function allowToken(address token) external;

    /// @notice Removes a reward token from the allowlist
    /// @dev Only callable by contract owner/admin.
    /// @param token Address of the token contract to remove
    function disallowToken(address token) external;

    /// @notice Batch adds multiple guards to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    /// @param guards Array of guard contract addresses to add
    function allowGuardBatch(address[] calldata guards) external;

    /// @notice Batch adds multiple strategies to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    /// @param strategies Array of strategy contract addresses to add
    function allowStrategyBatch(address[] calldata strategies) external;

    /// @notice Batch adds multiple reward tokens to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    /// @param tokens Array of token contract addresses to add
    function allowTokenBatch(address[] calldata tokens) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     QUERY FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets all allowed guards
    /// @return guards Array of allowed guard addresses
    function getAllowedGuards() external view returns (address[] memory guards);

    /// @notice Gets all allowed strategies
    /// @return strategies Array of allowed strategy addresses
    function getAllowedStrategies() external view returns (address[] memory strategies);

    /// @notice Gets all allowed reward tokens
    /// @return tokens Array of allowed token addresses
    function getAllowedTokens() external view returns (address[] memory tokens);
}
