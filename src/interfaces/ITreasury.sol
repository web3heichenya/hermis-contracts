// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// No external imports required for this interface

/// @title ITreasury
/// @notice Interface for the treasury contract managing all platform funds, deposits, and withdrawals
/// @dev This interface defines the standard treasury functionality including:
///      - Multi-purpose fund management for tasks, staking, arbitration, and platform fees
///      - Secure deposit and withdrawal mechanisms with purpose tracking
///      - Balance tracking and allocation management for different fund categories
///      - Administrative controls for platform fee management and distribution
/// @custom:interface Defines standard treasury behavior for comprehensive fund management
/// @author Hermis Team
interface ITreasury {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when available balance is insufficient for requested withdrawal
    error InsufficientBalance(address token, uint256 required, uint256 available);

    /// @notice Error when withdrawal request ID is invalid or does not exist
    error InvalidWithdrawalRequest(uint256 requestId);

    /// @notice Error when caller lacks permission to perform withdrawal
    error UnauthorizedWithdrawal(address caller);

    /// @notice Error when token transfer operation fails
    error TransferFailed(address token, address to, uint256 amount);

    /// @notice Error when provided token address is invalid or unsupported
    error InvalidTokenAddress(address token);

    /// @notice Error when contract is not authorized to perform treasury operations
    error ContractNotAuthorized(address caller);

    /// @notice Error when treasury operations are paused
    error TreasuryPaused();

    /// @notice Error when deposit purpose string is invalid
    error InvalidPurpose(string purpose);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when funds are deposited into the treasury for any purpose
    /// @param depositor Address of the user or contract making the deposit
    /// @param token Address of the token being deposited (zero address for native token)
    /// @param amount Amount of tokens deposited into the treasury
    /// @param taskId ID associated with the deposit (0 for non-task deposits)
    /// @param purpose String describing the purpose of the deposit
    event FundsDeposited(
        address indexed depositor,
        address indexed token,
        uint256 amount,
        uint256 indexed taskId,
        string purpose
    );

    /// @notice Emitted when funds are withdrawn from the treasury
    /// @param recipient Address receiving the withdrawn funds
    /// @param token Address of the token being withdrawn (zero address for native token)
    /// @param amount Amount of tokens withdrawn from the treasury
    /// @param taskId ID associated with the withdrawal (0 for non-task withdrawals)
    /// @param purpose String describing the purpose of the withdrawal
    event FundsWithdrawn(
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 indexed taskId,
        string purpose
    );

    /// @notice Emitted when funds are locked for specific purposes (e.g., task escrow)
    /// @param token Address of the token being locked
    /// @param amount Amount of tokens locked in escrow
    /// @param taskId ID of the task or purpose the funds are locked for
    /// @param purpose String describing why the funds are locked
    event FundsLocked(address indexed token, uint256 amount, uint256 indexed taskId, string purpose);

    /// @notice Emitted when previously locked funds are unlocked and made available
    /// @param token Address of the token being unlocked
    /// @param amount Amount of tokens unlocked from escrow
    /// @param taskId ID of the task or purpose the funds were locked for
    /// @param purpose String describing why the funds were unlocked
    event FundsUnlocked(address indexed token, uint256 amount, uint256 indexed taskId, string purpose);

    /// @notice Emitted when contract authorization status changes
    /// @param contractAddr Address of the contract whose authorization changed
    /// @param authorized New authorization status (true for authorized, false for revoked)
    event ContractAuthorized(address indexed contractAddr, bool authorized);

    /// @notice Event emitted when treasury pause status changes
    /// @dev DEPRECATED: Treasury now uses OpenZeppelin Pausable which emits:
    ///      - Paused(address account) when paused
    ///      - Unpaused(address account) when unpaused
    /// @param paused New pause status (true for paused, false for unpaused)
    event TreasuryPausedEvent(bool paused);

