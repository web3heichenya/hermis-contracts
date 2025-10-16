// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// 2. Internal interfaces
import {IHermisSBT} from "../interfaces/IHermisSBT.sol";
import {IReputationManager} from "../interfaces/IReputationManager.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

// 3. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";
import {Messages} from "../libraries/Messages.sol";

/// @title ReputationManager
/// @notice Manages user reputation scores, staking requirements, and platform access control in the Hermis ecosystem
/// @dev This contract implements a comprehensive reputation and staking system including:
///      - Dynamic reputation scoring with configurable thresholds (NORMAL/AT_RISK/BLACKLISTED)
///      - Risk-based staking requirements where lower reputation requires higher stakes
///      - Integration with Hermis SBT for on-chain reputation representation
///      - Category-specific scoring system for specialized expertise tracking
///      - Administrative controls for dispute resolution and arbitration
///      - Treasury integration for secure stake management and reward distribution
/// @custom:security All monetary operations are secured with ReentrancyGuard and proper access controls
/// @custom:thresholds NORMAL: 60+, AT_RISK: 10-59, BLACKLISTED: 0-9 (with 10x precision)
/// @author Hermis Team
contract ReputationManager is IReputationManager, Ownable, ReentrancyGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mapping of user addresses to their reputation scores (with 10x precision, e.g., 1000 = 100.0)
    mapping(address => uint256) private _reputationScores;

    /// @notice Mapping of user addresses to their staked token amounts
    mapping(address => uint256) private _stakedAmounts;

    /// @notice Mapping of user addresses to their current platform status
    mapping(address => DataTypes.UserStatus) private _userStatus;

    /// @notice Double mapping of user addresses to category names to their earned category scores
    mapping(address => mapping(string => uint256)) private _categoryScores;

    /// @notice Double mapping of user addresses to category names to their pending (unclaimable) category scores
    /// @dev Pending scores must be claimed to become active and affect SBT metadata
    mapping(address => mapping(string => uint256)) private _pendingCategoryScores;

    /// @notice Mapping of user addresses to their last category score claim timestamp
    /// @dev Used for rate limiting and tracking user activity
    mapping(address => uint256) private _lastClaimTime;

    /// @notice Mapping of user addresses to their unstake request unlock timestamps
    mapping(address => uint256) private _unstakeRequestTime;

    /// @notice Mapping of user addresses to whether they have an active unstake request
    mapping(address => bool) private _hasUnstakeRequest;

    /// @notice Treasury contract interface for stake management and reward distribution
    ITreasury public immutable TREASURY;

    /// @notice Hermis SBT contract interface for on-chain reputation representation
    IHermisSBT public hermisSBT;

    /// @notice Address of the token required for staking (immutable after deployment)
    /// @dev address(0) indicates ETH is used for staking
    address public immutable STAKE_TOKEN;

    /// @notice Mapping of authorized contracts that can interact with reputation system
    /// @dev Used to restrict sensitive operations like updateReputation to trusted contracts
    mapping(address => bool) public authorizedContracts;

    /// @notice Base stake amount required for at-risk users (configurable)
    /// @dev This value is used to calculate dynamic stake requirements based on reputation.
    ///      Formula: baseStake * (NORMAL_THRESHOLD - reputation) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD)
    ///      Lower reputation = higher stake required
    uint256 public baseStake;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Default reputation score for new users (100.0 with 10x precision)
    uint256 public constant DEFAULT_REPUTATION = 1000;

    /// @notice Minimum reputation threshold for normal platform access (60.0 with 10x precision)
    uint256 public constant NORMAL_THRESHOLD = 600;

    /// @notice Reputation threshold below which users are marked as at-risk (10.0 with 10x precision)
    uint256 public constant AT_RISK_THRESHOLD = 100;

    /// @notice Reputation threshold at or below which users are blacklisted (0.0 with 10x precision)
    uint256 public constant BLACKLIST_THRESHOLD = 0;

    /// @notice Time period users must wait after requesting unstake before they can complete it
    uint256 public constant UNSTAKE_LOCK_PERIOD = 7 days;

    /// @notice Maximum possible reputation score to prevent overflow (1000.0 with 10x precision)
    uint256 public constant MAX_REPUTATION = 10000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyAuthorized() {
        if (msg.sender != owner() && msg.sender != address(hermisSBT) && !authorizedContracts[msg.sender]) {
            revert UnauthorizedAccess(msg.sender);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the ReputationManager contract with required dependencies
    /// @dev Sets up immutable references to Treasury and stake token. HermisSBT is set separately after deployment.
    /// @param owner Address that will have administrative control over the contract
    /// @param treasuryAddress Address of the Treasury contract for stake management
    /// @param stakeTokenAddress Address of the ERC20 token used for staking requirements
    /// @custom:security Treasury and stake token addresses are immutable after deployment
    constructor(address owner, address treasuryAddress, address stakeTokenAddress) Ownable(owner) {
        TREASURY = ITreasury(treasuryAddress);
        STAKE_TOKEN = stakeTokenAddress;
        baseStake = 0.001 ether; // Default base stake amount
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the Hermis SBT contract address for reputation representation
    /// @dev This function should be called once after both contracts are deployed to establish the connection.
    ///      The SBT contract will be notified of reputation changes and will mint tokens for new users.
    /// @param hermisSBTAddress Address of the deployed Hermis SBT contract
    /// @custom:security Only callable by contract owner, typically during initial setup
    function setHermisSBT(address hermisSBTAddress) external onlyOwner {
        hermisSBT = IHermisSBT(hermisSBTAddress);
    }

    /// @notice Sets authorization status for contracts to interact with reputation system
    /// @dev Authorized contracts can call updateReputation and addPendingCategoryScore. Typically
    ///      used to grant access to TaskManager, SubmissionManager, and other core system contracts.
    /// @param contractAddress Address of the contract to authorize/deauthorize
    /// @param authorized Whether the contract should be authorized for reputation operations
    /// @custom:security Only callable by contract owner to prevent unauthorized access
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
    }

    /// @notice Updates the base stake amount required for at-risk users
    /// @dev Allows admin to adjust stake requirements based on economic conditions.
    ///      The base stake is used in the formula: baseStake * (NORMAL_THRESHOLD - reputation) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD)
    ///      This affects all at-risk users' stake requirements immediately.
    /// @param newBaseStake New base stake amount (must be greater than 0)
    /// @custom:security Only callable by contract owner
    /// @custom:economic Affects stake requirements for all at-risk users
    function updateBaseStake(uint256 newBaseStake) external override onlyOwner {
        if (newBaseStake == 0) revert InvalidBaseStake(newBaseStake);

        uint256 oldBaseStake = baseStake;
        baseStake = newBaseStake;

        emit BaseStakeUpdated(oldBaseStake, newBaseStake, msg.sender);
    }

    /// @notice Initializes a new user with default reputation and mints their SBT
    /// @dev Can be called by anyone to initialize a user. Sets reputation to DEFAULT_REPUTATION,
    ///      status to NORMAL, and mints an SBT if the contract is configured. Safe to call multiple times.
    /// @param user Address of the user to initialize
    /// @custom:sbt Automatically mints Hermis SBT for the user if SBT contract is set
    function initializeUser(address user) external override {
        _initializeUser(user);
    }

    /// @notice Updates user reputation and recalculates their platform status
    /// @dev Only callable by authorized contracts (TaskManager, SubmissionManager, etc.).
    ///      Automatically updates user status based on new reputation and syncs with SBT.
    ///      Reputation is capped at MAX_REPUTATION and cannot go below 0.
    /// @param user Address of the user whose reputation to update
    /// @param change Reputation change amount (positive or negative, with 10x precision)
    /// @param reason Human-readable reason for the reputation change (for transparency)
    /// @custom:security Only callable by authorized system contracts
    /// @custom:sbt Automatically updates SBT metadata with new reputation and status
    function updateReputation(address user, int256 change, string calldata reason) external override onlyAuthorized {
        _updateUserReputation(user, change, reason);
    }

    /// @notice Stakes tokens or ETH to meet platform access requirements for at-risk users
    /// @dev At-risk users must stake tokens/ETH to maintain platform access. The required amount
    ///      is inversely proportional to reputation. Funds are transferred to Treasury for safekeeping.
    ///      Initializes user if not already initialized.
    /// @param amount Amount of tokens/ETH to stake
    /// @param token Token address to stake (must match the configured stake token, address(0) for ETH)
    /// @custom:security Protected by reentrancy guard, validates token address
    /// @custom:treasury Funds are held in Treasury contract for security and reward distribution
    function stake(uint256 amount, address token) external payable override nonReentrant {
        if (token != STAKE_TOKEN) revert InvalidTokenAddress(token);
        if (amount == 0) revert InsufficientStake(msg.sender, 1, 0);

        // Initialize user if not already initialized
        if (_userStatus[msg.sender] == DataTypes.UserStatus.UNINITIALIZED) {
            _initializeUser(msg.sender);
        }

        if (token == address(0)) {
            // ETH staking
            if (msg.value != amount) revert InsufficientStake(msg.sender, amount, msg.value);

            // Let treasury handle the ETH deposit
            TREASURY.depositStake{value: amount}(msg.sender, token, amount);
        } else {
            // ERC20 token staking
            // Transfer tokens from user to ReputationManager first
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

            // Approve Treasury to spend the tokens
            IERC20(token).approve(address(TREASURY), amount);

            // Let treasury handle the deposit
            TREASURY.depositStake(msg.sender, token, amount);
        }

        _stakedAmounts[msg.sender] += amount;

        // Update user status if needed
        _updateUserStatus(msg.sender);

        // Update SBT if available
        if (address(hermisSBT) != address(0)) {
            hermisSBT.updateStakeAmount(msg.sender, _stakedAmounts[msg.sender]);
        }

        emit UserStaked(msg.sender, amount, token);
    }

    /// @notice Requests to unstake tokens, initiating the mandatory lock period
    /// @dev Users must wait UNSTAKE_LOCK_PERIOD (7 days) after requesting before they can complete unstaking.
    ///      This prevents rapid reputation manipulation through stake cycling.
    /// @custom:security Prevents immediate unstaking to maintain system stability
    function requestUnstake() external override {
        if (_stakedAmounts[msg.sender] == 0) revert InsufficientStake(msg.sender, 1, 0);
        if (_hasUnstakeRequest[msg.sender]) revert NoUnstakeRequest(msg.sender);

        _unstakeRequestTime[msg.sender] = block.timestamp + UNSTAKE_LOCK_PERIOD;
        _hasUnstakeRequest[msg.sender] = true;

        emit UnstakeRequested(msg.sender, _unstakeRequestTime[msg.sender]);
    }

    /// @notice Completes unstaking after the mandatory lock period has passed
    /// @dev Withdraws all staked tokens from Treasury and resets user's staking status.
    ///      Updates user status based on new conditions and syncs with SBT.
    /// @custom:security Protected by reentrancy guard, validates lock period completion
    /// @custom:treasury Tokens are withdrawn from Treasury back to user
    function unstake() external override nonReentrant {
        if (!_hasUnstakeRequest[msg.sender]) revert NoUnstakeRequest(msg.sender);
        if (block.timestamp < _unstakeRequestTime[msg.sender]) {
            revert UnstakeStillLocked(msg.sender, _unstakeRequestTime[msg.sender]);
        }

        uint256 stakedAmount = _stakedAmounts[msg.sender];
        if (stakedAmount == 0) revert InsufficientStake(msg.sender, 1, 0);

        _stakedAmounts[msg.sender] = 0;
        _hasUnstakeRequest[msg.sender] = false;
        _unstakeRequestTime[msg.sender] = 0;

        // Withdraw from treasury
        TREASURY.withdrawStake(msg.sender, STAKE_TOKEN, stakedAmount);

        // Update user status
        _updateUserStatus(msg.sender);

        // Update SBT if available
        if (address(hermisSBT) != address(0)) {
            hermisSBT.updateStakeAmount(msg.sender, 0);
        }

        emit UserUnstaked(msg.sender, stakedAmount, STAKE_TOKEN);
    }

    /// @notice Claims pending category score increases and updates SBT metadata
    /// @dev Converts pending category scores to active scores that are reflected in the user's SBT.
    ///      Pending scores are earned through successful task completion and accurate reviews.
    /// @param category Category name to claim scores for (e.g., "development", "design")
    /// @param scoreIncrease Amount of pending score to claim and make active
    /// @custom:sbt Updates SBT metadata with new active category score
    function claimCategoryScore(string calldata category, uint256 scoreIncrease) external override {
        if (scoreIncrease == 0) return;
        if (_pendingCategoryScores[msg.sender][category] < scoreIncrease) {
            revert InsufficientReputation(msg.sender, scoreIncrease, _pendingCategoryScores[msg.sender][category]);
        }

        _pendingCategoryScores[msg.sender][category] -= scoreIncrease;
        _categoryScores[msg.sender][category] += scoreIncrease;

        // Update SBT if available
        if (address(hermisSBT) != address(0)) {
            hermisSBT.updateCategoryScore(msg.sender, category, _categoryScores[msg.sender][category]);
        }

        emit CategoryScoreClaimed(msg.sender, category, scoreIncrease, _categoryScores[msg.sender][category]);
    }

    /// @notice Increases user reputation for arbitration and dispute resolution (admin only)
    /// @dev Used by contract owner for manual reputation adjustments during dispute resolution.
    ///      Validates that increase won't exceed MAX_REPUTATION before applying.
    /// @param user Address of the user whose reputation to increase
    /// @param increase Amount to increase reputation by (with 10x precision)
    /// @param reason Reason for the manual increase (for audit trail)
    /// @custom:security Only callable by contract owner for arbitration purposes
    /// @custom:validation Checks maximum reputation limits before applying
    function increaseReputationAdmin(
        address user,
        uint256 increase,
        string calldata reason
    ) external override onlyOwner {
        if (!canIncreaseReputation(user, increase)) {
            revert InvalidReputationChange(int256(increase));
        }

        _updateUserReputation(user, int256(increase), reason);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates if a user meets platform access requirements
    /// @dev Checks user initialization, blacklist status, and staking requirements for at-risk users.
    ///      Returns both boolean result and human-readable reason for better UX.
    /// @param user Address of the user to validate
    /// @return canAccess Whether the user can access platform features
    /// @return reason Human-readable reason if access is denied
    /// @custom:view This function is read-only and provides detailed access validation
    function validateUserAccess(address user) external view override returns (bool canAccess, string memory reason) {
        DataTypes.UserStatus status = _userStatus[user];

        if (status == DataTypes.UserStatus.UNINITIALIZED) {
            return (false, Messages.USER_NOT_INITIALIZED);
        }

        if (status == DataTypes.UserStatus.BLACKLISTED) {
            return (false, Messages.USER_BLACKLISTED);
        }

        if (status == DataTypes.UserStatus.AT_RISK) {
            uint256 requiredStake = _getRequiredStakeAmount(user);
            if (_stakedAmounts[user] < requiredStake) {
                return (false, Messages.INSUFFICIENT_STAKE_AT_RISK);
            }
        }

        return (true, Messages.ACCESS_GRANTED);
    }

    /// @notice Gets comprehensive user reputation and staking information
    /// @dev Returns all relevant user data in a single call for efficient frontend queries.
    ///      Includes reputation, status, staking details, and unstaking availability.
    /// @param user Address of the user to query
    /// @return reputation Current reputation score (with 10x precision)
    /// @return status Current platform status (NORMAL/AT_RISK/BLACKLISTED)
    /// @return stakedAmount Currently staked token amount
    /// @return canUnstake Whether user can complete unstaking now
    /// @return unstakeUnlockTime Timestamp when unstaking will be available (0 if no request)
    /// @custom:view This function is read-only and provides comprehensive user data
    function getUserReputation(
        address user
    )
        external
        view
        override
        returns (
            uint256 reputation,
            DataTypes.UserStatus status,
            uint256 stakedAmount,
            bool canUnstake,
            uint256 unstakeUnlockTime
        )
    {
        reputation = _reputationScores[user];
        status = _userStatus[user];
        stakedAmount = _stakedAmounts[user];
        canUnstake = _hasUnstakeRequest[user] && block.timestamp >= _unstakeRequestTime[user];
        unstakeUnlockTime = _unstakeRequestTime[user];
    }

    /// @notice Gets user's active category score for a specific category
    /// @dev Returns only claimed (active) category scores, not pending scores.
    ///      Category scores represent user expertise in specific domains.
    /// @param user Address of the user to query
    /// @param category Category name to get score for (e.g., "development", "design")
    /// @return score Current active category score for the user in the specified category
    /// @custom:view This function is read-only and returns active scores only
    function getCategoryScore(address user, string calldata category) external view override returns (uint256 score) {
        return _categoryScores[user][category];
    }

    /// @notice Gets the required stake amount for a user based on their reputation
    /// @dev Required stake is inversely proportional to reputation. Normal users (60+ reputation)
    ///      require no stake, while at-risk users need increasing stakes as reputation decreases.
    ///      Blacklisted users cannot stake their way out.
    /// @param user Address of the user to calculate required stake for
    /// @return requiredStake Required stake amount in tokens (0 for normal users, max for blacklisted)
    /// @custom:view This function is read-only and calculates dynamic staking requirements
    function getRequiredStakeAmount(address user) external view override returns (uint256 requiredStake) {
        return _getRequiredStakeAmount(user);
    }

    /// @notice Checks if user reputation can be increased without exceeding maximum
    /// @dev Validates that the proposed increase won't cause reputation to exceed MAX_REPUTATION.
    ///      Used by admin functions for pre-validation.
    /// @param user Address of the user whose reputation would be increased
    /// @param increase Amount to potentially increase reputation by (with 10x precision)
    /// @return canIncrease Whether the reputation increase is valid and within limits
    /// @custom:view This function is read-only and validates reputation limits
    function canIncreaseReputation(address user, uint256 increase) public view override returns (bool canIncrease) {
        uint256 currentReputation = _reputationScores[user];
        return currentReputation + increase <= MAX_REPUTATION;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to initialize a new user with default settings
    /// @dev Sets user to NORMAL status with DEFAULT_REPUTATION. Mints SBT if contract is configured.
    ///      Safe to call multiple times - returns early if user is already initialized.
    /// @param user Address of the user to initialize
    /// @custom:sbt Mints Hermis SBT for the user if SBT contract is set
    function _initializeUser(address user) internal {
        if (_userStatus[user] != DataTypes.UserStatus.UNINITIALIZED) {
            return; // User already initialized
        }

        _reputationScores[user] = DEFAULT_REPUTATION;
        _userStatus[user] = DataTypes.UserStatus.NORMAL;
        _lastClaimTime[user] = block.timestamp;

        // Mint SBT for user if SBT contract is set
        if (address(hermisSBT) != address(0)) {
            hermisSBT.mint(user);
        }

        emit UserInitialized(user, DEFAULT_REPUTATION);
    }

    /// @notice Internal function to calculate required stake amount based on user reputation
    /// @dev Implements inverse relationship between reputation and required stake.
    ///      Formula: baseStake * (NORMAL_THRESHOLD - reputation) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD)
    /// @param user Address of the user to calculate stake for
    /// @return requiredStake Required stake amount (0 for normal, max for blacklisted, scaled for at-risk)
    /// @custom:formula Uses linear interpolation for at-risk users between thresholds
    function _getRequiredStakeAmount(address user) internal view returns (uint256 requiredStake) {
        uint256 reputation = _reputationScores[user];

        if (reputation >= NORMAL_THRESHOLD) {
            return 0; // No staking required for normal users
        }

        if (reputation <= BLACKLIST_THRESHOLD) {
            return type(uint256).max; // Cannot stake out of blacklist
        }

        // At-risk users: stake requirement inversely proportional to reputation
        // Lower reputation = higher stake required
        // Formula: baseStake * (NORMAL_THRESHOLD - reputation) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD)
        requiredStake = (baseStake * (NORMAL_THRESHOLD - reputation)) / (NORMAL_THRESHOLD - AT_RISK_THRESHOLD);
    }

    /// @notice Internal function to update user reputation with bounds checking
    /// @dev Handles both positive and negative reputation changes with proper bounds checking.
    ///      Updates user status, syncs with SBT, and emits events for transparency.
    /// @param user Address of the user whose reputation to update
    /// @param change Reputation change amount (can be positive or negative)
    /// @param reason Human-readable reason for the change
    /// @custom:bounds Ensures reputation stays between 0 and MAX_REPUTATION
    /// @custom:sbt Updates SBT with new reputation and status information
    function _updateUserReputation(address user, int256 change, string memory reason) internal {
        uint256 currentReputation = _reputationScores[user];
        uint256 newReputation;

        if (change < 0) {
            uint256 decrease = uint256(-change);
            if (decrease >= currentReputation) {
                newReputation = 0;
            } else {
                newReputation = currentReputation - decrease;
            }
        } else {
            uint256 increase = uint256(change);
            newReputation = currentReputation + increase;
            if (newReputation > MAX_REPUTATION) {
                newReputation = MAX_REPUTATION;
            }
        }

        DataTypes.UserStatus oldStatus = _userStatus[user];
        _reputationScores[user] = newReputation;
        _updateUserStatus(user);

        // Update SBT if available
        if (address(hermisSBT) != address(0)) {
            hermisSBT.updateReputation(user, newReputation, _userStatus[user]);
        }

        emit ReputationChanged(user, change, newReputation, reason);

        if (oldStatus != _userStatus[user]) {
            emit UserStatusChanged(user, oldStatus, _userStatus[user]);
        }
    }

    /// @notice Internal function to update user status based on current reputation
    /// @dev Determines user status based on reputation thresholds and updates storage.
    ///      NORMAL: 60+, AT_RISK: 10-59, BLACKLISTED: 0-9 (with 10x precision)
    /// @param user Address of the user whose status to update
    /// @custom:thresholds Uses NORMAL_THRESHOLD, AT_RISK_THRESHOLD, and BLACKLIST_THRESHOLD
    function _updateUserStatus(address user) internal {
        uint256 reputation = _reputationScores[user];
        DataTypes.UserStatus currentStatus = _userStatus[user];
        DataTypes.UserStatus newStatus;

        if (reputation >= NORMAL_THRESHOLD) {
            newStatus = DataTypes.UserStatus.NORMAL;
        } else if (reputation > BLACKLIST_THRESHOLD) {
            newStatus = DataTypes.UserStatus.AT_RISK;
        } else {
            newStatus = DataTypes.UserStatus.BLACKLISTED;
        }

        if (newStatus != currentStatus) {
            _userStatus[user] = newStatus;
            emit UserStatusChanged(user, currentStatus, newStatus);
        }
    }

    /// @notice Adds pending category score that user can later claim
    /// @dev Called by authorized contracts when users earn category expertise through successful
    ///      task completion or accurate reviews. Scores remain pending until manually claimed.
    /// @param user Address of the user to award pending score to
    /// @param category Category name to add score for (e.g., "development", "design")
    /// @param score Amount of pending score to add
    /// @custom:security Only callable by authorized system contracts
    /// @custom:pending Scores must be manually claimed to become active and update SBT
    function addPendingCategoryScore(address user, string calldata category, uint256 score) external onlyAuthorized {
        _pendingCategoryScores[user][category] += score;
    }
}
