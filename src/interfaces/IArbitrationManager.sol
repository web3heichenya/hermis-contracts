// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IArbitrationManager
/// @notice Interface for arbitration system management that handles dispute resolution for users and submissions
/// @dev This interface defines the standard arbitration functionality including:
///      - Arbitration request creation for various dispute types
///      - Resolution processing with evidence evaluation
///      - Fee management with deposit and refund mechanisms
///      - Query functions for arbitration tracking and status
/// @custom:interface Defines standard arbitration behavior for dispute resolution
/// @author Hermis Team
interface IArbitrationManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when arbitration request ID does not exist
    error ArbitrationNotFound(uint256 arbitrationId);

    /// @notice Error when provided arbitration fee is below required amount
    error InsufficientArbitrationFee(uint256 required, uint256 provided);

    /// @notice Error when attempting to modify an already resolved arbitration
    error ArbitrationAlreadyResolved(uint256 arbitrationId);

    /// @notice Error when caller lacks permission to perform arbitration action
    error UnauthorizedArbitrationAction(address caller);

    /// @notice Error when provided evidence is invalid or malformed
    error InvalidArbitrationEvidence(string evidence);

    /// @notice Error when attempting action that requires resolved arbitration
    error ArbitrationStillPending(uint256 arbitrationId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new arbitration request is submitted
    /// @param arbitrationId Unique ID of the created arbitration request
    /// @param requester Address of the user who submitted the arbitration request
    /// @param arbitrationType Type of arbitration being requested (user reputation, submission status, etc.)
    /// @param targetId Target identifier for the dispute (user address as uint256 or submission ID)
    /// @param depositAmount Amount of fee deposited to cover arbitration processing costs
    /// @param evidence Supporting evidence provided for the arbitration request
    event ArbitrationRequested(
        uint256 indexed arbitrationId,
        address indexed requester,
        DataTypes.ArbitrationType arbitrationType,
        uint256 targetId,
        uint256 depositAmount,
        string evidence
    );

    /// @notice Emitted when an arbitration request is resolved with a decision
    /// @param arbitrationId ID of the arbitration request that was resolved
    /// @param resolver Address of the administrator who resolved the arbitration
    /// @param decision Final decision status (approved, rejected, or dismissed)
    /// @param reason Detailed explanation for the arbitration decision
    /// @param resolvedAt Timestamp when the arbitration was resolved
    event ArbitrationResolved(
        uint256 indexed arbitrationId,
        address indexed resolver,
        DataTypes.ArbitrationStatus decision,
        string reason,
        uint256 resolvedAt
    );

    /// @notice Emitted when arbitration fee is refunded to requester
    /// @param arbitrationId ID of the arbitration request for which fee is being refunded
    /// @param recipient Address receiving the refunded arbitration fee
    /// @param amount Amount of fee being refunded to the recipient
    event ArbitrationFeeRefunded(uint256 indexed arbitrationId, address indexed recipient, uint256 amount);

    /// @notice Emitted when arbitration fee is forfeited due to rejected request
    /// @param arbitrationId ID of the arbitration request whose fee is being forfeited
    /// @param amount Amount of fee being forfeited due to request rejection
    event ArbitrationFeeForfeited(uint256 indexed arbitrationId, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  ARBITRATION FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Requests arbitration for user reputation disputes or corrections
    /// @dev Creates a new arbitration request with evidence and required fee deposit.
    ///      Should validate user address and evidence format before processing.
    /// @param user Address of the user whose reputation is being disputed
    /// @param evidence Supporting evidence for the arbitration request (IPFS hash or detailed text)
    /// @param depositAmount Arbitration fee deposit amount to cover processing costs
    /// @return arbitrationId Unique ID of the created arbitration request
    /// @custom:security Requires sufficient fee deposit to prevent spam requests
    function requestUserArbitration(
        address user,
        string calldata evidence,
        uint256 depositAmount
    ) external returns (uint256 arbitrationId);

    /// @notice Requests arbitration for submission status disputes (adoption/rejection)
    /// @dev Creates a new arbitration request with evidence and required fee deposit.
    ///      Should validate submission exists and evidence format before processing.
    /// @param submissionId ID of the submission whose status is being disputed
    /// @param evidence Supporting evidence for the arbitration request (IPFS hash or detailed text)
    /// @param depositAmount Arbitration fee deposit amount to cover processing costs
    /// @return arbitrationId Unique ID of the created arbitration request
    /// @custom:security Requires sufficient fee deposit to prevent spam requests
    function requestSubmissionArbitration(
        uint256 submissionId,
        string calldata evidence,
        uint256 depositAmount
    ) external returns (uint256 arbitrationId);

    /// @notice Resolves an arbitration request with administrative decision
    /// @dev Processes arbitration request and sets final resolution status.
    ///      Should validate decision legitimacy and provide clear reasoning.
    /// @param arbitrationId ID of the arbitration request to resolve
    /// @param decision Final decision status (approved, rejected, or dismissed)
    /// @param reason Detailed explanation for the arbitration decision
    /// @custom:security Only callable by authorized arbitration administrators
    function resolveArbitration(
        uint256 arbitrationId,
        DataTypes.ArbitrationStatus decision,
        string calldata reason
    ) external;

    /// @notice Executes approved user reputation arbitration by applying reputation changes
    /// @dev Applies reputation adjustments for approved arbitration requests.
    ///      Should validate arbitration is approved before executing changes.
    /// @param arbitrationId ID of the approved arbitration request
    /// @param reputationIncrease Amount to increase the user's reputation score
    /// @custom:security Only callable after arbitration is approved, executes reputation changes
    function executeUserArbitration(uint256 arbitrationId, uint256 reputationIncrease) external;

    /// @notice Executes approved submission status arbitration by applying status changes
    /// @dev Applies status changes for approved submission arbitration requests.
    ///      Should validate arbitration is approved before executing changes.
    /// @param arbitrationId ID of the approved arbitration request
    /// @param newStatus New status to set for the disputed submission
    /// @custom:security Only callable after arbitration is approved, executes status changes
    function executeSubmissionArbitration(uint256 arbitrationId, DataTypes.SubmissionStatus newStatus) external;

    /// @notice Claims refund for approved or dismissed arbitration requests
    /// @dev Processes fee refund for legitimate arbitration requests.
    ///      Should validate refund eligibility and prevent double claiming.
    /// @param arbitrationId ID of the arbitration request eligible for refund
    /// @custom:security Only allows refunds for approved/dismissed arbitrations
    function claimArbitrationRefund(uint256 arbitrationId) external;

    /// @notice Gets complete arbitration request information and status
    /// @dev Returns full arbitration details including status, evidence, and resolution.
    /// @param arbitrationId ID of the arbitration request to retrieve
    /// @return arbitration Complete arbitration request data structure
    /// @custom:view This function is read-only and returns arbitration details
    function getArbitration(
        uint256 arbitrationId
    ) external view returns (DataTypes.ArbitrationRequest memory arbitration);

    /// @notice Gets arbitration requests submitted by a specific user
    /// @dev Returns paginated list of arbitration IDs for tracking user's requests.
    /// @param requester Address of the user who submitted arbitration requests
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of arbitrations to return in this batch
    /// @return arbitrationIds Array of arbitration IDs submitted by the requester
    /// @custom:view This function is read-only and supports pagination
    function getArbitrationsByRequester(
        address requester,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory arbitrationIds);

    /// @notice Gets arbitrations that are still pending resolution
    /// @dev Returns paginated list of unresolved arbitration requests for administrator review.
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of pending arbitrations to return in this batch
    /// @return arbitrationIds Array of arbitration IDs awaiting resolution
    /// @custom:view This function is read-only and supports pagination
    function getPendingArbitrations(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory arbitrationIds);

    /// @notice Gets arbitrations filtered by dispute type
    /// @dev Returns paginated list of arbitrations matching specific type criteria.
    /// @param arbitrationType Type of arbitration to filter (user reputation, submission status, etc.)
    /// @param offset Starting index for pagination (0-based)
    /// @param limit Maximum number of arbitrations to return in this batch
    /// @return arbitrationIds Array of arbitration IDs matching the specified type
    /// @custom:view This function is read-only and supports pagination
    function getArbitrationsByType(
        DataTypes.ArbitrationType arbitrationType,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory arbitrationIds);

    /// @notice Gets the current arbitration fee required for new requests
    /// @dev Returns the fee amount that must be deposited when submitting arbitration requests.
    /// @return fee Current arbitration fee amount in wei
    /// @custom:view This function is read-only and returns current fee structure
    function getArbitrationFee() external view returns (uint256 fee);

    /// @notice Validates whether arbitration can be requested for a specific target
    /// @dev Checks eligibility criteria and existing arbitration status before allowing new requests.
    /// @param arbitrationType Type of arbitration being requested
    /// @param targetId Target identifier (user address as uint256 for user disputes, submission ID for submission disputes)
    /// @return canRequest Whether arbitration is permitted for this target
    /// @return reason Human-readable explanation if arbitration is not allowed
    /// @custom:view This function is read-only and validates arbitration eligibility
    function canRequestArbitration(
        DataTypes.ArbitrationType arbitrationType,
        uint256 targetId
    ) external view returns (bool canRequest, string memory reason);

    /// @notice Gets the total number of arbitration requests ever created
    /// @dev Returns cumulative count of all arbitration requests for statistical purposes.
    /// @return totalArbitrations Total arbitration request count across all types and statuses
    /// @custom:view This function is read-only and returns cumulative statistics
    function getTotalArbitrations() external view returns (uint256 totalArbitrations);
}
