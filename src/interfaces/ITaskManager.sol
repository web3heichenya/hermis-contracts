// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title ITaskManager
/// @notice Interface for comprehensive task lifecycle management within the Hermis platform
/// @dev This interface defines the standard task management functionality including:
///      - Task creation with customizable guards and adoption strategies
///      - Task lifecycle management from draft to completion or expiration
///      - Reward escrow and distribution coordination with treasury
///      - Query functions for task discovery, filtering, and status tracking
/// @custom:interface Defines standard task behavior for work coordination and completion
/// @author Hermis Team
interface ITaskManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when task ID does not exist in the system
    error TaskNotFound(uint256 taskId);

    /// @notice Error when attempting operations on inactive tasks
    error TaskNotActive(uint256 taskId);

    /// @notice Error when task deadline has passed
    error TaskExpired(uint256 taskId);

    /// @notice Error when attempting to modify a completed task
    error TaskAlreadyCompleted(uint256 taskId);

    /// @notice Error when caller lacks permission to perform task action
    error UnauthorizedTaskAction(address caller, uint256 taskId);

    /// @notice Error when task deadline is invalid or in the past
    error InvalidTaskDeadline(uint256 deadline);

    /// @notice Error when task reward amount is invalid or insufficient
    error InvalidTaskReward(uint256 reward);

    /// @notice Error when task title is empty or invalid
    error InvalidTaskTitle(string title);

    /// @notice Error when task cannot be cancelled due to existing submissions
    error TaskCannotBeCancelled(uint256 taskId);

    /// @notice Error thrown when invalid configuration is provided
    error InvalidConfiguration();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new task is created in the system
    /// @param taskId Unique ID of the newly created task
    /// @param publisher Address of the user who created the task
    /// @param title Descriptive title of the task
    /// @param category Category classification of the task
    /// @param deadline Unix timestamp when the task expires
    /// @param reward Total reward amount for task completion
    /// @param rewardToken Address of the reward token (zero address for native token)
    event TaskCreated(
        uint256 indexed taskId,
        address indexed publisher,
        string title,
        string category,
        uint256 deadline,
        uint256 reward,
        address rewardToken
    );

    /// @notice Emitted when a draft task is published and becomes active
    /// @param taskId ID of the task that was published
    /// @param publishedAt Timestamp when the task was published
    event TaskPublished(uint256 indexed taskId, uint256 publishedAt);

    /// @notice Emitted when a task is completed with an adopted submission
    /// @param taskId ID of the task that was completed
    /// @param adoptedSubmissionId ID of the submission that was adopted as the solution
    event TaskCompleted(uint256 indexed taskId, uint256 adoptedSubmissionId);

    /// @notice Emitted when a task expires due to deadline passing
    /// @param taskId ID of the task that expired
    event TaskExpiredEvent(uint256 indexed taskId);

    /// @notice Emitted when a task is cancelled by the publisher
    /// @param taskId ID of the task that was cancelled
    /// @param reason Human-readable explanation for the cancellation
    event TaskCancelled(uint256 indexed taskId, string reason);

    /// @notice Emitted when task guards and adoption strategy are updated
    /// @param taskId ID of the task whose configuration was updated
    /// @param submissionGuard Address of the new submission validation guard
    /// @param reviewGuard Address of the new review validation guard
    /// @param adoptionStrategy Address of the new adoption strategy contract
    event TaskGuardsUpdated(
        uint256 indexed taskId,
        address submissionGuard,
        address reviewGuard,
        address adoptionStrategy
    );

    /// @notice Emitted when task reward is increased
    /// @param taskId ID of the task
    /// @param publisher Address of the task publisher who increased the reward
    /// @param previousReward Previous reward amount
    /// @param newReward New reward amount after increase
    /// @param rewardToken Token address for the reward (address(0) for ETH)
    event TaskRewardIncreased(
        uint256 indexed taskId,
        address indexed publisher,
        uint256 previousReward,
        uint256 newReward,
        address rewardToken
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      TASK FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates a new task with specified requirements and reward structure
    /// @dev Creates a task in draft state with customizable guards and adoption strategy.
    ///      Should validate all parameters and set up reward escrow preparation.
    /// @param title Descriptive title summarizing the task objective
    /// @param description Detailed description of work to be performed
    /// @param requirements Specific technical or quality requirements for submissions
    /// @param category Category classification for task discovery and filtering
    /// @param deadline Unix timestamp when task expires and stops accepting submissions
    /// @param reward Total reward amount to be distributed upon task completion
    /// @param rewardToken Address of ERC-20 token for rewards (zero address for native token)
    /// @param submissionGuard Address of guard contract for submission validation
    /// @param reviewGuard Address of guard contract for reviewer validation
    /// @param adoptionStrategy Address of strategy contract for submission adoption logic
    /// @return taskId Unique identifier of the created task
    /// @custom:security Validates all contract addresses and parameters before creation
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
    ) external returns (uint256 taskId);

    /// @notice Publishes a draft task to active status and accepts submissions
    /// @dev Activates task for submissions and locks reward funds in treasury escrow.
    ///      Should validate reward deposit and update task status to active.
    /// @param taskId ID of the draft task to publish and activate
    /// @custom:security Requires reward deposit and validates task readiness for publication
    function publishTask(uint256 taskId) external payable;

    /// @notice Cancels an active task before any submissions are received
    /// @dev Allows publisher to cancel task and retrieve deposited rewards.
    ///      Should validate no submissions exist and return funds to publisher.
    /// @param taskId ID of the active task to cancel
    /// @param reason Human-readable explanation for task cancellation
    /// @custom:security Only callable by task publisher, only before submissions exist
    function cancelTask(uint256 taskId, string calldata reason) external;

    /// @notice Marks a task as expired when the deadline timestamp has passed
    /// @dev Transitions task to expired state and handles reward refund if no adoption.
    ///      Should validate deadline has passed and update task status accordingly.
    /// @param taskId ID of the task to mark as expired
    /// @custom:security Can be called by anyone after deadline passes
    function expireTask(uint256 taskId) external;

    /// @notice Activates a draft task for internal system coordination
    /// @dev Internal function to transition task from draft to active state.
    ///      Should validate task readiness and update status for submission acceptance.
    /// @param taskId ID of the draft task to activate internally
    /// @custom:security Only callable by authorized system contracts
    function activateTask(uint256 taskId) external;

    /// @notice Completes a task when a submission is successfully adopted
    /// @dev Finalizes task completion and triggers reward distribution to participants.
    ///      Should coordinate with treasury for reward distribution processing.
    /// @param taskId ID of the task to mark as completed
    /// @param adoptedSubmissionId ID of the submission that was adopted as the solution
    /// @custom:security Only callable by authorized adoption contracts, triggers reward distribution
    function completeTask(uint256 taskId, uint256 adoptedSubmissionId) external;

    /// @notice Updates task guards and adoption strategy before task publication
    /// @dev Allows publisher to modify validation contracts before task becomes active.
    ///      Should validate contract addresses implement required interfaces.
    /// @param taskId ID of the draft task to update configuration for
    /// @param submissionGuard New address of submission validation guard contract
    /// @param reviewGuard New address of review validation guard contract
    /// @param adoptionStrategy New address of adoption strategy contract
    /// @custom:security Only callable by task publisher before task is published
    function updateTaskGuards(
        uint256 taskId,
        address submissionGuard,
        address reviewGuard,
        address adoptionStrategy
    ) external;

    /// @notice Increases the reward amount for a task
    /// @dev Allows task publisher to increase reward to attract more submissions.
    ///      Only the publisher can call this function. The reward can only be increased, not decreased.
    ///      The reward token type cannot be changed. Requires transferring additional tokens to treasury.
    /// @param taskId ID of the task to increase reward for
    /// @param additionalReward Additional reward amount to add to current reward
    /// @custom:security Only publisher can increase reward, only allows increases (not decreases)
    /// @custom:payable For ETH rewards, msg.value must equal additionalReward
    function increaseTaskReward(uint256 taskId, uint256 additionalReward) external payable;

    /// @notice Gets complete task information including status and configuration
    /// @dev Returns full task details for display and processing validation.
    /// @param taskId ID of the task to retrieve information for
    /// @return task Complete task data structure with metadata, status, and configuration
    /// @custom:view This function is read-only and returns comprehensive task details
    function getTask(uint256 taskId) external view returns (DataTypes.TaskInfo memory task);

    /// @notice Gets paginated list of tasks created by a specific publisher
    /// @dev Returns task IDs for publisher profile and activity tracking.
    /// @param publisher Address of the user who published the tasks
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of task IDs to return in this batch
    /// @return taskIds Array of task IDs published by the specified user
    /// @custom:view This function is read-only and supports pagination
    function getTasksByPublisher(
        address publisher,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory taskIds);

    /// @notice Gets paginated list of tasks filtered by category
    /// @dev Returns task IDs for category-based discovery and specialization.
    /// @param category String identifier of the task category to filter by
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of task IDs to return in this batch
    /// @return taskIds Array of task IDs in the specified category
    /// @custom:view This function is read-only and supports pagination
    function getTasksByCategory(
        string calldata category,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory taskIds);

    /// @notice Validates whether a task can currently accept new submissions
    /// @dev Checks task status, deadline, and completion state for submission eligibility.
    /// @param taskId ID of the task to validate submission acceptance for
    /// @return canAccept Whether the task is currently accepting new submissions
    /// @return reason Human-readable explanation if submissions are not accepted
    /// @custom:view This function is read-only and validates submission eligibility
    function canAcceptSubmissions(uint256 taskId) external view returns (bool canAccept, string memory reason);

    /// @notice Gets the total number of tasks created across the platform
    /// @dev Returns cumulative count of all tasks for statistical purposes.
    /// @return totalTasks Total task count across all categories and statuses
    /// @custom:view This function is read-only and returns cumulative statistics
    function getTotalTasks() external view returns (uint256 totalTasks);
}