    /// @notice Event emitted during emergency withdrawals
    /// @param token Address of the token withdrawn in emergency
    /// @param recipient Address receiving the emergency withdrawal
    /// @param amount Amount of tokens withdrawn in emergency
    event EmergencyWithdrawal(address indexed token, address indexed recipient, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    TREASURY FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deposits reward funds for a specific task into escrow
    /// @dev Locks funds for task completion rewards until distribution is triggered.
    ///      Should validate token address and amount before processing.
    /// @param taskId ID of the task to deposit reward funds for
    /// @param token Address of the ERC-20 token for rewards (or zero address for native token)
    /// @param amount Amount of tokens to deposit as task reward
    /// @custom:security Requires token approval for ERC-20 or sufficient msg.value for native
    function depositTaskReward(uint256 taskId, address token, uint256 amount) external payable;

    /// @notice Deposits staking tokens for user platform access requirements
    /// @dev Securely holds user stake tokens until unstaking is requested and processed.
    ///      Should validate staking token and update user staking records.
    /// @param user Address of the user depositing stake tokens
    /// @param token Address of the approved staking token contract
    /// @param amount Amount of staking tokens to deposit for platform access
    /// @custom:security Requires token approval and validates staking token eligibility
    function depositStake(address user, address token, uint256 amount) external payable;

    /// @notice Deposits arbitration fee for dispute resolution processing
    /// @dev Holds arbitration fees in escrow until resolution, with refund or forfeit based on outcome.
    ///      Should validate fee amount meets minimum requirements.
    /// @param arbitrationId ID of the arbitration request requiring fee deposit
    /// @param token Address of the token accepted for arbitration fees
    /// @param amount Fee amount required for arbitration processing
    /// @custom:security Validates fee requirements and holds in escrow until resolution
    function depositArbitrationFee(uint256 arbitrationId, address token, uint256 amount) external payable;

    /// @notice Withdraws task reward funds to specified recipient after task completion
    /// @dev Transfers reward funds from escrow to recipients based on reward distribution.
    ///      Should validate task completion and authorized distribution.
    /// @param taskId ID of the completed task for reward distribution
    /// @param recipient Address of the user receiving the reward payment
    /// @param token Address of the reward token to transfer
    /// @param amount Amount of reward tokens to transfer to recipient
    /// @custom:security Only callable by authorized contracts after task completion verification
    function withdrawTaskReward(uint256 taskId, address recipient, address token, uint256 amount) external;

    /// @notice Withdraws user stake tokens after unstaking lock period completion
    /// @dev Returns staked tokens to user after unstaking requirements are met.
    ///      Should validate unstaking eligibility and lock period expiration.
    /// @param user Address of the user withdrawing their stake
    /// @param token Address of the staking token being withdrawn
    /// @param amount Amount of staking tokens to return to user
    /// @custom:security Only callable after unstaking lock period and eligibility validation
    function withdrawStake(address user, address token, uint256 amount) external;

    /// @notice Withdraws arbitration fee from escrow based on resolution outcome
    /// @dev Transfers fee refund to recipient for approved/dismissed arbitrations.
    ///      Should validate arbitration resolution status before processing.
    /// @param arbitrationId ID of the resolved arbitration request
    /// @param recipient Address eligible to receive the fee refund
    /// @param token Address of the fee token to refund
    /// @param amount Amount of fee tokens to refund to recipient
    /// @custom:security Only processes refunds for legitimate arbitration resolutions
    function withdrawArbitrationFee(uint256 arbitrationId, address recipient, address token, uint256 amount) external;

    /// @notice Withdraws accumulated platform fees to designated recipient
    /// @dev Transfers collected platform fees for operational expenses and development.
    ///      Should validate authorized fee withdrawal and available balance.
    /// @param recipient Address authorized to receive platform fee payments
    /// @param token Address of the fee token to withdraw
    /// @param amount Amount of platform fees to withdraw
    /// @custom:security Only callable by authorized platform administrators
    function withdrawPlatformFees(address recipient, address token, uint256 amount) external;

    /// @notice Allocates platform fees from task reward distributions
    /// @dev Separates platform fee portion from task rewards for operational funding.
    ///      Should validate fee calculation and update platform fee balance.
    /// @param token Address of the token for platform fee allocation
    /// @param amount Amount to allocate from rewards to platform fees
    /// @custom:security Only callable by authorized reward distribution contracts
    function allocatePlatformFee(address token, uint256 amount) external;

    /// @notice Gets available balance for a specific purpose and identifier
    /// @dev Returns balance allocated to specific purpose categories for fund management.
    ///      Used for validating withdrawal eligibility and displaying balances.
    /// @param token Address of the token to check balance for
    /// @param purpose Purpose category string ("task", "stake", "arbitration", "platform")
    /// @param id Specific identifier related to the purpose (taskId for tasks, userId for stakes, etc.)
    /// @return balance Available balance amount for the specified purpose and identifier
    /// @custom:view This function is read-only and returns purpose-specific balance data
    function getBalance(address token, string calldata purpose, uint256 id) external view returns (uint256 balance);

    /// @notice Gets total amount of locked funds for a specific token
    /// @dev Returns cumulative locked balance across all purposes for treasury management.
    ///      Locked funds are not available for withdrawal until unlocked.
    /// @param token Address of the token to check total locked funds for
    /// @return totalLocked Total amount of tokens currently locked across all purposes
    /// @custom:view This function is read-only and returns cumulative locked fund data
    function getTotalLocked(address token) external view returns (uint256 totalLocked);

    /// @notice Gets accumulated platform fee balance for operational funding
    /// @dev Returns available platform fees for withdrawal by authorized administrators.
    ///      Fees accumulate from task rewards and other platform activities.
    /// @param token Address of the token to check platform fee balance for
    /// @return feeBalance Available platform fee balance ready for withdrawal
    /// @custom:view This function is read-only and returns platform fee balance data
    function getPlatformFeeBalance(address token) external view returns (uint256 feeBalance);
}
