// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// 2. Internal interfaces
import {IAllowlistManager} from "../interfaces/IAllowlistManager.sol";
import {IReputationManager} from "../interfaces/IReputationManager.sol";
import {ITaskManager} from "../interfaces/ITaskManager.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

// 3. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";
import {Messages} from "../libraries/Messages.sol";

/// @title TaskManager
/// @notice Manages task creation, publication, and lifecycle in the Hermis crowdsourcing platform
/// @dev This contract implements the core task management functionality including:
///      - Task creation with configurable guards and adoption strategies for flexible validation
///      - Complete task lifecycle management (DRAFT → PUBLISHED → ACTIVE → COMPLETED/CANCELLED/EXPIRED)
///      - Reward management integration with Treasury for secure fund handling
///      - Reputation-based access control through ReputationManager integration
///      - Extensible guard system for submission and review validation
///      - Adoption strategy system for determining winning submissions
///      - Category-based task organization and pagination support
/// @custom:security All monetary operations are secured with ReentrancyGuard and proper access controls
/// @custom:upgradeable This contract is upgradeable and uses OpenZeppelin's proxy pattern
/// @author Hermis Team
contract TaskManager is ITaskManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Core mapping storing all task information by ID
    mapping(uint256 => DataTypes.TaskInfo) private _tasks;

    /// @notice Mapping of publisher addresses to their created task IDs for efficient publisher queries
    mapping(address => uint256[]) private _publisherTasks;

    /// @notice Mapping of category names to task IDs for category-based browsing
    mapping(string => uint256[]) private _categoryTasks;

    /// @notice Counter for generating unique task IDs, starts from 1
    uint256 private _nextTaskId;

    /// @notice Total number of tasks ever created for statistics
    uint256 private _totalTasks;

    /// @notice Treasury contract interface for reward management
    ITreasury public treasury;

    /// @notice ReputationManager contract interface for user validation
    IReputationManager public reputationManager;

    /// @notice AllowlistManager contract interface for validating guards, strategies, and tokens
    IAllowlistManager public allowlistManager;

    /// @notice Mapping of authorized contracts that can interact with tasks (e.g., SubmissionManager)
    /// @dev Used to restrict sensitive operations like completeTask to authorized system contracts
    mapping(address => bool) public authorizedContracts;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Minimum task duration to prevent spam and ensure reasonable completion time
    uint256 private constant _MIN_TASK_DURATION = 1 hours;

    /// @notice Maximum task duration to prevent indefinite tasks
    uint256 private constant _MAX_TASK_DURATION = 365 days;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier taskExists(uint256 taskId) {
        if (taskId == 0 || taskId >= _nextTaskId) revert TaskNotFound(taskId);
        _;
    }

    modifier onlyTaskPublisher(uint256 taskId) {
        if (_tasks[taskId].publisher != msg.sender) {
            revert UnauthorizedTaskAction(msg.sender, taskId);
        }
        _;
    }

    modifier onlyAuthorized() {
        // Allow owner and authorized contracts (like SubmissionManager)
        if (msg.sender != owner() && !authorizedContracts[msg.sender]) {
            revert UnauthorizedTaskAction(msg.sender, 0);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Constructor that disables initializers for upgradeable contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the TaskManager contract with required dependencies
    /// @dev This function is called once during proxy deployment to set up the contract
    /// @param owner Owner address with administrative privileges
    /// @param treasuryAddress Treasury contract address for reward management
    /// @param reputationManagerAddress ReputationManager contract address for user validation
    /// @param allowlistManagerAddress AllowlistManager contract address for validating guards, strategies, and tokens
    /// @custom:security Only callable once due to initializer modifier
    function initialize(
        address owner,
        address treasuryAddress,
        address reputationManagerAddress,
        address allowlistManagerAddress
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();

        treasury = ITreasury(treasuryAddress);
        reputationManager = IReputationManager(reputationManagerAddress);
        allowlistManager = IAllowlistManager(allowlistManagerAddress);
        _nextTaskId = 1; // Start task IDs from 1
    }

    /// @notice Sets authorization status for a contract to interact with tasks
    /// @dev Used to grant permission to system contracts like SubmissionManager to call restricted functions
    /// @param contractAddress Address of the contract to authorize/deauthorize
    /// @param authorized Whether the contract should be authorized
    /// @custom:security Only callable by contract owner to prevent unauthorized access
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
    }

    /// @notice Sets the AllowlistManager contract address
    /// @dev Allows updating the AllowlistManager for system upgrades
    /// @param newAllowlistManager Address of the new AllowlistManager contract
    /// @custom:security Only callable by contract owner
    function setAllowlistManager(address newAllowlistManager) external onlyOwner {
        allowlistManager = IAllowlistManager(newAllowlistManager);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates a new task in DRAFT status
    /// @dev Creates a task that can be configured before publishing. Validates user access through ReputationManager
    ///      and validates all guard contracts and adoption strategy before creation. Task starts in DRAFT status
    ///      and must be published separately to become active.
    /// @param title Task title (must not be empty)
    /// @param description Task description providing detailed information
    /// @param requirements Task requirements specifying what submitters need to deliver
    /// @param category Task category for organization and filtering
    /// @param deadline Task deadline timestamp (must be between MIN_TASK_DURATION and MAX_TASK_DURATION from now)
    /// @param reward Reward amount to be paid to the winning submission (must be > 0)
    /// @param rewardToken Reward token address (address(0) for ETH)
    /// @param submissionGuard Address of submission validation guard (can be address(0) for no guard)
    /// @param reviewGuard Address of review validation guard (can be address(0) for no guard)
    /// @param adoptionStrategy Address of adoption strategy contract (required, cannot be address(0))
    /// @return taskId ID of the created task
    /// @custom:security Protected by reentrancy guard and validates user access
    /// @custom:validation Validates all input parameters and contract interfaces
    function createTask(
        string calldata title,
        string calldata description,
        string calldata requirements,
        string calldata category,
        uint256 deadline,
        uint256 reward,
        address rewardToken,
        address submissionGuard,
        address reviewGuard,
        address adoptionStrategy
    ) external override nonReentrant returns (uint256 taskId) {
        // Validate inputs
        if (bytes(title).length == 0) revert InvalidTaskTitle(title);
        if (deadline <= block.timestamp + _MIN_TASK_DURATION) revert InvalidTaskDeadline(deadline);
        if (deadline > block.timestamp + _MAX_TASK_DURATION) revert InvalidTaskDeadline(deadline);
        if (reward == 0) revert InvalidTaskReward(reward);

        // Initialize user if needed
        reputationManager.initializeUser(msg.sender);

        // Validate user can publish tasks
        (bool canAccess, ) = reputationManager.validateUserAccess(msg.sender);
        if (!canAccess) revert UnauthorizedTaskAction(msg.sender, 0);

        // Validate task configuration using AllowlistManager
        (bool isValid, ) = allowlistManager.validateTaskConfig(
            submissionGuard,
            reviewGuard,
            adoptionStrategy,
            rewardToken
        );
        if (!isValid) revert InvalidConfiguration();

        taskId = _nextTaskId;
        unchecked {
            ++_nextTaskId;
            ++_totalTasks;
        }

        // Create task struct
        DataTypes.TaskInfo storage task = _tasks[taskId];
        task.id = taskId;
        task.publisher = msg.sender;
        task.title = title;
        task.description = description;
        task.requirements = requirements;
        task.category = category;
        task.deadline = deadline;
        task.reward = reward;
        task.rewardToken = rewardToken;
        task.status = DataTypes.TaskStatus.DRAFT;
        task.createdAt = block.timestamp;
        task.submissionGuard = submissionGuard;
        task.reviewGuard = reviewGuard;
        task.adoptionStrategy = adoptionStrategy;
        task.adoptedSubmissionId = 0;

        // Add to publisher's tasks
        _publisherTasks[msg.sender].push(taskId);

        emit TaskCreated(taskId, msg.sender, title, category, deadline, reward, rewardToken);
    }

    /// @notice Publishes a draft task to make it available for submissions
    /// @dev Transfers reward to Treasury and changes task status to PUBLISHED. For ETH rewards,
    ///      the reward amount must be sent with the transaction. For ERC20 rewards, approval is required.
    ///      Once published, the task becomes visible and accepts submissions.
    /// @param taskId ID of the task to publish
    /// @custom:security Protected by reentrancy guard, validates task ownership and status
    /// @custom:economy Handles reward transfer to Treasury for escrow
    function publishTask(
        uint256 taskId
    ) external payable override taskExists(taskId) onlyTaskPublisher(taskId) nonReentrant {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status != DataTypes.TaskStatus.DRAFT) {
            revert TaskNotActive(taskId);
        }

        if (task.deadline <= block.timestamp) {
            revert InvalidTaskDeadline(task.deadline);
        }

        // Transfer reward to treasury
        if (task.rewardToken == address(0)) {
            // ETH reward must match the configured amount
            if (msg.value != task.reward) {
                revert ITreasury.InsufficientBalance(task.rewardToken, task.reward, msg.value);
            }

            treasury.depositTaskReward{value: msg.value}(taskId, task.rewardToken, task.reward);
        } else {
            // ERC20 reward: transfer into TaskManager, then escrow via Treasury
            IERC20 rewardToken = IERC20(task.rewardToken);
            rewardToken.safeTransferFrom(msg.sender, address(this), task.reward);
            rewardToken.forceApprove(address(treasury), task.reward);

            treasury.depositTaskReward(taskId, task.rewardToken, task.reward);
        }

        // Update task status
        task.status = DataTypes.TaskStatus.PUBLISHED;

        // Add to category tasks for categorization
        _categoryTasks[task.category].push(taskId);

        emit TaskPublished(taskId, block.timestamp);
    }

    /// @notice Cancels a task and refunds the reward if already deposited
    /// @dev Allows task publishers to cancel tasks in DRAFT or PUBLISHED status. Applies a reputation
    ///      penalty to discourage frivolous cancellations. If the task was published, refunds the reward
    ///      from Treasury back to the publisher.
    /// @param taskId ID of the task to cancel
    /// @param reason Reason for cancellation (for transparency and record-keeping)
    /// @custom:security Only callable by task publisher, validates task status, protected by reentrancy guard
    /// @custom:economy Handles reward refund and applies reputation penalty
    function cancelTask(
        uint256 taskId,
        string calldata reason
    ) external override taskExists(taskId) onlyTaskPublisher(taskId) nonReentrant {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status != DataTypes.TaskStatus.PUBLISHED && task.status != DataTypes.TaskStatus.DRAFT) {
            revert TaskCannotBeCancelled(taskId);
        }

        // Check if task has submissions (this would need to be checked via SubmissionManager)
        // For now, we'll allow cancellation if task is not ACTIVE

        DataTypes.TaskStatus oldStatus = task.status;
        task.status = DataTypes.TaskStatus.CANCELLED;

        // Refund reward if it was already deposited
        if (oldStatus == DataTypes.TaskStatus.PUBLISHED) {
            treasury.withdrawTaskReward(taskId, task.publisher, task.rewardToken, task.reward);
        }

        // Update reputation (small penalty for cancellation)
        reputationManager.updateReputation(
            msg.sender,
            -50, // -5.0 reputation penalty
            Messages.TASK_CANCELLATION
        );

        emit TaskCancelled(taskId, reason);
    }

    /// @notice Marks a task as expired when deadline passes without completion
    /// @dev Can be called by anyone after the task deadline to expire the task and refund the reward
    ///      to the publisher. Removes the task from active tasks and changes status to EXPIRED.
    /// @param taskId ID of the task to expire
    /// @custom:security Validates task status and deadline before expiration
    /// @custom:economy Refunds reward from Treasury back to publisher
    function expireTask(uint256 taskId) external override taskExists(taskId) {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status != DataTypes.TaskStatus.PUBLISHED && task.status != DataTypes.TaskStatus.ACTIVE) {
            revert TaskNotActive(taskId);
        }

        if (block.timestamp < task.deadline) {
            revert TaskNotActive(taskId); // Task not yet expired
        }

        task.status = DataTypes.TaskStatus.EXPIRED;

        // Refund reward to publisher
        treasury.withdrawTaskReward(taskId, task.publisher, task.rewardToken, task.reward);

        emit TaskExpiredEvent(taskId);
    }

    /// @notice Completes a task when a submission is adopted by the adoption strategy
    /// @dev Only callable by authorized contracts (like SubmissionManager) when a submission
    ///      is selected as the winner. Changes task status to COMPLETED and records the winning submission.
    ///      The actual reward distribution is handled by the calling contract.
    /// @param taskId ID of the task to complete
    /// @param adoptedSubmissionId ID of the adopted submission that won the task
    /// @custom:security Only callable by authorized system contracts
    /// @custom:integration Called by SubmissionManager during submission adoption process
    function completeTask(
        uint256 taskId,
        uint256 adoptedSubmissionId
    ) external override onlyAuthorized taskExists(taskId) {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status != DataTypes.TaskStatus.PUBLISHED && task.status != DataTypes.TaskStatus.ACTIVE) {
            revert TaskNotActive(taskId);
        }

        task.status = DataTypes.TaskStatus.COMPLETED;
        task.adoptedSubmissionId = adoptedSubmissionId;

        emit TaskCompleted(taskId, adoptedSubmissionId);
    }

    /// @notice Updates task guards and adoption strategy (only for draft tasks)
    /// @dev Allows publishers to modify validation logic before publishing. Only works on DRAFT tasks
    ///      to prevent changing rules after submissions begin. Validates all contracts before updating.
    /// @param taskId ID of the task to update
    /// @param submissionGuard New submission guard address (can be address(0) for no guard)
    /// @param reviewGuard New review guard address (can be address(0) for no guard)
    /// @param adoptionStrategy New adoption strategy address (required, cannot be address(0))
    /// @custom:security Only callable by task publisher on draft tasks
    /// @custom:validation Validates all contract interfaces before updating
    function updateTaskGuards(
        uint256 taskId,
        address submissionGuard,
        address reviewGuard,
        address adoptionStrategy
    ) external override taskExists(taskId) onlyTaskPublisher(taskId) {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status != DataTypes.TaskStatus.DRAFT) {
            revert TaskNotActive(taskId); // Can only update drafts
        }

        // Validate task configuration using AllowlistManager
        (bool isValid, ) = allowlistManager.validateTaskConfig(
            submissionGuard,
            reviewGuard,
            adoptionStrategy,
            address(0)
        );
        if (!isValid) revert InvalidConfiguration();

        task.submissionGuard = submissionGuard;
        task.reviewGuard = reviewGuard;
        task.adoptionStrategy = adoptionStrategy;

        emit TaskGuardsUpdated(taskId, submissionGuard, reviewGuard, adoptionStrategy);
    }

    /// @notice Increases the reward amount for a task to attract more submissions
    /// @dev Allows task publisher to add additional rewards. Only increases are permitted.
    ///      The reward token type cannot be changed. Task must not be completed or cancelled.
    ///      For ETH rewards, msg.value must equal additionalReward.
    ///      For ERC20 rewards, tokens are transferred from publisher to treasury.
    /// @param taskId ID of the task to increase reward for
    /// @param additionalReward Additional reward amount to add (must be > 0)
    /// @custom:security Only publisher can call, validates token type unchanged
    /// @custom:payable Must send exact ETH amount for native token rewards
    function increaseTaskReward(
        uint256 taskId,
        uint256 additionalReward
    ) external payable override taskExists(taskId) onlyTaskPublisher(taskId) nonReentrant {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        // Validate task is in a state that can accept reward increases
        if (
            task.status == DataTypes.TaskStatus.COMPLETED ||
            task.status == DataTypes.TaskStatus.CANCELLED ||
            task.status == DataTypes.TaskStatus.EXPIRED
        ) {
            revert TaskNotActive(taskId);
        }

        // Validate additional reward is positive
        if (additionalReward == 0) {
            revert InvalidTaskReward(additionalReward);
        }

        uint256 previousReward = task.reward;
        uint256 newReward = previousReward + additionalReward;

        // Handle reward token transfer
        if (task.rewardToken == address(0)) {
            // Native ETH reward
            if (msg.value != additionalReward) {
                revert ITreasury.InsufficientBalance(task.rewardToken, additionalReward, msg.value);
            }
            // Deposit additional ETH to treasury
            treasury.depositTaskReward{value: msg.value}(taskId, task.rewardToken, additionalReward);
        } else {
            // ERC20 token reward
            IERC20 rewardToken = IERC20(task.rewardToken);
            rewardToken.safeTransferFrom(msg.sender, address(this), additionalReward);
            rewardToken.forceApprove(address(treasury), additionalReward);
            treasury.depositTaskReward(taskId, task.rewardToken, additionalReward);
        }

        // Update task reward
        task.reward = newReward;

        emit TaskRewardIncreased(taskId, msg.sender, previousReward, newReward, task.rewardToken);
    }

    /// @notice Sets task status to ACTIVE when first submission is received
    /// @dev Called by SubmissionManager when the first valid submission is made to a PUBLISHED task.
    ///      This indicates that the task has active participation and work is in progress.
    /// @param taskId ID of the task to activate
    /// @custom:security Only callable by authorized system contracts
    /// @custom:integration Called by SubmissionManager during submission creation
    function activateTask(uint256 taskId) external override onlyAuthorized taskExists(taskId) {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status == DataTypes.TaskStatus.PUBLISHED) {
            task.status = DataTypes.TaskStatus.ACTIVE;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets complete task information
    /// @dev Returns the full TaskInfo struct with all task details including status, rewards,
    ///      guards, and metadata. This is the primary function for retrieving task data.
    /// @param taskId ID of the task to retrieve
    /// @return task Complete task information struct
    /// @custom:view This function is read-only and does not modify state
    function getTask(
        uint256 taskId
    ) external view override taskExists(taskId) returns (DataTypes.TaskInfo memory task) {
        return _tasks[taskId];
    }

    /// @notice Gets tasks created by a specific publisher with pagination
    /// @dev Returns paginated array of task IDs for the specified publisher. Useful for
    ///      displaying publisher profiles and task history.
    /// @param publisher Address of the publisher to query
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of tasks to return (for gas efficiency)
    /// @return taskIds Array of task IDs created by the publisher
    /// @custom:view This function is read-only and supports pagination
    function getTasksByPublisher(
        address publisher,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory taskIds) {
        uint256[] storage publisherTasks = _publisherTasks[publisher];
        return _paginateArray(publisherTasks, offset, limit);
    }

    /// @notice Gets tasks in a specific category with pagination
    /// @dev Returns paginated array of task IDs for the specified category. Useful for
    ///      category-based browsing and filtering of tasks.
    /// @param category Category name to filter by
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of tasks to return (for gas efficiency)
    /// @return taskIds Array of task IDs in the specified category
    /// @custom:view This function is read-only and supports pagination
    function getTasksByCategory(
        string calldata category,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory taskIds) {
        uint256[] storage categoryTasks = _categoryTasks[category];
        return _paginateArray(categoryTasks, offset, limit);
    }

    /// @notice Checks if a task can accept new submissions with detailed reason
    /// @dev Validates task status and deadline to determine if submissions are allowed.
    ///      Returns both a boolean result and human-readable reason for better UX.
    /// @param taskId ID of the task to check
    /// @return canAccept Whether the task can accept new submissions
    /// @return reason Human-readable reason if submissions are not accepted
    /// @custom:view This function is read-only and provides detailed feedback
    function canAcceptSubmissions(
        uint256 taskId
    ) external view override taskExists(taskId) returns (bool canAccept, string memory reason) {
        DataTypes.TaskInfo storage task = _tasks[taskId];

        if (task.status == DataTypes.TaskStatus.COMPLETED) {
            return (false, Messages.TASK_ALREADY_COMPLETED);
        }

        if (task.status == DataTypes.TaskStatus.CANCELLED) {
            return (false, Messages.TASK_CANCELLED);
        }

        if (task.status == DataTypes.TaskStatus.EXPIRED) {
            return (false, Messages.TASK_EXPIRED);
        }

        if (task.status == DataTypes.TaskStatus.DRAFT) {
            return (false, Messages.TASK_NOT_PUBLISHED);
        }

        if (block.timestamp >= task.deadline) {
            return (false, Messages.TASK_DEADLINE_PASSED);
        }

        return (true, Messages.TASK_ACCEPTING_SUBMISSIONS);
    }

    /// @notice Gets total number of tasks ever created
    /// @dev Returns the total count of tasks created since contract deployment.
    ///      Useful for statistics and pagination calculations.
    /// @return totalTasks Total task count across all statuses
    /// @custom:view This function is read-only and provides platform statistics
    function getTotalTasks() external view override returns (uint256 totalTasks) {
        return _totalTasks;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Paginates an array with bounds checking
    /// @dev Generic pagination function that handles edge cases like offset beyond array length.
    ///      Returns empty array for invalid offsets and adjusts end index for boundary cases.
    /// @param array Source storage array to paginate
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of items to return
    /// @return result Paginated array slice
    /// @custom:optimization Efficient pagination with proper bounds checking
    function _paginateArray(
        uint256[] storage array,
        uint256 offset,
        uint256 limit
    ) internal view returns (uint256[] memory result) {
        uint256 arrayLength = array.length;

        if (offset >= arrayLength) {
            return new uint256[](0);
        }

        uint256 end = offset + limit;
        if (end > arrayLength) {
            end = arrayLength;
        }

        uint256 resultLength = end - offset;
        result = new uint256[](resultLength);

        for (uint256 i = 0; i < resultLength; ) {
            result[i] = array[offset + i];
            unchecked {
                ++i;
            }
        }
    }
}
