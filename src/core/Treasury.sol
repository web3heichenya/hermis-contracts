// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Internal interfaces
import {ITreasury} from "../interfaces/ITreasury.sol";

/// @title Treasury
/// @notice Secure treasury contract managing all platform funds and token escrow in the Hermis ecosystem
/// @dev This contract implements a multi-purpose fund management system including:
///      - Task reward escrow with secure deposit and withdrawal mechanisms
///      - User staking deposits with time-locked withdrawal capabilities
///      - Arbitration fee collection and refund processing
///      - Platform fee accumulation and administrative withdrawal
///      - Emergency pause functionality for security incidents
///      - Multi-token support for both ETH and ERC20 tokens
/// @custom:security Non-upgradeable contract design for maximum fund security
/// @custom:access Only authorized system contracts can deposit/withdraw funds
/// @author Hermis Team
contract Treasury is ITreasury, Ownable, ReentrancyGuard, Pausable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Triple mapping storing balances by token address, purpose category, and specific ID
    /// @dev Structure: token => purpose => id => amount
    ///      - token: ERC20 token address (address(0) for ETH)
    ///      - purpose: "task", "stake", "arbitration", or "platform"
    ///      - id: task ID, user ID (as uint256), or arbitration ID
    mapping(address => mapping(string => mapping(uint256 => uint256))) private _balances;

    /// @notice Mapping of token addresses to their total locked amounts across all purposes
    /// @dev Used for tracking total funds committed to various platform activities
    mapping(address => uint256) private _totalLocked;

    /// @notice Mapping of token addresses to accumulated platform fee balances
    /// @dev Platform fees collected from task rewards and other platform activities
    mapping(address => uint256) private _platformFees;

    /// @notice Mapping of contract addresses to their authorization status
    /// @dev Only authorized contracts can deposit and withdraw funds from Treasury
    mapping(address => bool) private _authorizedContracts;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyAuthorized() {
        if (!_authorizedContracts[msg.sender] && msg.sender != owner()) {
            revert ContractNotAuthorized(msg.sender);
        }
        _;
    }

    modifier validPurpose(string calldata purpose) {
        bytes32 purposeHash = keccak256(bytes(purpose));
        if (
            purposeHash != keccak256("task") &&
            purposeHash != keccak256("stake") &&
            purposeHash != keccak256("arbitration") &&
            purposeHash != keccak256("platform")
        ) {
            revert InvalidPurpose(purpose);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the Treasury contract with the specified owner
    /// @dev Sets up the contract in an unpaused state with no authorized contracts initially.
    ///      The owner must call setAuthorizedContract to enable system contracts to interact.
    /// @param owner Address that will have administrative control over the Treasury
    /// @custom:security Owner has exclusive access to authorization, pause, and emergency functions
    constructor(address owner) Ownable(owner) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Authorizes or deauthorizes a contract to interact with Treasury functions
    /// @dev Only authorized contracts can deposit and withdraw funds. Typically used to grant
    ///      access to TaskManager, SubmissionManager, ReputationManager, and other core contracts.
    /// @param contractAddr Address of the contract to modify authorization for
    /// @param authorized Whether to grant (true) or revoke (false) authorization
    /// @custom:security Only callable by contract owner to prevent unauthorized access
    function setAuthorizedContract(address contractAddr, bool authorized) external onlyOwner {
        _authorizedContracts[contractAddr] = authorized;
        emit ContractAuthorized(contractAddr, authorized);
    }

    /// @notice Pauses or unpauses Treasury operations for emergency situations
    /// @dev When paused, all deposit/withdraw functions are disabled except emergency withdrawals.
    ///      Used as a circuit breaker during security incidents or critical bugs.
    /// @param shouldPause Whether to pause (true) or unpause (false) Treasury operations
    /// @custom:security Only callable by contract owner for emergency response
    function setPaused(bool shouldPause) external onlyOwner {
        if (shouldPause) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Emergency withdrawal function for recovering funds during security incidents
    /// @dev Only callable by owner and only when Treasury is paused. Bypasses all normal
    ///      balance tracking and authorization checks. Should only be used in extreme circumstances.
    /// @param token Token address to withdraw (address(0) for ETH)
    /// @param recipient Address to receive the withdrawn funds
    /// @param amount Amount of tokens/ETH to withdraw
    /// @custom:security Only callable by owner when paused, bypasses normal checks
    /// @custom:emergency Use only during security incidents or contract failures
    function emergencyWithdraw(address token, address recipient, uint256 amount) external onlyOwner whenPaused {
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed(token, recipient, amount);
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit EmergencyWithdrawal(token, recipient, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deposits task reward funds into escrow for secure distribution
    /// @dev Called by TaskManager when publishers fund their tasks. Supports both ETH and ERC20 tokens.
    ///      For ETH deposits, the amount must match msg.value. Updates both specific balance and total locked.
    /// @param taskId ID of the task to deposit rewards for
    /// @param token Address of the reward token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to deposit
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:escrow Funds remain locked until task completion or cancellation
    function depositTaskReward(
        uint256 taskId,
        address token,
        uint256 amount
    ) external payable override onlyAuthorized whenNotPaused nonReentrant {
        if (amount == 0) return;

        _balances[token]["task"][taskId] += amount;
        _totalLocked[token] += amount;

        if (token == address(0)) {
            // ETH deposit - should be sent with the transaction
            if (msg.value != amount) revert InsufficientBalance(token, amount, msg.value);
        } else {
            // ERC20 deposit
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit FundsDeposited(msg.sender, token, amount, taskId, "task");
        emit FundsLocked(token, amount, taskId, "task");
    }

    /// @notice Deposits user staking funds for reputation-based access control
    /// @dev Called by ReputationManager when at-risk users stake tokens for platform access.
    ///      Converts user address to uint256 for consistent ID handling across the system.
    /// @param user Address of the user depositing stake
    /// @param token Address of the staking token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to stake
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:reputation Stakes remain locked until user requests unstaking
    function depositStake(
        address user,
        address token,
        uint256 amount
    ) external payable override onlyAuthorized whenNotPaused nonReentrant {
        if (amount == 0) return;

        uint256 userId = uint256(uint160(user));
        _balances[token]["stake"][userId] += amount;
        _totalLocked[token] += amount;

        if (token == address(0)) {
            if (msg.value != amount) revert InsufficientBalance(token, amount, msg.value);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit FundsDeposited(user, token, amount, userId, "stake");
        emit FundsLocked(token, amount, userId, "stake");
    }

    /// @notice Deposits arbitration fees for dispute resolution processes
    /// @dev Called by ArbitrationManager when users pay fees to dispute reputation or submissions.
    ///      Fees are held in escrow and either refunded (if dispute is approved) or forfeited (if denied).
    /// @param arbitrationId ID of the arbitration request
    /// @param token Address of the fee token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to deposit as arbitration fee
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:arbitration Fees remain locked pending arbitration resolution
    function depositArbitrationFee(
        uint256 arbitrationId,
        address token,
        uint256 amount
    ) external payable override onlyAuthorized whenNotPaused nonReentrant {
        if (amount == 0) return;

        _balances[token]["arbitration"][arbitrationId] += amount;
        _totalLocked[token] += amount;

        if (token == address(0)) {
            if (msg.value != amount) revert InsufficientBalance(token, amount, msg.value);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit FundsDeposited(msg.sender, token, amount, arbitrationId, "arbitration");
        emit FundsLocked(token, amount, arbitrationId, "arbitration");
    }

    /// @notice Withdraws task reward funds to specified recipient
    /// @dev Called by authorized contracts (TaskManager, SubmissionManager) to distribute rewards
    ///      to winning submitters, reviewers, or refund publishers. Validates sufficient balance before transfer.
    /// @param taskId ID of the task to withdraw rewards from
    /// @param recipient Address to receive the reward funds
    /// @param token Address of the reward token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to withdraw
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:validation Checks sufficient balance before withdrawal
    function withdrawTaskReward(
        uint256 taskId,
        address recipient,
        address token,
        uint256 amount
    ) external override onlyAuthorized whenNotPaused nonReentrant {
        uint256 available = _balances[token]["task"][taskId];
        if (available < amount) revert InsufficientBalance(token, amount, available);

        _balances[token]["task"][taskId] -= amount;
        _totalLocked[token] -= amount;

        _transferFunds(token, recipient, amount);

        emit FundsWithdrawn(recipient, token, amount, taskId, "task");
        emit FundsUnlocked(token, amount, taskId, "task");
    }

    /// @notice Withdraws user staking funds after unstaking request completion
    /// @dev Called by ReputationManager after user completes unstaking process (including lock period).
    ///      Converts user address to uint256 for consistent storage access pattern.
    /// @param user Address of the user withdrawing stake
    /// @param token Address of the staking token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to withdraw
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:timelock ReputationManager enforces time lock before calling this function
    function withdrawStake(
        address user,
        address token,
        uint256 amount
    ) external override onlyAuthorized whenNotPaused nonReentrant {
        uint256 userId = uint256(uint160(user));
        uint256 available = _balances[token]["stake"][userId];
        if (available < amount) revert InsufficientBalance(token, amount, available);

        _balances[token]["stake"][userId] -= amount;
        _totalLocked[token] -= amount;

        _transferFunds(token, user, amount);

        emit FundsWithdrawn(user, token, amount, userId, "stake");
        emit FundsUnlocked(token, amount, userId, "stake");
    }

    /// @notice Withdraws arbitration fees for refunds or forfeitures
    /// @dev Called by ArbitrationManager to refund fees (if dispute approved) or process forfeitures.
    ///      The recipient is typically the original fee payer for refunds or the platform for forfeitures.
    /// @param arbitrationId ID of the arbitration request
    /// @param recipient Address to receive the fee (disputer for refunds, platform for forfeitures)
    /// @param token Address of the fee token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to withdraw
    /// @custom:security Only callable by authorized contracts when not paused
    /// @custom:arbitration Used for both refunds and fee forfeitures
    function withdrawArbitrationFee(
        uint256 arbitrationId,
        address recipient,
        address token,
        uint256 amount
    ) external override onlyAuthorized whenNotPaused nonReentrant {
        uint256 available = _balances[token]["arbitration"][arbitrationId];
        if (available < amount) revert InsufficientBalance(token, amount, available);

        _balances[token]["arbitration"][arbitrationId] -= amount;
        _totalLocked[token] -= amount;

        _transferFunds(token, recipient, amount);

        emit FundsWithdrawn(recipient, token, amount, arbitrationId, "arbitration");
        emit FundsUnlocked(token, amount, arbitrationId, "arbitration");
    }

    /// @notice Withdraws accumulated platform fees (owner only)
    /// @dev Allows contract owner to withdraw fees collected from task rewards and other platform activities.
    ///      Platform fees are typically a percentage of task rewards allocated during reward distribution.
    /// @param recipient Address to receive the platform fees (typically team treasury)
    /// @param token Address of the fee token (address(0) for ETH)
    /// @param amount Amount of tokens/ETH to withdraw from platform fee balance
    /// @custom:security Only callable by contract owner for platform fee collection
    /// @custom:revenue Primary mechanism for platform revenue extraction
    function withdrawPlatformFees(
        address recipient,
        address token,
        uint256 amount
    ) external override onlyOwner whenNotPaused nonReentrant {
        uint256 available = _platformFees[token];
        if (available < amount) revert InsufficientBalance(token, amount, available);

        _platformFees[token] -= amount;

        _transferFunds(token, recipient, amount);

        emit FundsWithdrawn(recipient, token, amount, 0, "platform");
    }

    /// @notice Allocates platform fees from reward distributions
    /// @dev Called by SubmissionManager during reward processing to set aside platform fees.
    ///      These fees are separate from locked task funds and can be withdrawn by owner.
    /// @param token Token address to allocate fees for
    /// @param amount Amount to allocate as platform fee (from reward distributions)
    /// @custom:security Only callable by authorized contracts during reward processing
    /// @custom:revenue Accumulates fees that can later be withdrawn by owner
    function allocatePlatformFee(address token, uint256 amount) external onlyAuthorized {
        _platformFees[token] += amount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets available balance for a specific token, purpose, and ID combination
    /// @dev Queries the triple mapping structure for precise balance information.
    ///      Purpose must be one of: "task", "stake", "arbitration", "platform"
    /// @param token Address of the token to query (address(0) for ETH)
    /// @param purpose Purpose category for the funds (validated by modifier)
    /// @param id Specific identifier (task ID, user ID as uint256, or arbitration ID)
    /// @return balance Available balance for the specified combination
    /// @custom:view This function is read-only and provides precise balance queries
    function getBalance(
        address token,
        string calldata purpose,
        uint256 id
    ) external view override validPurpose(purpose) returns (uint256) {
        return _balances[token][purpose][id];
    }

    /// @notice Gets total locked funds for a specific token across all purposes
    /// @dev Returns the sum of all funds locked for tasks, stakes, and arbitrations.
    ///      Does not include platform fees as they are not locked for specific purposes.
    /// @param token Address of the token to query (address(0) for ETH)
    /// @return totalLocked Total amount locked across all platform activities
    /// @custom:view This function is read-only and provides aggregate locking information
    function getTotalLocked(address token) external view override returns (uint256) {
        return _totalLocked[token];
    }

    /// @notice Gets accumulated platform fee balance for a specific token
    /// @dev Returns fees that have been allocated but not yet withdrawn by the owner.
    ///      These fees are separate from locked funds and available for withdrawal.
    /// @param token Address of the token to query (address(0) for ETH)
    /// @return feeBalance Current platform fee balance available for withdrawal
    /// @custom:view This function is read-only and shows withdrawable fee amounts
    function getPlatformFeeBalance(address token) external view override returns (uint256) {
        return _platformFees[token];
    }

    /// @notice Checks if a contract address is authorized to interact with Treasury
    /// @dev Returns authorization status set by the contract owner. Authorized contracts
    ///      can call deposit and withdrawal functions.
    /// @param contractAddr Address of the contract to check authorization for
    /// @return authorized Whether the contract is authorized for Treasury operations
    /// @custom:view This function is read-only and checks access permissions
    function isAuthorized(address contractAddr) external view returns (bool) {
        return _authorizedContracts[contractAddr];
    }

    /// @notice Gets total balance of a token held by the Treasury contract
    /// @dev Returns the actual token balance held by the contract, including both locked
    ///      funds and platform fees. For ETH, uses contract's native balance.
    /// @param token Token address to query (address(0) for ETH)
    /// @return totalBalance Total token balance held by Treasury contract
    /// @custom:view This function is read-only and shows actual contract balances
    function getTotalBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to safely transfer funds to recipients
    /// @dev Handles both ETH and ERC20 transfers with proper error checking.
    ///      For ETH transfers, uses low-level call for better gas efficiency.
    ///      For ERC20 transfers, uses SafeERC20 for secure token handling.
    /// @param token Token address to transfer (address(0) for ETH)
    /// @param recipient Address to receive the funds
    /// @param amount Amount of tokens/ETH to transfer
    /// @custom:security Uses SafeERC20 for token transfers, proper error handling for ETH
    function _transferFunds(address token, address recipient, uint256 amount) internal {
        if (amount == 0) return;

        if (token == address(0)) {
            // ETH transfer
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed(token, recipient, amount);
        } else {
            // ERC20 transfer
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RECEIVE FUNCTION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Allows Treasury contract to receive ETH deposits
    /// @dev Enables the contract to receive ETH for task rewards, staking, and arbitration fees.
    ///      The actual allocation to specific purposes is handled by the deposit functions.
    /// @custom:payable Required for ETH-based operations in the platform
    receive() external payable {
        // Allow ETH deposits for task rewards and staking
    }
}
