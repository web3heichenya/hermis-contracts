// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title ISubmissionManager
/// @notice Interface for submission lifecycle and peer review management within the Hermis platform
/// @dev This interface defines the standard submission management functionality including:
///      - Work submission creation and versioning with IPFS content storage
///      - Peer review system with outcome tracking and reputation integration
///      - Submission status evaluation based on adoption strategies
///      - Query functions for submissions, reviews, and user activity tracking
/// @custom:interface Defines standard submission and review behavior for task completion workflow
/// @author Hermis Team
interface ISubmissionManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when submission ID does not exist in the system
    error SubmissionNotFound(uint256 submissionId);

    /// @notice Error when task is not accepting new submissions (completed, expired, or paused)
    error TaskNotAcceptingSubmissions(uint256 taskId);

    /// @notice Error when attempting to edit a submission that is no longer editable
    error SubmissionNotEditable(uint256 submissionId);

    /// @notice Error when caller lacks permission to perform submission action
    error UnauthorizedSubmissionAction(address caller, uint256 submissionId);

    /// @notice Error when provided content hash is invalid or malformed
    error InvalidContentHash(string contentHash);

    /// @notice Error when reviewer attempts to review the same submission twice
    error AlreadyReviewed(address reviewer, uint256 submissionId);

    /// @notice Error when user attempts to review their own submission
    error CannotReviewOwnSubmission(address reviewer, uint256 submissionId);

    /// @notice Error when review ID does not exist in the system
    error ReviewNotFound(uint256 reviewId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new work submission is created for a task
    /// @param submissionId Unique ID of the newly created submission
    /// @param taskId ID of the task this submission was created for
    /// @param submitter Address of the user who created the submission
    /// @param contentHash IPFS or Arweave hash pointing to the submission content
    /// @param version Version number of the submission (starts at 1)
    event SubmissionCreated(
        uint256 indexed submissionId,
        uint256 indexed taskId,
        address indexed submitter,
        string contentHash,
        uint256 version
    );

    /// @notice Emitted when an existing submission is updated with new content
    /// @param submissionId ID of the submission that was updated
    /// @param newContentHash New IPFS or Arweave hash for the updated content
    /// @param newVersion Incremented version number after the update
    /// @param updatedAt Timestamp when the submission was updated
    event SubmissionUpdated(uint256 indexed submissionId, string newContentHash, uint256 newVersion, uint256 updatedAt);

    /// @notice Emitted when submission status changes through evaluation or administrative action
    /// @param submissionId ID of the submission whose status changed
    /// @param oldStatus Previous status of the submission before the change
    /// @param newStatus New status of the submission after the change
    /// @param reason Explanation for the status change
    event SubmissionStatusChanged(
        uint256 indexed submissionId,
        DataTypes.SubmissionStatus oldStatus,
        DataTypes.SubmissionStatus newStatus,
        string reason
    );

    /// @notice Emitted when a peer review is submitted for a submission
    /// @param reviewId Unique ID of the newly created review
    /// @param submissionId ID of the submission being reviewed
    /// @param reviewer Address of the user who submitted the review
    /// @param outcome Review decision (approve, reject, or request changes)
    /// @param reason Detailed explanation for the review outcome
    event ReviewSubmitted(
        uint256 indexed reviewId,
        uint256 indexed submissionId,
        address indexed reviewer,
        DataTypes.ReviewOutcome outcome,
        string reason
    );

    /// @notice Emitted when a submission is adopted as the winning solution for a task
    /// @param submissionId ID of the submission that was adopted
    /// @param taskId ID of the task for which the submission was adopted
    /// @param submitter Address of the user who created the winning submission
    /// @param adoptedAt Timestamp when the submission was adopted
    event SubmissionAdopted(uint256 indexed submissionId, uint256 indexed taskId, address submitter, uint256 adoptedAt);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   SUBMISSION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Submits new work content for an active task
    /// @dev Creates a new submission with content stored on IPFS/Arweave.
    ///      Should validate task accepts submissions and user meets requirements.
    /// @param taskId ID of the task to submit work for
    /// @param contentHash IPFS or Arweave hash pointing to the submission content
    /// @return submissionId Unique ID of the created submission
    /// @custom:security Validates user permissions and task status before creation
    function submitWork(uint256 taskId, string calldata contentHash) external returns (uint256 submissionId);

    /// @notice Updates an existing submission with new content version
    /// @dev Creates a new version of submission with updated content hash.
    ///      Should validate submission is still editable and user owns it.
    /// @param submissionId ID of the submission to update with new content
    /// @param newContentHash New IPFS or Arweave hash for the updated content
    /// @return newVersion Incremented version number of the updated submission
    /// @custom:security Only allows updates by submission owner and for editable submissions
    function updateSubmission(
        uint256 submissionId,
        string calldata newContentHash
    ) external returns (uint256 newVersion);

    /// @notice Submits a peer review evaluation for a submission
    /// @dev Creates a review with outcome and reasoning for adoption strategy evaluation.
    ///      Should validate reviewer eligibility and prevent duplicate reviews.
    /// @param submissionId ID of the submission to evaluate with peer review
    /// @param outcome Review decision (approve, reject, or request changes)
    /// @param reason Detailed explanation for the review outcome decision
    /// @return reviewId Unique ID of the created review record
    /// @custom:security Validates reviewer permissions and prevents self-review
    function submitReview(
        uint256 submissionId,
        DataTypes.ReviewOutcome outcome,
        string calldata reason
    ) external returns (uint256 reviewId);

    /// @notice Evaluates and updates submission status based on accumulated reviews and adoption strategy
    /// @dev Triggers adoption strategy evaluation using review data to determine status changes.
    ///      Should handle status transitions like pending -> adopted or pending -> rejected.
    /// @param submissionId ID of the submission to evaluate for status update
    /// @custom:security Can trigger adoption and task completion based on strategy rules
    function evaluateSubmissionStatus(uint256 submissionId) external;

    /// @notice Restores submission status through administrative action for arbitration resolution
    /// @dev Allows administrative override of submission status for dispute resolution.
    ///      Should validate arbitration authority and emit status change events.
    /// @param submissionId ID of the submission to restore status for
    /// @param newStatus New status to apply to the submission
    /// @param reason Explanation for the administrative status restoration
    /// @custom:security Only callable by authorized administrators for arbitration
    function restoreSubmissionStatus(
        uint256 submissionId,
        DataTypes.SubmissionStatus newStatus,
        string calldata reason
    ) external;

    /// @notice Gets complete submission information including content and status
    /// @dev Returns full submission details for display and processing.
    /// @param submissionId ID of the submission to retrieve information for
    /// @return submission Complete submission data structure with content hash, status, and metadata
    /// @custom:view This function is read-only and returns submission details
    function getSubmission(uint256 submissionId) external view returns (DataTypes.SubmissionInfo memory submission);

    /// @notice Gets paginated list of all submissions for a specific task
    /// @dev Returns submission IDs for task-based filtering and display.
    /// @param taskId ID of the task to retrieve submissions for
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of submission IDs to return in this batch
    /// @return submissionIds Array of submission IDs associated with the task
    /// @custom:view This function is read-only and supports pagination
    function getTaskSubmissions(
        uint256 taskId,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory submissionIds);

    /// @notice Gets paginated list of submissions created by a specific user
    /// @dev Returns submission IDs for user profile and activity tracking.
    /// @param submitter Address of the user who created the submissions
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of submission IDs to return in this batch
    /// @return submissionIds Array of submission IDs created by the user
    /// @custom:view This function is read-only and supports pagination
    function getUserSubmissions(
        address submitter,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory submissionIds);

    /// @notice Gets paginated list of reviews for a specific submission
    /// @dev Returns review IDs for submission evaluation and display.
    /// @param submissionId ID of the submission to retrieve reviews for
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of review IDs to return in this batch
    /// @return reviewIds Array of review IDs associated with the submission
    /// @custom:view This function is read-only and supports pagination
    function getSubmissionReviews(
        uint256 submissionId,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory reviewIds);

    /// @notice Gets complete review information including outcome and reasoning
    /// @dev Returns full review details for display and evaluation processing.
    /// @param reviewId ID of the review to retrieve information for
    /// @return review Complete review data structure with outcome, reason, and metadata
    /// @custom:view This function is read-only and returns review details
    function getReview(uint256 reviewId) external view returns (DataTypes.ReviewInfo memory review);

    /// @notice Gets paginated list of reviews submitted by a specific reviewer
    /// @dev Returns review IDs for reviewer profile and activity tracking.
    /// @param reviewer Address of the user who submitted the reviews
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of review IDs to return in this batch
    /// @return reviewIds Array of review IDs submitted by the reviewer
    /// @custom:view This function is read-only and supports pagination
    function getReviewerReviews(
        address reviewer,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory reviewIds);

    /// @notice Validates whether a user can submit work to a specific task
    /// @dev Checks user eligibility, task status, and submission requirements.
    ///      Used for UI validation and access control.
    /// @param user Address of the user requesting to submit work
    /// @param taskId ID of the task to validate submission eligibility for
    /// @return canSubmit Whether the user is permitted to submit to this task
    /// @return reason Human-readable explanation if submission is not allowed
    /// @custom:view This function is read-only and validates submission eligibility
    function canSubmitToTask(address user, uint256 taskId) external view returns (bool canSubmit, string memory reason);

    /// @notice Validates whether a user can review a specific submission
    /// @dev Checks reviewer eligibility, prevents self-review, and validates submission status.
    ///      Used for UI validation and access control.
    /// @param user Address of the user requesting to review
    /// @param submissionId ID of the submission to validate review eligibility for
    /// @return canReview Whether the user is permitted to review this submission
    /// @return reason Human-readable explanation if review is not allowed
    /// @custom:view This function is read-only and validates review eligibility
    function canReviewSubmission(
        address user,
        uint256 submissionId
    ) external view returns (bool canReview, string memory reason);

    /// @notice Gets the total number of submissions created across all tasks
    /// @dev Returns cumulative count of all submissions for statistical purposes.
    /// @return totalSubmissions Total submission count across the platform
    /// @custom:view This function is read-only and returns cumulative statistics
    function getTotalSubmissions() external view returns (uint256 totalSubmissions);

    /// @notice Gets the total number of reviews submitted across all submissions
    /// @dev Returns cumulative count of all reviews for statistical purposes.
    /// @return totalReviews Total review count across the platform
    /// @custom:view This function is read-only and returns cumulative statistics
    function getTotalReviews() external view returns (uint256 totalReviews);
}
