// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// 2. Internal interfaces
import {IAllowlistManager} from "../interfaces/IAllowlistManager.sol";
import {IAdoptionStrategy} from "../interfaces/IAdoptionStrategy.sol";
import {IGuard} from "../interfaces/IGuard.sol";

// 3. Internal libraries
import {Messages} from "../libraries/Messages.sol";

/// @title AllowlistManager
/// @notice Manages whitelists of approved Guards, Strategies, and Tokens in the Hermis platform
/// @dev This contract implements comprehensive allowlist management functionality including:
///      - Guard contract validation for submission and review guards
///      - Strategy contract validation for adoption strategies
///      - Token contract validation for reward tokens
///      - Admin functions for adding/removing approved contracts
///      - Batch operations for gas-efficient management
/// @custom:security Critical security component - only platform-verified contracts should be whitelisted
/// @custom:upgradeable This contract is upgradeable and uses OpenZeppelin's proxy pattern
/// @author Hermis Team
contract AllowlistManager is IAllowlistManager, Initializable, OwnableUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mapping of allowed guard contracts
    mapping(address => bool) private _allowedGuards;

    /// @notice Mapping of allowed strategy contracts (both adoption and reward strategies)
    mapping(address => bool) private _allowedStrategies;

    /// @notice Mapping of allowed reward token contracts
    mapping(address => bool) private _allowedTokens;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Constructor that disables initializers for upgradeable contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the AllowlistManager contract
    /// @dev This function is called once during proxy deployment to set up the contract
    /// @param owner Owner address with administrative privileges
    /// @custom:security Only callable once due to initializer modifier
    function initialize(address owner) external initializer {
        __Ownable_init(owner);

        // Always allow address(0) for guards (no guard) and tokens (native ETH)
        _allowedGuards[address(0)] = true;
        _allowedTokens[address(0)] = true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   VALIDATION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates if a guard contract is in the allowlist
    /// @dev Returns true if guard is approved, false otherwise. address(0) is always allowed (no guard).
    /// @param guard Address of the guard contract to validate
    /// @return isAllowed Whether the guard is in the allowlist
    function isGuardAllowed(address guard) external view override returns (bool isAllowed) {
        return _allowedGuards[guard];
    }

    /// @notice Validates if a strategy (adoption or reward) is in the allowlist
    /// @dev Returns true if strategy is approved, false otherwise.
    ///      Both adoption and reward strategies share the same allowlist.
    /// @param strategy Address of the strategy contract to validate
    /// @return isAllowed Whether the strategy is in the allowlist
    function isStrategyAllowed(address strategy) external view override returns (bool isAllowed) {
        return _allowedStrategies[strategy];
    }

    /// @notice Validates if a reward token is in the allowlist
    /// @dev Returns true if token is approved, false otherwise. address(0) is always allowed (native ETH).
    /// @param token Address of the token contract to validate
    /// @return isAllowed Whether the token is in the allowlist
    function isTokenAllowed(address token) external view override returns (bool isAllowed) {
        return _allowedTokens[token];
    }

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
    ) external view override returns (bool isValid, string memory reason) {
        // Validate submission guard
        if (!_allowedGuards[submissionGuard]) {
            return (false, Messages.SUBMISSION_GUARD_NOT_ALLOWED);
        }

        // Validate review guard
        if (!_allowedGuards[reviewGuard]) {
            return (false, Messages.REVIEW_GUARD_NOT_ALLOWED);
        }

        // Validate adoption strategy (cannot be address(0))
        if (adoptionStrategy == address(0)) {
            return (false, Messages.ADOPTION_STRATEGY_REQUIRED);
        }
        if (!_allowedStrategies[adoptionStrategy]) {
            return (false, Messages.ADOPTION_STRATEGY_NOT_ALLOWED);
        }

        // Validate reward token
        if (!_allowedTokens[rewardToken]) {
            return (false, Messages.REWARD_TOKEN_NOT_ALLOWED);
        }

        return (true, "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Adds a guard to the allowlist
    /// @dev Only callable by contract owner/admin. Validates guard is not zero address.
    ///      Checks that the guard contract implements IGuard interface by calling getGuardMetadata().
    /// @param guard Address of the guard contract to add
    /// @custom:security Only add guards that have been thoroughly audited and tested
    function allowGuard(address guard) external override onlyOwner {
        if (guard == address(0)) return; // Already allowed by default
        if (_allowedGuards[guard]) return; // Already allowed

        // Validate guard contract implements IGuard interface
        try IGuard(guard).getGuardMetadata() returns (string memory, string memory, string memory) {
            _allowedGuards[guard] = true;
            emit GuardAllowed(guard, msg.sender);
        } catch {
            revert InvalidAddress();
        }
    }

    /// @notice Removes a guard from the allowlist
    /// @dev Only callable by contract owner/admin. Cannot disallow address(0) as it's used for "no guard".
    /// @param guard Address of the guard contract to remove
    function disallowGuard(address guard) external override onlyOwner {
        if (guard == address(0)) revert InvalidAddress(); // Cannot disallow address(0)
        if (!_allowedGuards[guard]) return; // Not in allowlist

        _allowedGuards[guard] = false;
        emit GuardDisallowed(guard, msg.sender);
    }

    /// @notice Adds a strategy to the allowlist
    /// @dev Only callable by contract owner/admin. Validates strategy is not zero address.
    ///      Works for both adoption and reward strategies. Attempts to validate IAdoptionStrategy interface.
    /// @param strategy Address of the strategy contract to add
    /// @custom:security Only add strategies that have been thoroughly audited and tested
    function allowStrategy(address strategy) external override onlyOwner {
        if (strategy == address(0)) revert InvalidAddress();
        if (_allowedStrategies[strategy]) return; // Already allowed

        // Try to validate strategy contract implements IAdoptionStrategy interface
        // This is optional - strategy may not implement this interface
        /* solhint-disable no-empty-blocks */
        try IAdoptionStrategy(strategy).getStrategyMetadata() returns (string memory, string memory, string memory) {
            // Interface validation succeeded - strategy is valid
        } catch {
            // Not an IAdoptionStrategy, but could be a reward strategy or other type - Continue anyway
        }
        /* solhint-enable no-empty-blocks */
        _allowedStrategies[strategy] = true;
        emit StrategyAllowed(strategy, msg.sender);
    }

    /// @notice Removes a strategy from the allowlist
    /// @dev Only callable by contract owner/admin.
    /// @param strategy Address of the strategy contract to remove
    function disallowStrategy(address strategy) external override onlyOwner {
        if (!_allowedStrategies[strategy]) return; // Not in allowlist

        _allowedStrategies[strategy] = false;
        emit StrategyDisallowed(strategy, msg.sender);
    }

    /// @notice Adds a reward token to the allowlist
    /// @dev Only callable by contract owner/admin. address(0) represents native ETH.
    ///      For ERC20 tokens, validates that the address contains contract code.
    /// @param token Address of the token contract to add (address(0) for ETH)
    /// @custom:security Only add tokens that are verified and trusted
    function allowToken(address token) external override onlyOwner {
        if (_allowedTokens[token]) return; // Already allowed

        // For ERC20 tokens, we could validate they implement the ERC20 interface
        // For address(0) (native ETH), we skip validation
        if (token != address(0)) {
            // Basic check: token contract should have code
            uint256 codeSize;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                codeSize := extcodesize(token)
            }
            if (codeSize == 0) revert InvalidAddress();
        }

        _allowedTokens[token] = true;
        emit TokenAllowed(token, msg.sender);
    }

    /// @notice Removes a reward token from the allowlist
    /// @dev Only callable by contract owner/admin. Cannot disallow address(0) (native ETH).
    /// @param token Address of the token contract to remove
    function disallowToken(address token) external override onlyOwner {
        if (token == address(0)) revert InvalidAddress(); // Cannot disallow native ETH
        if (!_allowedTokens[token]) return; // Not in allowlist

        _allowedTokens[token] = false;
        emit TokenDisallowed(token, msg.sender);
    }

    /// @notice Batch adds multiple guards to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    ///      Skips guards that are already allowed or fail interface validation.
    /// @param guards Array of guard contract addresses to add
    function allowGuardBatch(address[] calldata guards) external override onlyOwner {
        for (uint256 i = 0; i < guards.length; ) {
            address guard = guards[i];
            if (guard != address(0) && !_allowedGuards[guard]) {
                // Validate guard contract implements IGuard interface
                /* solhint-disable no-empty-blocks */
                try IGuard(guard).getGuardMetadata() returns (string memory, string memory, string memory) {
                    _allowedGuards[guard] = true;
                    emit GuardAllowed(guard, msg.sender);
                } catch {
                    // Skip invalid guards - interface check failed
                }
                /* solhint-enable no-empty-blocks */
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch adds multiple strategies to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    ///      Skips strategies that are already allowed. Optionally validates IAdoptionStrategy interface.
    /// @param strategies Array of strategy contract addresses to add
    function allowStrategyBatch(address[] calldata strategies) external override onlyOwner {
        for (uint256 i = 0; i < strategies.length; ) {
            address strategy = strategies[i];
            if (strategy != address(0) && !_allowedStrategies[strategy]) {
                // Try to validate strategy contract implements IAdoptionStrategy interface
                // This is optional - continue even if validation fails
                /* solhint-disable no-empty-blocks */
                try IAdoptionStrategy(strategy).getStrategyMetadata() returns (
                    string memory,
                    string memory,
                    string memory
                ) {
                    // Interface validation succeeded - strategy is valid
                } catch {
                    // Not an IAdoptionStrategy, but could be a reward strategy or other type
                }
                /* solhint-enable no-empty-blocks */
                _allowedStrategies[strategy] = true;
                emit StrategyAllowed(strategy, msg.sender);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch adds multiple reward tokens to the allowlist
    /// @dev Only callable by contract owner/admin. More gas efficient for multiple additions.
    ///      Validates token contracts have code. Skips tokens that are already allowed or invalid.
    /// @param tokens Array of token contract addresses to add
    function allowTokenBatch(address[] calldata tokens) external override onlyOwner {
        for (uint256 i = 0; i < tokens.length; ) {
            address token = tokens[i];
            if (!_allowedTokens[token]) {
                // Validate token contract for non-zero addresses
                if (token != address(0)) {
                    uint256 codeSize;
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        codeSize := extcodesize(token)
                    }
                    if (codeSize == 0) {
                        unchecked {
                            ++i;
                        }
                        continue; // Skip invalid tokens
                    }
                }
                _allowedTokens[token] = true;
                emit TokenAllowed(token, msg.sender);
            }
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     QUERY FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets all allowed guards
    /// @dev Enumeration is not supported - use events or off-chain indexing instead
    /// @return guards Array of allowed guard addresses (always reverts)
    function getAllowedGuards() external pure override returns (address[] memory) {
        revert(Messages.ENUMERATION_NOT_SUPPORTED);
    }

    /// @notice Gets all allowed strategies
    /// @dev Enumeration is not supported - use events or off-chain indexing instead
    /// @return strategies Array of allowed strategy addresses (always reverts)
    function getAllowedStrategies() external pure override returns (address[] memory) {
        revert(Messages.ENUMERATION_NOT_SUPPORTED);
    }

    /// @notice Gets all allowed reward tokens
    /// @dev Enumeration is not supported - use events or off-chain indexing instead
    /// @return tokens Array of allowed token addresses (always reverts)
    function getAllowedTokens() external pure override returns (address[] memory) {
        revert(Messages.ENUMERATION_NOT_SUPPORTED);
    }
}
