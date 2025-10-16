// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title DataTypes
/// @notice Core data structures, enums, and type definitions for the Hermis crowdsourcing platform
/// @dev This library defines all fundamental data types used across the Hermis ecosystem including:
///      - Task lifecycle and status management enums
///      - Submission and review workflow states
///      - User reputation and access control enums
///      - Arbitration system status and type definitions
///      - Comprehensive data structures for tasks, submissions, reviews, and reputation
///      - Platform configuration and reward distribution structures
/// @custom:library Provides centralized type definitions for cross-contract consistency
/// @author Hermis Team
library DataTypes {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ENUMS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Lifecycle status enumeration for tasks on the platform
    /// @dev Tasks progress sequentially through these states from creation to completion.
    ///      Terminal states are COMPLETED, EXPIRED, and CANCELLED.
    enum TaskStatus {
        /// @notice Task created but not yet published to the platform
        DRAFT,
        /// @notice Task published and actively accepting submissions
        PUBLISHED,
        /// @notice Task has received at least one submission and is being reviewed
        ACTIVE,
        /// @notice Task completed with a successfully adopted submission
        COMPLETED,
        /// @notice Task deadline passed without any submission being adopted
        EXPIRED,
        /// @notice Task cancelled by the publisher before completion
        CANCELLED
    }

    /// @notice Status enumeration for work submissions in the review process
    /// @dev Submissions flow through validation and review states to reach final adoption or removal.
    ///      Terminal states are ADOPTED and REMOVED.
    enum SubmissionStatus {
        /// @notice Initial submission state immediately after creation
        SUBMITTED,
        /// @notice Submission is actively being reviewed by community
        UNDER_REVIEW,
        /// @notice Submission has passed initial review and is eligible for adoption
        NORMAL,
        /// @notice Submission has been selected as the winning solution for the task
        ADOPTED,
        /// @notice Submission has been removed due to policy violations or quality issues
        REMOVED
    }

    /// @notice Binary outcome enumeration for submission reviews
    /// @dev Used by reviewers to indicate their assessment of submission quality and compliance
    enum ReviewOutcome {
        /// @notice Submission meets task requirements and quality standards
        APPROVE,
        /// @notice Submission fails to meet task requirements or quality standards
        REJECT
    }

    /// @notice User access status enumeration based on reputation score and platform behavior
    /// @dev Automatically assigned based on configurable reputation thresholds.
    ///      Affects user permissions and staking requirements.
    enum UserStatus {
        /// @notice User has never interacted with the platform
        UNINITIALIZED,
        /// @notice User is banned from platform activities (reputation < 10.0)
        BLACKLISTED,
        /// @notice User requires additional staking for platform access (10.0 ≤ reputation < 60.0)
        AT_RISK,
        /// @notice User has full platform access privileges (reputation ≥ 60.0)
        NORMAL
    }

    /// @notice Status enumeration for arbitration request resolution
    /// @dev Tracks the lifecycle of dispute resolution requests from submission to final decision
    enum ArbitrationStatus {
        /// @notice Arbitration request has been submitted and is awaiting moderator review
        PENDING,
        /// @notice Arbitration request has been approved and remedial action has been applied
        APPROVED,
        /// @notice Arbitration request has been reviewed and rejected with no action taken
        REJECTED
    }

    /// @notice Type enumeration for different arbitration request categories
    /// @dev Each type has specific resolution processes and evidence requirements
    enum ArbitrationType {
        /// @notice Appeal regarding user reputation score or access status assignment
        USER_REPUTATION,
        /// @notice Appeal regarding submission review outcome or status change
        SUBMISSION_STATUS
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Comprehensive data structure containing all task information and metadata
    /// @dev Optimized struct layout for gas efficiency. Contains complete task lifecycle data
    ///      including configuration, status, and associated contracts for validation and adoption.
    struct TaskInfo {
        /// @notice Unique numerical identifier for the task
        uint256 id;
        /// @notice Address of the user who created and published the task
        address publisher;
        /// @notice Human-readable title summarizing the task objective
        string title;
        /// @notice Detailed description explaining the task requirements and context
        string description;
        /// @notice Technical requirements and acceptance criteria for submissions
        string requirements;
        /// @notice Task category for organizational and filtering purposes
        string category;
        /// @notice Unix timestamp when the task expires and stops accepting submissions
        uint256 deadline;
        /// @notice Total reward amount to be distributed upon task completion
        uint256 reward;
        /// @notice Token contract address for rewards (address(0) indicates native ETH)
        address rewardToken;
        /// @notice Current lifecycle status of the task
        TaskStatus status;
        /// @notice Unix timestamp when the task was initially created
        uint256 createdAt;
        /// @notice Guard contract address for validating submission eligibility
        address submissionGuard;
        /// @notice Guard contract address for validating reviewer eligibility
        address reviewGuard;
        /// @notice Strategy contract address for determining submission adoption logic
        address adoptionStrategy;
        /// @notice ID of the submission that was adopted as the winning solution (0 if none)
        uint256 adoptedSubmissionId;
    }

    /// @notice Data structure containing submission information and review status
    /// @dev Tracks submission lifecycle, content, and community review metrics
    struct SubmissionInfo {
        /// @notice Unique numerical identifier for the submission
        uint256 id;
        /// @notice ID of the task this submission is responding to
        uint256 taskId;
        /// @notice Address of the user who created the submission
        address submitter;
        /// @notice Content hash (typically IPFS) pointing to the submission work
        string contentHash;
        /// @notice Version number for submission updates (starts at 1)
        uint256 version;
        /// @notice Current status in the review and adoption process
        SubmissionStatus status;
        /// @notice Total number of approval reviews received
        uint256 approveCount;
        /// @notice Total number of rejection reviews received
        uint256 rejectCount;
        /// @notice Unix timestamp when the submission was initially created
        uint256 submittedAt;
        /// @notice Unix timestamp of the most recent status or content update
        uint256 lastUpdatedAt;
    }

    /// @notice Data structure containing individual review information and assessment
    /// @dev Records reviewer decisions and rationale for submission evaluations
    struct ReviewInfo {
        /// @notice Unique numerical identifier for the review
        uint256 id;
        /// @notice ID of the submission being reviewed
        uint256 submissionId;
        /// @notice Address of the user who conducted the review
        address reviewer;
        /// @notice Binary outcome decision (approve or reject)
        ReviewOutcome outcome;
        /// @notice Textual explanation for the review decision
        string reason;
        /// @notice Unix timestamp when the review was submitted
        uint256 reviewedAt;
    }

    /// @notice Data structure containing user reputation metrics and staking information
    /// @dev Tracks user standing, category expertise, and staking status for platform access
    struct UserReputation {
        /// @notice Overall reputation score with 10x precision (e.g., 600 = 60.0)
        /// @dev Using uint128 is sufficient for reputation scores (max ~10^38)
        uint128 reputationScore;
        /// @notice Amount of tokens currently staked by the user for platform access
        /// @dev Using uint128 is sufficient for stake amounts (max ~10^38)
        uint128 stakedAmount;
        /// @notice Unix timestamp of the last reputation score claim/update
        /// @dev Using uint128 is sufficient for timestamps until year ~10^31
        uint128 lastClaimTime;
        /// @notice Unix timestamp when unstaking request was initiated (0 if none)
        /// @dev Using uint128 is sufficient for timestamps until year ~10^31
        uint128 unstakeRequestTime;
        /// @notice Address of the user this reputation data belongs to
        address user;
        /// @notice Current access status based on reputation thresholds
        UserStatus status;
        /// @notice Boolean flag indicating if user has pending unstake request
        bool hasUnstakeRequest;
        /// @notice Mapping of category names to specialized reputation scores
        mapping(string => uint256) categoryScores;
    }

    /// @notice Data structure containing arbitration request details and resolution status
    /// @dev Tracks dispute resolution requests from initiation through final decision
    struct ArbitrationRequest {
        /// @notice Unique numerical identifier for the arbitration request
        uint256 id;
        /// @notice Address of the user who initiated the arbitration request
        address requester;
        /// @notice Type of arbitration being requested (reputation or submission appeal)
        ArbitrationType arbitrationType;
        /// @notice ID of the target being disputed (user ID, submission ID, etc.)
        uint256 targetId;
        /// @notice Supporting evidence or explanation for the arbitration request
        string evidence;
        /// @notice Amount deposited as collateral for the arbitration request
        uint256 depositAmount;
        /// @notice Current resolution status of the arbitration request
        ArbitrationStatus status;
        /// @notice Unix timestamp when the arbitration request was submitted
        uint256 requestedAt;
        /// @notice Unix timestamp when the arbitration was resolved (0 if pending)
        uint256 resolvedAt;
        /// @notice Address of the moderator who resolved the arbitration (address(0) if pending)
        address resolver;
    }

    /// @notice Platform-wide configuration parameters and system settings
    /// @dev Contains all global settings that affect platform behavior and user interactions
    struct GlobalConfig {
        /// @notice Minimum reputation score required for normal platform access
        uint256 minReputationScore;
        /// @notice Reputation threshold below which users are considered at-risk
        uint256 atRiskThreshold;
        /// @notice Reputation threshold below which users are blacklisted
        uint256 blacklistThreshold;
        /// @notice Base amount of tokens required for staking by at-risk users
        uint256 baseStakeAmount;
        /// @notice Time period (in seconds) that tokens remain locked after unstake request
        uint256 unstakeLockPeriod;
        /// @notice Fee amount required to submit arbitration requests
        uint256 arbitrationFee;
        /// @notice Address of the default reward distribution strategy contract
        address rewardStrategy;
        /// @notice Address of the global guard contract for platform-wide access control
        address globalGuard;
        /// @notice Address of the treasury contract for fund management
        address treasury;
        /// @notice Emergency pause flag for platform operations
        bool paused;
    }

    /// @notice Data structure defining reward allocation breakdown for completed tasks
    /// @dev Specifies how total task rewards are distributed among different participants
    struct RewardDistribution {
        /// @notice Amount allocated to the submission creator (winner)
        uint256 creatorShare;
        /// @notice Total amount allocated to be distributed among reviewers
        uint256 reviewerShare;
        /// @notice Amount allocated to the platform as operational fees
        uint256 platformShare;
        /// @notice Amount refunded to the original task publisher
        uint256 publisherRefund;
    }
}
