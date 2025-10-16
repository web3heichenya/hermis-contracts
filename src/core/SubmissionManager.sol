// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// 2. Internal interfaces
import {IAdoptionStrategy} from "../interfaces/IAdoptionStrategy.sol";
import {IGuard} from "../interfaces/IGuard.sol";
import {IReputationManager} from "../interfaces/IReputationManager.sol";
import {IRewardStrategy} from "../interfaces/IRewardStrategy.sol";
import {ISubmissionManager} from "../interfaces/ISubmissionManager.sol";
import {ITaskManager} from "../interfaces/ITaskManager.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

// 3. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";
import {Messages} from "../libraries/Messages.sol";

/// @title SubmissionManager
/// @notice Manages work submissions and reviews for tasks in the Hermis crowdsourcing platform
/// @dev This contract implements comprehensive submission and review functionality including:
///      - Work submission creation and versioning with IPFS/Arweave content storage
///      - Peer review system with guard-based validation and reputation integration
///      - Automated adoption strategy evaluation for determining winning submissions
///      - Reward distribution system for submitters, reviewers, and platform
///      - Status management throughout submission lifecycle (SUBMITTED → UNDER_REVIEW → ADOPTED/REMOVED)
///      - Integration with TaskManager, ReputationManager, and Treasury for complete workflow
/// @custom:security All monetary operations are secured with ReentrancyGuard and proper access controls
/// @custom:upgradeable This contract is upgradeable and uses OpenZeppelin's proxy pattern
/// @author Hermis Team
contract SubmissionManager is ISubmissionManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Core mapping storing all submission information by ID
    mapping(uint256 => DataTypes.SubmissionInfo) private _submissions;

    /// @notice Core mapping storing all review information by ID
    mapping(uint256 => DataTypes.ReviewInfo) private _reviews;

    /// @notice Mapping of task IDs to their submission IDs for task-based queries
    mapping(uint256 => uint256[]) private _taskSubmissions;

    /// @notice Mapping of user addresses to their submission IDs for user profile queries
    mapping(address => uint256[]) private _userSubmissions;

    /// @notice Mapping of submission IDs to their review IDs for submission review history
    mapping(uint256 => uint256[]) private _submissionReviews;

    /// @notice Mapping of reviewer addresses to their review IDs for reviewer profile queries
    mapping(address => uint256[]) private _reviewerReviews;

    /// @notice Double mapping to track if a user has already reviewed a specific submission
    /// @dev Prevents duplicate reviews by the same user
    mapping(uint256 => mapping(address => bool)) private _hasReviewed;

    /// @notice Mapping of submission IDs to their version history (content hashes)
    /// @dev Stores all versions of a submission for audit trail and rollback capability
    mapping(uint256 => string[]) private _submissionVersions;

    /// @notice Counter for generating unique submission IDs, starts from 1
    uint256 private _nextSubmissionId;

    /// @notice Counter for generating unique review IDs, starts from 1
    uint256 private _nextReviewId;

    /// @notice Total number of submissions ever created for statistics
    uint256 private _totalSubmissions;

    /// @notice Total number of reviews ever created for statistics
    uint256 private _totalReviews;

    /// @notice TaskManager contract interface for task validation and lifecycle management
    ITaskManager public taskManager;

    /// @notice ReputationManager contract interface for user access control and reputation updates
    IReputationManager public reputationManager;

    /// @notice Treasury contract interface for reward distribution and payment processing
    ITreasury public treasury;

    /// @notice RewardStrategy contract interface for calculating reward distributions
    IRewardStrategy public rewardStrategy;

    /// @notice Mapping of authorized contracts that can perform administrative actions
    /// @dev Used to allow ArbitrationManager to restore submission status
    mapping(address => bool) public authorizedContracts;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier submissionExists(uint256 submissionId) {
        if (submissionId == 0 || submissionId >= _nextSubmissionId) {
            revert SubmissionNotFound(submissionId);
        }
        _;
    }

    modifier reviewExists(uint256 reviewId) {
        if (reviewId == 0 || reviewId >= _nextReviewId) {
            revert ReviewNotFound(reviewId);
        }
        _;
    }

    modifier onlySubmitter(uint256 submissionId) {
        if (_submissions[submissionId].submitter != msg.sender) {
            revert UnauthorizedSubmissionAction(msg.sender, submissionId);
        }
        _;
    }

    modifier onlyAuthorized() {
        // Allow owner and authorized contracts (like ArbitrationManager)
        if (msg.sender != owner() && !authorizedContracts[msg.sender]) {
            revert UnauthorizedSubmissionAction(msg.sender, 0);
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

    /// @notice Initializes the SubmissionManager contract with required dependencies
    /// @dev This function is called once during proxy deployment to set up the contract
    /// @param owner Owner address with administrative privileges
    /// @param taskManagerAddress TaskManager contract address for task validation
    /// @param reputationManagerAddress ReputationManager contract address for user validation
    /// @param treasuryAddress Treasury contract address for reward management
    /// @param rewardStrategyAddress RewardStrategy contract address for reward calculations
    /// @custom:security Only callable once due to initializer modifier
    function initialize(
        address owner,
        address taskManagerAddress,
        address reputationManagerAddress,
        address treasuryAddress,
        address rewardStrategyAddress
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();

        taskManager = ITaskManager(taskManagerAddress);
        reputationManager = IReputationManager(reputationManagerAddress);
        treasury = ITreasury(treasuryAddress);
        rewardStrategy = IRewardStrategy(rewardStrategyAddress);

        _nextSubmissionId = 1; // Start IDs from 1
        _nextReviewId = 1;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  AUTHORIZATION FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets authorization status for a contract address
    /// @dev Allows the owner to authorize or revoke authorization for contracts
    /// @param contractAddress Address of the contract to authorize/revoke
    /// @param authorized True to authorize, false to revoke authorization
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Submits new work for a task with content stored on IPFS/Arweave
    /// @dev Creates a new submission in SUBMITTED status and triggers task activation if it's the first.
    ///      Validates task acceptance, user permissions, and content hash. Automatically evaluates
    ///      submission status using adoption strategy after creation.
    /// @param taskId ID of the task to submit work for
    /// @param contentHash IPFS/Arweave hash of the submission content (must not be empty)
    /// @return submissionId ID of the created submission
    /// @custom:security Protected by reentrancy guard and validates user access
    /// @custom:validation Checks task status, user permissions, and content validity
    function submitWork(
        uint256 taskId,
        string calldata contentHash
    ) external override nonReentrant returns (uint256 submissionId) {
        // Validate content hash
        if (bytes(contentHash).length == 0) revert InvalidContentHash(contentHash);

        // Check if task can accept submissions
        (bool canAccept, ) = taskManager.canAcceptSubmissions(taskId);
        if (!canAccept) revert TaskNotAcceptingSubmissions(taskId);

        // Validate user can submit
        (bool canSubmit, ) = canSubmitToTask(msg.sender, taskId);
        if (!canSubmit) revert UnauthorizedSubmissionAction(msg.sender, 0);

        submissionId = _nextSubmissionId;
        unchecked {
            ++_nextSubmissionId;
            ++_totalSubmissions;
        }

        // Create submission
        DataTypes.SubmissionInfo storage submission = _submissions[submissionId];
        submission.id = submissionId;
        submission.taskId = taskId;
        submission.submitter = msg.sender;
        submission.contentHash = contentHash;
        submission.version = 1;
        submission.status = DataTypes.SubmissionStatus.SUBMITTED;
        submission.approveCount = 0;
        submission.rejectCount = 0;
        submission.submittedAt = block.timestamp;
        submission.lastUpdatedAt = block.timestamp;

        // Store version history
        _submissionVersions[submissionId].push(contentHash);

        // Add to mappings
        _taskSubmissions[taskId].push(submissionId);
        _userSubmissions[msg.sender].push(submissionId);

        // Set task to ACTIVE if it's the first submission
        taskManager.activateTask(taskId);

        emit SubmissionCreated(submissionId, taskId, msg.sender, contentHash, 1);

        // Automatically evaluate if status should change
        _evaluateSubmissionStatus(submissionId);
    }

    /// @notice Updates an existing submission with a new version of content
    /// @dev Creates a new version while preserving the submission history. Only the original submitter
    ///      can update their submission, and only if it hasn't been adopted or removed. Updates are
    ///      stored in version history for audit trail.
    /// @param submissionId ID of the submission to update
    /// @param newContentHash New IPFS/Arweave content hash (must not be empty)
    /// @return newVersion New version number after update
    /// @custom:security Only callable by original submitter, validates submission status
    /// @custom:validation Checks submission editability and task acceptance status
    function updateSubmission(
        uint256 submissionId,
        string calldata newContentHash
    ) external override submissionExists(submissionId) onlySubmitter(submissionId) returns (uint256 newVersion) {
        DataTypes.SubmissionInfo storage submission = _submissions[submissionId];

        // Check if submission can be updated
        if (
            submission.status == DataTypes.SubmissionStatus.ADOPTED ||
            submission.status == DataTypes.SubmissionStatus.REMOVED
        ) {
            revert SubmissionNotEditable(submissionId);
        }

        // Validate content hash
        if (bytes(newContentHash).length == 0) revert InvalidContentHash(newContentHash);

        // Check if task is still accepting submissions
        (bool canAccept, ) = taskManager.canAcceptSubmissions(submission.taskId);
        if (!canAccept) revert TaskNotAcceptingSubmissions(submission.taskId);

        // Update submission
        newVersion = submission.version + 1;
        submission.contentHash = newContentHash;
        submission.version = newVersion;
        submission.lastUpdatedAt = block.timestamp;

        // Store new version
        _submissionVersions[submissionId].push(newContentHash);

        emit SubmissionUpdated(submissionId, newContentHash, newVersion, block.timestamp);
    }

    /// @notice Submits a peer review for a submission with outcome and reasoning
    /// @dev Creates a new review and updates submission approve/reject counts. Validates reviewer
    ///      permissions through guards and reputation system. Prevents self-review and duplicate reviews.
    ///      Automatically evaluates submission status after review submission.
    /// @param submissionId ID of the submission to review
    /// @param outcome Review outcome (APPROVE or REJECT)
    /// @param reason Detailed reason for the review decision (for transparency)
    /// @return reviewId ID of the created review
    /// @custom:security Protected by reentrancy guard, prevents self-review and duplicates
    /// @custom:validation Validates reviewer permissions through guard system
    function submitReview(
        uint256 submissionId,
        DataTypes.ReviewOutcome outcome,
        string calldata reason
    ) external override submissionExists(submissionId) nonReentrant returns (uint256 reviewId) {
        DataTypes.SubmissionInfo storage submission = _submissions[submissionId];

        // Validate user can review
        (bool canReview, ) = canReviewSubmission(msg.sender, submissionId);
        if (!canReview) revert UnauthorizedSubmissionAction(msg.sender, submissionId);

        // Check if user already reviewed this submission
        if (_hasReviewed[submissionId][msg.sender]) {
            revert AlreadyReviewed(msg.sender, submissionId);
        }

        // Cannot review own submission
        if (submission.submitter == msg.sender) {
            revert CannotReviewOwnSubmission(msg.sender, submissionId);
        }

        reviewId = _nextReviewId;
        unchecked {
            ++_nextReviewId;
            ++_totalReviews;
        }

        // Create review
        DataTypes.ReviewInfo storage review = _reviews[reviewId];
        review.id = reviewId;
        review.submissionId = submissionId;
        review.reviewer = msg.sender;
        review.outcome = outcome;
        review.reason = reason;
        review.reviewedAt = block.timestamp;

        // Update mappings
        _submissionReviews[submissionId].push(reviewId);
        _reviewerReviews[msg.sender].push(reviewId);
        _hasReviewed[submissionId][msg.sender] = true;

        // Update submission counts
        if (outcome == DataTypes.ReviewOutcome.APPROVE) {
            unchecked {
                ++submission.approveCount;
            }
        } else {
            unchecked {
                ++submission.rejectCount;
            }
        }

        submission.lastUpdatedAt = block.timestamp;

        emit ReviewSubmitted(reviewId, submissionId, msg.sender, outcome, reason);

        // Evaluate if submission status should change
        _evaluateSubmissionStatus(submissionId);
    }

    /// @notice Updates submission status based on reviews and adoption strategy evaluation
    /// @dev Public function that triggers the adoption strategy to evaluate if a submission should
    ///      change status based on accumulated reviews and time elapsed. Can be called by anyone
    ///      to update submission status when conditions are met.
    /// @param submissionId ID of the submission to evaluate
    /// @custom:validation Validates submission existence before evaluation
    /// @custom:strategy Uses adoption strategy contract to determine status changes
    function evaluateSubmissionStatus(uint256 submissionId) external override submissionExists(submissionId) {
        _evaluateSubmissionStatus(submissionId);
    }

    /// @notice Restores a submission status for arbitration purposes (admin only)
    /// @dev Allows contract owner to manually change submission status for dispute resolution.
    ///      Only allows restoration to NORMAL or ADOPTED status. If restored to ADOPTED,
    ///      completes the task and processes rewards automatically.
    /// @param submissionId ID of the submission to restore
    /// @param newStatus New status to set (must be NORMAL or ADOPTED)
    /// @param reason Reason for restoration (for audit trail and transparency)
    /// @custom:security Only callable by contract owner for arbitration purposes
    /// @custom:arbitration Used in dispute resolution and appeals process
    function restoreSubmissionStatus(
        uint256 submissionId,
        DataTypes.SubmissionStatus newStatus,
        string calldata reason
    ) external override onlyAuthorized submissionExists(submissionId) {
        DataTypes.SubmissionInfo storage submission = _submissions[submissionId];
        DataTypes.SubmissionStatus oldStatus = submission.status;

        // Only allow restoration to NORMAL or ADOPTED
        if (newStatus != DataTypes.SubmissionStatus.NORMAL && newStatus != DataTypes.SubmissionStatus.ADOPTED) {
            revert UnauthorizedSubmissionAction(msg.sender, submissionId);
        }

        submission.status = newStatus;
        submission.lastUpdatedAt = block.timestamp;

        emit SubmissionStatusChanged(submissionId, oldStatus, newStatus, reason);

        // If submission is adopted, complete the task
        if (newStatus == DataTypes.SubmissionStatus.ADOPTED) {
            taskManager.completeTask(submission.taskId, submissionId);
            _processRewards(submissionId);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets complete submission information
    /// @dev Returns the full SubmissionInfo struct with all submission details including status,
    ///      review counts, version history, and metadata. This is the primary function for retrieving submission data.
    /// @param submissionId ID of the submission to retrieve
    /// @return submission Complete submission information struct
    /// @custom:view This function is read-only and does not modify state
    function getSubmission(
        uint256 submissionId
    ) external view override submissionExists(submissionId) returns (DataTypes.SubmissionInfo memory submission) {
        return _submissions[submissionId];
    }

    /// @notice Gets all submissions for a specific task with pagination
    /// @dev Returns paginated array of submission IDs for the specified task. Useful for
    ///      displaying all work submitted to a task and comparing different submissions.
    /// @param taskId ID of the task to query submissions for
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of submissions to return (for gas efficiency)
    /// @return submissionIds Array of submission IDs for the task
    /// @custom:view This function is read-only and supports pagination
    function getTaskSubmissions(
        uint256 taskId,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory submissionIds) {
        return _paginateArray(_taskSubmissions[taskId], offset, limit);
    }

    /// @notice Gets submissions created by a specific user with pagination
    /// @dev Returns paginated array of submission IDs for the specified submitter. Useful for
    ///      displaying user profiles and submission history.
    /// @param submitter Address of the submitter to query
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of submissions to return (for gas efficiency)
    /// @return submissionIds Array of submission IDs created by the user
    /// @custom:view This function is read-only and supports pagination
    function getUserSubmissions(
        address submitter,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory submissionIds) {
        return _paginateArray(_userSubmissions[submitter], offset, limit);
    }

    /// @notice Gets all reviews for a specific submission with pagination
    /// @dev Returns paginated array of review IDs for the specified submission. Useful for
    ///      displaying review history and feedback for a submission.
    /// @param submissionId ID of the submission to query reviews for
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of reviews to return (for gas efficiency)
    /// @return reviewIds Array of review IDs for the submission
    /// @custom:view This function is read-only and supports pagination
    function getSubmissionReviews(
        uint256 submissionId,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory reviewIds) {
        return _paginateArray(_submissionReviews[submissionId], offset, limit);
    }

    /// @notice Gets complete review information
    /// @dev Returns the full ReviewInfo struct with all review details including outcome,
    ///      reasoning, reviewer address, and timestamp. This is the primary function for retrieving review data.
    /// @param reviewId ID of the review to retrieve
    /// @return review Complete review information struct
    /// @custom:view This function is read-only and does not modify state
    function getReview(
        uint256 reviewId
    ) external view override reviewExists(reviewId) returns (DataTypes.ReviewInfo memory review) {
        return _reviews[reviewId];
    }

    /// @notice Gets reviews submitted by a specific reviewer with pagination
    /// @dev Returns paginated array of review IDs for the specified reviewer. Useful for
    ///      displaying reviewer profiles and review history.
    /// @param reviewer Address of the reviewer to query
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of reviews to return (for gas efficiency)
    /// @return reviewIds Array of review IDs submitted by the reviewer
    /// @custom:view This function is read-only and supports pagination
    function getReviewerReviews(
        address reviewer,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory reviewIds) {
        return _paginateArray(_reviewerReviews[reviewer], offset, limit);
    }

    /// @notice Checks if a user can submit work to a task with detailed validation
    /// @dev Validates user access through ReputationManager, prevents task publishers from
    ///      submitting to their own tasks, and validates permissions through submission guard.
    ///      Returns both boolean result and human-readable reason.
    /// @param user Address of the user to validate
    /// @param taskId ID of the task to submit to
    /// @return canSubmit Whether the user can submit to the task
    /// @return reason Human-readable reason if submission is not allowed
    /// @custom:view This function is read-only and provides detailed validation feedback
    function canSubmitToTask(
        address user,
        uint256 taskId
    ) public view override returns (bool canSubmit, string memory reason) {
        // Check user access
        (bool canAccess, string memory accessReason) = reputationManager.validateUserAccess(user);
        if (!canAccess) {
            return (false, accessReason);
        }

        // Get task info and validate with submission guard
        DataTypes.TaskInfo memory task = taskManager.getTask(taskId);

        // Task publisher cannot submit to their own task
        if (task.publisher == user) {
            return (false, Messages.PUBLISHER_CANNOT_SUBMIT);
        }

        if (task.submissionGuard != address(0)) {
            bytes memory guardData = abi.encode(taskId, task.category);
            (bool guardValid, string memory guardReason) = IGuard(task.submissionGuard).validateUser(user, guardData);
            if (!guardValid) {
                return (false, guardReason);
            }
        }

        return (true, "");
    }

    /// @notice Checks if a user can review a submission with detailed validation
    /// @dev Validates submission reviewability status, user access through ReputationManager,
    ///      prevents self-review, and validates permissions through review guard.
    ///      Returns both boolean result and human-readable reason.
    /// @param user Address of the user to validate
    /// @param submissionId ID of the submission to review
    /// @return canReview Whether the user can review the submission
    /// @return reason Human-readable reason if review is not allowed
    /// @custom:view This function is read-only and provides detailed validation feedback
    function canReviewSubmission(
        address user,
        uint256 submissionId
    ) public view override returns (bool canReview, string memory reason) {
        DataTypes.SubmissionInfo memory submission = _submissions[submissionId];

        // Check if submission exists and is reviewable
        if (
            submission.status != DataTypes.SubmissionStatus.SUBMITTED &&
            submission.status != DataTypes.SubmissionStatus.UNDER_REVIEW &&
            submission.status != DataTypes.SubmissionStatus.NORMAL
        ) {
            return (false, Messages.SUBMISSION_NOT_REVIEWABLE);
        }

        // Check user access
        (bool canAccess, string memory accessReason) = reputationManager.validateUserAccess(user);
        if (!canAccess) {
            return (false, accessReason);
        }

        // User cannot review their own submission
        if (submission.submitter == user) {
            return (false, Messages.CANNOT_REVIEW_OWN);
        }

        // Get task info and validate with review guard
        DataTypes.TaskInfo memory task = taskManager.getTask(submission.taskId);

        if (task.reviewGuard != address(0)) {
            bytes memory guardData = abi.encode(submission.taskId, task.category, submissionId);
            (bool guardValid, string memory guardReason) = IGuard(task.reviewGuard).validateUser(user, guardData);
            if (!guardValid) {
                return (false, guardReason);
            }
        }

        return (true, "");
    }

    /// @notice Gets total number of submissions ever created
    /// @dev Returns the total count of submissions created since contract deployment.
    ///      Useful for statistics and platform analytics.
    /// @return totalSubmissions Total submission count across all tasks and statuses
    /// @custom:view This function is read-only and provides platform statistics
    function getTotalSubmissions() external view override returns (uint256 totalSubmissions) {
        return _totalSubmissions;
    }

    /// @notice Gets total number of reviews ever created
    /// @dev Returns the total count of reviews created since contract deployment.
    ///      Useful for statistics and platform analytics.
    /// @return totalReviews Total review count across all submissions
    /// @custom:view This function is read-only and provides platform statistics
    function getTotalReviews() external view override returns (uint256 totalReviews) {
        return _totalReviews;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to evaluate submission status using adoption strategy
    /// @dev Calls the adoption strategy contract to determine if a submission should change status
    ///      based on review counts and time elapsed. Handles status transitions including adoption
    ///      (which triggers reward processing) and removal (which applies reputation penalty).
    /// @param submissionId ID of the submission to evaluate
    /// @custom:strategy Integrates with adoption strategy for automated decision making
    /// @custom:rewards Processes rewards automatically when submissions are adopted
    function _evaluateSubmissionStatus(uint256 submissionId) internal {
        DataTypes.SubmissionInfo storage submission = _submissions[submissionId];

        // Get task and adoption strategy
        DataTypes.TaskInfo memory task = taskManager.getTask(submission.taskId);

        if (task.adoptionStrategy == address(0)) return;

        uint256 totalReviews = submission.approveCount + submission.rejectCount;
        uint256 timeSinceSubmission = block.timestamp - submission.submittedAt;

        // Evaluate with adoption strategy
        (DataTypes.SubmissionStatus newStatus, bool shouldChange, string memory reason) = IAdoptionStrategy(
            task.adoptionStrategy
        ).evaluateSubmission(
                submissionId,
                submission.approveCount,
                submission.rejectCount,
                totalReviews,
                timeSinceSubmission
            );

        if (shouldChange && newStatus != submission.status) {
            DataTypes.SubmissionStatus oldStatus = submission.status;
            submission.status = newStatus;
            submission.lastUpdatedAt = block.timestamp;

            emit SubmissionStatusChanged(submissionId, oldStatus, newStatus, reason);

            // Handle adoption
            if (newStatus == DataTypes.SubmissionStatus.ADOPTED) {
                taskManager.completeTask(submission.taskId, submissionId);
                _processRewards(submissionId);
                emit SubmissionAdopted(submissionId, submission.taskId, submission.submitter, block.timestamp);
            }

            // Handle removal (reputation penalty)
            if (newStatus == DataTypes.SubmissionStatus.REMOVED) {
                reputationManager.updateReputation(
                    submission.submitter,
                    -200, // -20.0 reputation penalty
                    Messages.SUBMISSION_REMOVED_NEGATIVE_REVIEWS
                );
            }
        }
    }

    /// @notice Processes comprehensive reward distribution for an adopted submission
    /// @dev Calculates and distributes rewards to submitter, reviewers, and platform using
    ///      the reward strategy. Handles Treasury withdrawals, reputation updates, and
    ///      category score additions for all participants.
    /// @param submissionId ID of the adopted submission to process rewards for
    /// @custom:economy Handles complete reward distribution workflow
    /// @custom:reputation Updates reputation and category scores for participants
    function _processRewards(uint256 submissionId) internal {
        DataTypes.SubmissionInfo memory submission = _submissions[submissionId];
        DataTypes.TaskInfo memory task = taskManager.getTask(submission.taskId);

        // Calculate reward distribution
        uint256 reviewerCount = submission.approveCount + submission.rejectCount;

        DataTypes.RewardDistribution memory distribution = rewardStrategy.calculateRewardDistribution(
            submission.taskId,
            task.reward,
            submissionId,
            reviewerCount
        );

        // Process creator reward
        if (distribution.creatorShare > 0) {
            treasury.withdrawTaskReward(
                submission.taskId,
                submission.submitter,
                task.rewardToken,
                distribution.creatorShare
            );

            // Add category score for creator
            reputationManager.addPendingCategoryScore(
                submission.submitter,
                task.category,
                100 // 10.0 category score
            );
        }

        // Process platform fee
        if (distribution.platformShare > 0) {
            treasury.allocatePlatformFee(task.rewardToken, distribution.platformShare);
        }

        // Process publisher refund
        if (distribution.publisherRefund > 0) {
            treasury.withdrawTaskReward(
                submission.taskId,
                task.publisher,
                task.rewardToken,
                distribution.publisherRefund
            );
        }

        // Update reviewer rewards and reputation
        _processReviewerRewards(submissionId, distribution.reviewerShare);
    }

    /// @notice Processes individual reviewer rewards and reputation updates
    /// @dev Calculates individual reviewer rewards based on review accuracy and distributes
    ///      them through Treasury. Updates reviewer reputation based on whether their review
    ///      matched the final outcome (accurate reviewers get positive reputation).
    /// @param submissionId ID of the submission that was adopted
    /// @param totalReviewerReward Total amount allocated for all reviewers
    /// @custom:accuracy Rewards accurate reviewers and penalizes inaccurate ones
    /// @custom:reputation Updates both general reputation and category-specific scores
    function _processReviewerRewards(uint256 submissionId, uint256 totalReviewerReward) internal {
        if (totalReviewerReward == 0) return;

        DataTypes.SubmissionInfo memory submission = _submissions[submissionId];
        DataTypes.TaskInfo memory task = taskManager.getTask(submission.taskId);

        uint256[] memory reviewIds = _submissionReviews[submissionId];
        uint256 reviewCount = reviewIds.length;

        if (reviewCount == 0) return;

        for (uint256 i = 0; i < reviewCount; ) {
            DataTypes.ReviewInfo memory review = _reviews[reviewIds[i]];

            // Check if reviewer's opinion matched final outcome (adopted = correct if they approved)
            bool reviewAccuracy = (submission.status == DataTypes.SubmissionStatus.ADOPTED &&
                review.outcome == DataTypes.ReviewOutcome.APPROVE) ||
                (submission.status == DataTypes.SubmissionStatus.REMOVED &&
                    review.outcome == DataTypes.ReviewOutcome.REJECT);

            // Calculate individual reviewer reward
            uint256 reviewerReward = rewardStrategy.calculateReviewerReward(
                submission.taskId,
                review.reviewer,
                totalReviewerReward,
                reviewCount,
                reviewAccuracy
            );

            // Distribute reward
            if (reviewerReward > 0) {
                treasury.withdrawTaskReward(submission.taskId, review.reviewer, task.rewardToken, reviewerReward);
            }

            // Update reputation and category scores
            if (reviewAccuracy) {
                reputationManager.updateReputation(
                    review.reviewer,
                    50, // +5.0 reputation for accurate review
                    Messages.ACCURATE_REVIEW
                );

                // Add category score for accurate reviewer
                reputationManager.addPendingCategoryScore(
                    review.reviewer,
                    task.category,
                    50 // 5.0 category score
                );
            } else {
                reputationManager.updateReputation(
                    review.reviewer,
                    -20, // -2.0 reputation for inaccurate review
                    Messages.INACCURATE_REVIEW
                );
            }

            unchecked {
                ++i;
            }
        }
    }

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
