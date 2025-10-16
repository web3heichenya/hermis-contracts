// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IReputationManager
/// @notice Interface for managing user reputation scoring, staking requirements, and category-based skill tracking
/// @dev This interface defines the standard reputation management functionality including:
///      - User reputation scoring with dynamic updates based on performance
///      - Token staking requirements for platform access and participation
///      - Category-based skill scoring for specialized task matching
///      - Access validation combining reputation, staking, and status checks
/// @custom:interface Defines standard reputation behavior for user credibility and access control
/// @author Hermis Team
interface IReputationManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when user's reputation is below required threshold for action
    error InsufficientReputation(address user, uint256 required, uint256 current);

    /// @notice Error when user's stake amount is below required threshold
    error InsufficientStake(address user, uint256 required, uint256 current);

    /// @notice Error when attempting action with a blacklisted user account
    error UserBlacklisted(address user);

    /// @notice Error when attempting to unstake before lock period expires
    error UnstakeStillLocked(address user, uint256 unlockTime);

    /// @notice Error when caller is not authorized for the operation
    error UnauthorizedAccess(address caller);

    /// @notice Error for invalid token address
    error InvalidTokenAddress(address token);

    /// @notice Error when attempting to unstake without an active unstake request
    error NoUnstakeRequest(address user);

    /// @notice Error when reputation change amount is invalid or out of bounds
    error InvalidReputationChange(int256 change);

    /// @notice Error when base stake amount is invalid (e.g., zero)
    error InvalidBaseStake(uint256 baseStake);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new user is initialized with default reputation
    /// @param user Address of the user being initialized in the reputation system
    /// @param initialReputation Starting reputation score assigned to the new user
    event UserInitialized(address indexed user, uint256 initialReputation);

    /// @notice Emitted when user reputation is updated with change amount and reason
    /// @param user Address of the user whose reputation was changed
    /// @param change Amount of reputation change (positive for increase, negative for decrease)
    /// @param newReputation User's reputation score after the change
    /// @param reason Human-readable explanation for the reputation change
    event ReputationChanged(address indexed user, int256 change, uint256 newReputation, string reason);

    /// @notice Emitted when user stakes tokens for platform access
    /// @param user Address of the user who staked tokens
    /// @param amount Number of tokens staked for platform access
    /// @param token Address of the staking token contract
    event UserStaked(address indexed user, uint256 amount, address token);

    /// @notice Emitted when user requests to unstake with lock period start
    /// @param user Address of the user requesting to unstake
    /// @param unlockTime Timestamp when unstaking will become available
    event UnstakeRequested(address indexed user, uint256 unlockTime);

    /// @notice Emitted when user completes unstaking and withdraws tokens
    /// @param user Address of the user who completed unstaking
    /// @param amount Number of tokens withdrawn from staking
    /// @param token Address of the staking token that was withdrawn
    event UserUnstaked(address indexed user, uint256 amount, address token);

    /// @notice Emitted when user status changes based on reputation or behavior
    /// @param user Address of the user whose status changed
    /// @param oldStatus Previous user status before the change
    /// @param newStatus New user status after the change
    event UserStatusChanged(address indexed user, DataTypes.UserStatus oldStatus, DataTypes.UserStatus newStatus);

    /// @notice Emitted when user claims category score increases from completed work
    /// @param user Address of the user claiming category score
    /// @param category String identifier of the skill category being claimed
    /// @param scoreIncrease Amount of score points claimed and added
    /// @param newScore User's total category score after claiming
    event CategoryScoreClaimed(address indexed user, string category, uint256 scoreIncrease, uint256 newScore);

    /// @notice Emitted when base stake amount is updated by admin
    /// @param oldBaseStake Previous base stake amount
    /// @param newBaseStake New base stake amount
    /// @param updatedBy Address of the admin who updated the base stake
    event BaseStakeUpdated(uint256 oldBaseStake, uint256 newBaseStake, address indexed updatedBy);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   REPUTATION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes a new user account with default reputation and status
    /// @dev Creates user profile with initial reputation score and active status.
    ///      Should only be called once per user address.
    /// @param user Address of the user to initialize in the reputation system
    /// @custom:security Typically called automatically on first platform interaction
    function initializeUser(address user) external;

    /// @notice Updates user reputation based on platform activity and performance
    /// @dev Applies reputation changes from task completion, review accuracy, or administrative actions.
    ///      Should validate change amount and update user status if thresholds are crossed.
    /// @param user Address of the user whose reputation is being updated
    /// @param change Reputation change amount (positive for increases, negative for decreases)
    /// @param reason Human-readable explanation for the reputation change
    /// @custom:security Only callable by authorized platform contracts
    function updateReputation(address user, int256 change, string calldata reason) external;

    /// @notice Stakes tokens or ETH to meet platform access requirements and demonstrate commitment
    /// @dev Deposits tokens/ETH as collateral for platform participation.
    ///      Should validate token address and update user staking status.
    /// @param amount Number of tokens/ETH to stake for platform access
    /// @param token Address of the ERC-20 token to stake (address(0) for ETH, must be approved staking token)
    /// @custom:security Requires token approval for ERC20 or sufficient msg.value for ETH
    function stake(uint256 amount, address token) external payable;

    /// @notice Requests to unstake tokens and begins the mandatory lock period
    /// @dev Initiates unstaking process with time delay for security and stability.
    ///      User cannot unstake immediately to prevent rapid entry/exit.
    /// @custom:security Starts lock period timer, user cannot unstake until period expires
    function requestUnstake() external;

    /// @notice Completes the unstaking process after the lock period has expired
    /// @dev Transfers staked tokens back to user after lock period validation.
    ///      Should verify lock period has passed and update user access status.
    /// @custom:security Only callable after lock period expires, transfers tokens to user
    function unstake() external;

    /// @notice Claims pending category score increases earned from completed work
    /// @dev Processes accumulated category scores from successful task completions and reviews.
    ///      Should validate pending scores and update user's category expertise.
    /// @param category String identifier of the skill category (e.g., "development", "design")
    /// @param scoreIncrease Amount of score points to claim for the category
    /// @custom:security Only allows claiming legitimate earned scores
    function claimCategoryScore(string calldata category, uint256 scoreIncrease) external;

    /// @notice Validates whether user meets all platform access requirements
    /// @dev Checks reputation, staking, and status requirements for platform participation.
    ///      Used by other contracts to validate user eligibility for actions.
    /// @param user Address of the user to validate for platform access
    /// @return canAccess Whether user meets all requirements for platform access
    /// @return reason Human-readable explanation if access is denied
    /// @custom:view This function is read-only and performs comprehensive access validation
    function validateUserAccess(address user) external view returns (bool canAccess, string memory reason);

    /// @notice Gets comprehensive user reputation and staking information
    /// @dev Returns complete user profile including reputation, status, and staking details.
    /// @param user Address of the user to retrieve information for
    /// @return reputation Current reputation score accumulated from platform activity
    /// @return status Current user status (active, restricted, blacklisted, etc.)
    /// @return stakedAmount Currently staked token amount for platform access
    /// @return canUnstake Whether user can complete unstaking process now
    /// @return unstakeUnlockTime Timestamp when unstaking will become available (0 if no request)
    /// @custom:view This function is read-only and returns comprehensive user data
    function getUserReputation(
        address user
    )
        external
        view
        returns (
            uint256 reputation,
            DataTypes.UserStatus status,
            uint256 stakedAmount,
            bool canUnstake,
            uint256 unstakeUnlockTime
        );

    /// @notice Gets user's skill score in a specific category
    /// @dev Returns accumulated expertise score for specialized task matching.
    /// @param user Address of the user to check category expertise
    /// @param category String identifier of the skill category to query
    /// @return score Current accumulated score in the specified category
    /// @custom:view This function is read-only and returns category expertise data
    function getCategoryScore(address user, string calldata category) external view returns (uint256 score);

    /// @notice Gets the required stake amount for a user based on their reputation level
    /// @dev Calculates dynamic staking requirements that may vary with reputation.
    ///      Higher reputation users may have lower staking requirements.
    /// @param user Address of the user to calculate stake requirements for
    /// @return requiredStake Minimum token amount required for platform access
    /// @custom:view This function is read-only and calculates dynamic stake requirements
    function getRequiredStakeAmount(address user) external view returns (uint256 requiredStake);

    /// @notice Validates whether user reputation can be increased by administrators
    /// @dev Checks eligibility and limits for administrative reputation adjustments.
    ///      Used for arbitration and dispute resolution processes.
    /// @param user Address of the user for reputation increase validation
    /// @param increase Amount of reputation increase to validate
    /// @return canIncrease Whether the reputation increase is permitted
    /// @custom:view This function is read-only and validates administrative actions
    function canIncreaseReputation(address user, uint256 increase) external view returns (bool canIncrease);

    /// @notice Increases user reputation through administrative action for arbitration resolution
    /// @dev Applies reputation increases from successful arbitration or dispute resolution.
    ///      Should validate increase amount and emit appropriate events.
    /// @param user Address of the user receiving reputation increase
    /// @param increase Amount of reputation points to add
    /// @param reason Explanation for the administrative reputation increase
    /// @custom:security Only callable by authorized administrators for arbitration
    function increaseReputationAdmin(address user, uint256 increase, string calldata reason) external;

    /// @notice Adds pending category score that user can claim after completing work
    /// @dev Records earned category scores from task completion or review accuracy.
    ///      Scores remain pending until user explicitly claims them.
    /// @param user Address of the user who earned the category score
    /// @param category String identifier of the skill category for the earned score
    /// @param score Amount of score points to add to pending claims
    /// @custom:security Only callable by authorized platform contracts for earned scores
    function addPendingCategoryScore(address user, string calldata category, uint256 score) external;

    /// @notice Updates the base stake amount required for at-risk users
    /// @dev Allows admin to adjust stake requirements based on economic conditions.
    ///      The base stake is used in the formula: baseStake * (NORMAL_THRESHOLD - reputation) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD)
    /// @param newBaseStake New base stake amount (must be greater than 0)
    /// @custom:security Only callable by contract owner
    /// @custom:economic Affects stake requirements for all at-risk users
    function updateBaseStake(uint256 newBaseStake) external;
}
