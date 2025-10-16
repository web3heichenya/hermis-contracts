// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Messages
/// @notice Centralized message strings for consistent user-facing text across the Hermis platform
/// @dev This library provides constant string messages for return values in view functions.
///      Using a centralized library offers several benefits:
///      - Consistency: Same messages across all contracts
///      - Maintainability: Update messages in one place
///      - Internationalization: Easy to replace with multi-language support
///      - Code clarity: Descriptive constant names instead of magic strings
///
///      All constants are public and can be accessed directly via Messages.CONSTANT_NAME
/// @custom:note For error conditions, use custom errors (more gas-efficient than string messages)
/// @author Hermis Team
library Messages {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    TASK STATUS MESSAGES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message when task is already completed and cannot accept new submissions
    string public constant TASK_ALREADY_COMPLETED = "Task already completed";

    /// @notice Message when task has been cancelled by the publisher
    string public constant TASK_CANCELLED = "Task cancelled";

    /// @notice Message when task has expired past its deadline
    string public constant TASK_EXPIRED = "Task expired";

    /// @notice Message when task is still in draft status and not yet published
    string public constant TASK_NOT_PUBLISHED = "Task not published";

    /// @notice Message when task deadline has passed
    string public constant TASK_DEADLINE_PASSED = "Task deadline passed";

    /// @notice Message when task is successfully accepting submissions
    string public constant TASK_ACCEPTING_SUBMISSIONS = "Task accepting submissions";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  REPUTATION MESSAGES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message for task cancellation reputation penalty
    string public constant TASK_CANCELLATION = "Task cancellation";

    /// @notice Message when user is not initialized in the system
    string public constant USER_NOT_INITIALIZED = "User not initialized";

    /// @notice Message when user is blacklisted
    string public constant USER_BLACKLISTED = "User is blacklisted";

    /// @notice Message when at-risk user has insufficient stake
    string public constant INSUFFICIENT_STAKE_AT_RISK = "Insufficient stake for at-risk user";

    /// @notice Message when access is granted to user
    string public constant ACCESS_GRANTED = "Access granted";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  SUBMISSION MESSAGES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message for successful task completion
    string public constant TASK_COMPLETED_SUCCESS = "Task completed successfully";

    /// @notice Message for successful submission
    string public constant SUBMISSION_ACCEPTED = "Submission accepted";

    /// @notice Message when submission is already adopted
    string public constant SUBMISSION_ALREADY_ADOPTED = "Submission already adopted";

    /// @notice Message when task publisher attempts to submit to their own task
    string public constant PUBLISHER_CANNOT_SUBMIT = "Task publisher cannot submit to their own task";

    /// @notice Message when submission is not in a reviewable state
    string public constant SUBMISSION_NOT_REVIEWABLE = "Submission not reviewable";

    /// @notice Message when user attempts to review their own submission
    string public constant CANNOT_REVIEW_OWN = "Cannot review own submission";

    /// @notice Message when submission is removed due to negative reviews
    string public constant SUBMISSION_REMOVED_NEGATIVE_REVIEWS = "Submission removed due to negative reviews";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    REVIEW MESSAGES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message for accurate review reputation update
    string public constant ACCURATE_REVIEW = "Accurate review";

    /// @notice Message for inaccurate review reputation penalty
    string public constant INACCURATE_REVIEW = "Inaccurate review";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  ARBITRATION MESSAGES                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message when arbitration is pending review
    string public constant ARBITRATION_PENDING = "Arbitration pending review";

    /// @notice Message when arbitration is approved
    string public constant ARBITRATION_APPROVED = "Arbitration approved";

    /// @notice Message when arbitration is rejected
    string public constant ARBITRATION_REJECTED = "Rejected arbitration request";

    /// @notice Message for arbitration resolution reputation update
    string public constant ARBITRATION_RESOLUTION = "Arbitration resolution";

    /// @notice Message when user has insufficient reputation for arbitration
    string public constant INSUFFICIENT_REPUTATION_ARBITRATION = "Insufficient reputation for arbitration";

    /// @notice Message when user reputation is too high to request arbitration
    string public constant REPUTATION_TOO_HIGH_ARBITRATION = "User reputation too high for arbitration";

    /// @notice Message when arbitration can be requested
    string public constant ARBITRATION_CAN_REQUEST = "Arbitration can be requested";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  ALLOWLIST MESSAGES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Message when submission guard is not allowed
    string public constant SUBMISSION_GUARD_NOT_ALLOWED = "Submission guard not allowed";

    /// @notice Message when review guard is not allowed
    string public constant REVIEW_GUARD_NOT_ALLOWED = "Review guard not allowed";

    /// @notice Message when adoption strategy is not allowed
    string public constant ADOPTION_STRATEGY_NOT_ALLOWED = "Adoption strategy not allowed";

    /// @notice Message when adoption strategy is required but not provided
    string public constant ADOPTION_STRATEGY_REQUIRED = "Adoption strategy required";

    /// @notice Message when reward token is not allowed
    string public constant REWARD_TOKEN_NOT_ALLOWED = "Reward token not allowed";

    /// @notice Message when enumeration is not supported
    string public constant ENUMERATION_NOT_SUPPORTED = "Enumeration not supported";
}
