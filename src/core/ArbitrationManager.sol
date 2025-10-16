// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// 2. Internal interfaces
import {IArbitrationManager} from "../interfaces/IArbitrationManager.sol";
import {IReputationManager} from "../interfaces/IReputationManager.sol";
import {ISubmissionManager} from "../interfaces/ISubmissionManager.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

// 3. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";
import {Messages} from "../libraries/Messages.sol";

/// @title ArbitrationManager
/// @notice Manages arbitration requests for user reputation and submission disputes in the Hermis platform
/// @dev This contract implements a comprehensive arbitration system including:
///      - User reputation dispute resolution for users below reputation thresholds
///      - Submission status arbitration for contested content decisions
///      - Fee-based arbitration request system with configurable parameters
///      - Integration with ReputationManager and SubmissionManager for dispute resolution
///      - Treasury integration for fee collection and management
/// @author Hermis Team
contract ArbitrationManager is IArbitrationManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mapping from arbitration ID to arbitration request details
    mapping(uint256 => DataTypes.ArbitrationRequest) private _arbitrations;

    /// @notice Mapping from requester address to array of their arbitration IDs
    mapping(address => uint256[]) private _requesterArbitrations;

    /// @notice Mapping from arbitration type to array of arbitration IDs of that type
    mapping(DataTypes.ArbitrationType => uint256[]) private _arbitrationsByType;

    /// @notice Array of all pending arbitration IDs
    uint256[] private _pendingArbitrations;

    /// @notice The next arbitration ID to be assigned
    uint256 private _nextArbitrationId;

    /// @notice The total number of arbitrations created
    uint256 private _totalArbitrations;

    /// @notice The current arbitration fee amount
    uint256 private _arbitrationFee;

    /// @notice Reference to the ReputationManager contract
    IReputationManager public reputationManager;

    /// @notice Reference to the SubmissionManager contract
    ISubmissionManager public submissionManager;

    /// @notice Reference to the Treasury contract for fee management
    ITreasury public treasury;

    /// @notice Address of the ERC20 token used for arbitration fees
    address public feeToken;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Minimum reputation score required to request user reputation arbitration (50.0 with precision 10)
    uint256 private constant _MIN_REPUTATION_FOR_ARBITRATION = 500;

    /// @notice Maximum reputation score eligible for arbitration (60.0 with precision 10)
    uint256 private constant _MAX_REPUTATION_FOR_ARBITRATION = 600;

    /// @notice Default arbitration fee amount in fee token units
    uint256 private constant _DEFAULT_ARBITRATION_FEE = 0.001 ether;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier arbitrationExists(uint256 arbitrationId) {
        if (arbitrationId == 0 || arbitrationId >= _nextArbitrationId) {
            revert ArbitrationNotFound(arbitrationId);
        }
        _;
    }

    modifier onlyRequester(uint256 arbitrationId) {
        if (_arbitrations[arbitrationId].requester != msg.sender) {
            revert UnauthorizedArbitrationAction(msg.sender);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Constructor for ArbitrationManager
    /// @dev Disables initializers to prevent initialization of the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the ArbitrationManager contract
    /// @param owner Owner address
    /// @param reputationManagerAddress ReputationManager contract address
    /// @param submissionManagerAddress SubmissionManager contract address
    /// @param treasuryAddress Treasury contract address
    /// @param feeTokenAddress Token address for arbitration fees
    function initialize(
        address owner,
        address reputationManagerAddress,
        address submissionManagerAddress,
        address treasuryAddress,
        address feeTokenAddress
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();

        reputationManager = IReputationManager(reputationManagerAddress);
        submissionManager = ISubmissionManager(submissionManagerAddress);
        treasury = ITreasury(treasuryAddress);
        feeToken = feeTokenAddress;

        _nextArbitrationId = 1; // Start IDs from 1
        _arbitrationFee = _DEFAULT_ARBITRATION_FEE;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates arbitration fee
    /// @param newFee New arbitration fee amount
    function setArbitrationFee(uint256 newFee) external onlyOwner {
        _arbitrationFee = newFee;
    }

    /// @notice Updates fee token
    /// @param newFeeToken New fee token address
    function setFeeToken(address newFeeToken) external onlyOwner {
        feeToken = newFeeToken;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Request arbitration for a user's reputation dispute
    /// @dev This function allows users with reputation below the normal threshold to dispute
    ///      reputation penalties. The function validates user eligibility, processes fee payment,
    ///      and creates a new arbitration request in PENDING status.
    ///      Requirements:
    ///      - User reputation must be between MIN_REPUTATION_FOR_ARBITRATION and MAX_REPUTATION_FOR_ARBITRATION
    ///      - AT_RISK users must have sufficient stake
    ///      - Arbitration fee must be paid in full
    /// @param user Address of the user whose reputation is being disputed
    /// @param evidence Evidence supporting the arbitration request (must not be empty)
    /// @param depositAmount Arbitration fee amount (must be >= current arbitration fee)
    /// @return arbitrationId The unique identifier for the created arbitration request
    /// @custom:security Protected by reentrancy guard and validates user access through ReputationManager
    /// @custom:economy Requires payment of arbitration fee which is transferred to Treasury
    function requestUserArbitration(
        address user,
        string calldata evidence,
        uint256 depositAmount
    ) external override nonReentrant returns (uint256 arbitrationId) {
        // Validate inputs
        if (bytes(evidence).length == 0) revert InvalidArbitrationEvidence(evidence);
        if (depositAmount < _arbitrationFee) {
            revert InsufficientArbitrationFee(_arbitrationFee, depositAmount);
        }

        // Check if requester can request arbitration
        (bool canRequest, ) = canRequestArbitration(DataTypes.ArbitrationType.USER_REPUTATION, uint256(uint160(user)));
        if (!canRequest) revert UnauthorizedArbitrationAction(msg.sender);

        // Transfer arbitration fee to this contract, then deposit to treasury
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), depositAmount);
        IERC20(feeToken).forceApprove(address(treasury), depositAmount);

        arbitrationId = _createArbitration(
            DataTypes.ArbitrationType.USER_REPUTATION,
            uint256(uint160(user)),
            evidence,
            depositAmount
        );

        emit ArbitrationRequested(
            arbitrationId,
            msg.sender,
            DataTypes.ArbitrationType.USER_REPUTATION,
            uint256(uint160(user)),
            depositAmount,
            evidence
        );
    }

    /// @notice Requests arbitration for submission status
    /// @param submissionId ID of the affected submission
    /// @param evidence Evidence supporting the arbitration request
    /// @param depositAmount Arbitration fee deposit
    /// @return arbitrationId ID of the created arbitration request
    function requestSubmissionArbitration(
        uint256 submissionId,
        string calldata evidence,
        uint256 depositAmount
    ) external override nonReentrant returns (uint256 arbitrationId) {
        // Validate inputs
        if (bytes(evidence).length == 0) revert InvalidArbitrationEvidence(evidence);
        if (depositAmount < _arbitrationFee) {
            revert InsufficientArbitrationFee(_arbitrationFee, depositAmount);
        }

        // Check if requester can request arbitration
        (bool canRequest, ) = canRequestArbitration(DataTypes.ArbitrationType.SUBMISSION_STATUS, submissionId);
        if (!canRequest) revert UnauthorizedArbitrationAction(msg.sender);

        // Verify submission exists
        submissionManager.getSubmission(submissionId);

        // Transfer arbitration fee to this contract, then deposit to treasury
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), depositAmount);
        IERC20(feeToken).forceApprove(address(treasury), depositAmount);

        arbitrationId = _createArbitration(
            DataTypes.ArbitrationType.SUBMISSION_STATUS,
            submissionId,
            evidence,
            depositAmount
        );

        emit ArbitrationRequested(
            arbitrationId,
            msg.sender,
            DataTypes.ArbitrationType.SUBMISSION_STATUS,
            submissionId,
            depositAmount,
            evidence
        );
    }

    /// @notice Resolves an arbitration request (admin only)
    /// @param arbitrationId ID of the arbitration request
    /// @param decision Decision on the arbitration
    /// @param reason Reason for the decision
    function resolveArbitration(
        uint256 arbitrationId,
        DataTypes.ArbitrationStatus decision,
        string calldata reason
    ) external override onlyOwner arbitrationExists(arbitrationId) {
        DataTypes.ArbitrationRequest storage arbitration = _arbitrations[arbitrationId];

        if (arbitration.status != DataTypes.ArbitrationStatus.PENDING) {
            revert ArbitrationAlreadyResolved(arbitrationId);
        }

        arbitration.status = decision;
        arbitration.resolvedAt = block.timestamp;
        arbitration.resolver = msg.sender;

        // Remove from pending arbitrations
        _removeFromPendingArbitrations(arbitrationId);

        emit ArbitrationResolved(arbitrationId, msg.sender, decision, reason, block.timestamp);

        // Handle decision consequences
        if (decision == DataTypes.ArbitrationStatus.APPROVED) {
            // Arbitration approved - execute remedial actions
            if (arbitration.arbitrationType == DataTypes.ArbitrationType.USER_REPUTATION) {
                address user = address(uint160(arbitration.targetId));
                (uint256 currentReputation, , , , ) = reputationManager.getUserReputation(user);

                if (currentReputation < _MIN_REPUTATION_FOR_ARBITRATION) {
                    uint256 delta = _MIN_REPUTATION_FOR_ARBITRATION - currentReputation;
                    reputationManager.updateReputation(user, int256(uint256(delta)), Messages.ARBITRATION_APPROVED);
                }

                if (arbitration.depositAmount > 0) {
                    treasury.withdrawArbitrationFee(
                        arbitrationId,
                        arbitration.requester,
                        feeToken,
                        arbitration.depositAmount
                    );
                    emit ArbitrationFeeRefunded(arbitrationId, arbitration.requester, arbitration.depositAmount);
                }
            } else if (arbitration.arbitrationType == DataTypes.ArbitrationType.SUBMISSION_STATUS) {
                uint256 submissionId = arbitration.targetId;
                submissionManager.restoreSubmissionStatus(submissionId, DataTypes.SubmissionStatus.NORMAL, reason);

                if (arbitration.depositAmount > 0) {
                    treasury.withdrawArbitrationFee(
                        arbitrationId,
                        arbitration.requester,
                        feeToken,
                        arbitration.depositAmount
                    );
                    emit ArbitrationFeeRefunded(arbitrationId, arbitration.requester, arbitration.depositAmount);
                }
            }
        } else if (decision == DataTypes.ArbitrationStatus.REJECTED) {
            // Arbitration rejected - penalize requester
            reputationManager.updateReputation(
                arbitration.requester,
                -100, // -10.0 reputation penalty
                Messages.ARBITRATION_REJECTED
            );
        }
    }

    /// @notice Executes approved arbitration for user reputation
    /// @param arbitrationId ID of the approved arbitration
    /// @param reputationIncrease Amount to increase user's reputation
    function executeUserArbitration(
        uint256 arbitrationId,
        uint256 reputationIncrease
    ) external override onlyOwner arbitrationExists(arbitrationId) {
        DataTypes.ArbitrationRequest storage arbitration = _arbitrations[arbitrationId];

        if (
            arbitration.status != DataTypes.ArbitrationStatus.APPROVED ||
            arbitration.arbitrationType != DataTypes.ArbitrationType.USER_REPUTATION
        ) {
            revert UnauthorizedArbitrationAction(msg.sender);
        }

        address user = address(uint160(arbitration.targetId));

        // Increase user reputation
        reputationManager.increaseReputationAdmin(user, reputationIncrease, Messages.ARBITRATION_RESOLUTION);

        // Refund arbitration fee to requester
        treasury.withdrawArbitrationFee(arbitrationId, arbitration.requester, feeToken, arbitration.depositAmount);

        emit ArbitrationFeeRefunded(arbitrationId, arbitration.requester, arbitration.depositAmount);
    }

    /// @notice Executes approved arbitration for submission status
    /// @param arbitrationId ID of the approved arbitration
    /// @param newStatus New status to set for the submission
    function executeSubmissionArbitration(
        uint256 arbitrationId,
        DataTypes.SubmissionStatus newStatus
    ) external override onlyOwner arbitrationExists(arbitrationId) {
        DataTypes.ArbitrationRequest storage arbitration = _arbitrations[arbitrationId];

        if (
            arbitration.status != DataTypes.ArbitrationStatus.APPROVED ||
            arbitration.arbitrationType != DataTypes.ArbitrationType.SUBMISSION_STATUS
        ) {
            revert UnauthorizedArbitrationAction(msg.sender);
        }

        uint256 submissionId = arbitration.targetId;

        // Restore submission status
        submissionManager.restoreSubmissionStatus(submissionId, newStatus, Messages.ARBITRATION_RESOLUTION);

        // Refund arbitration fee to requester
        treasury.withdrawArbitrationFee(arbitrationId, arbitration.requester, feeToken, arbitration.depositAmount);

        emit ArbitrationFeeRefunded(arbitrationId, arbitration.requester, arbitration.depositAmount);
    }

    /// @notice Claims refund for approved arbitration
    /// @param arbitrationId ID of the arbitration
    function claimArbitrationRefund(
        uint256 arbitrationId
    ) external override arbitrationExists(arbitrationId) nonReentrant {
        DataTypes.ArbitrationRequest storage arbitration = _arbitrations[arbitrationId];

        if (arbitration.requester != msg.sender) {
            revert UnauthorizedArbitrationAction(msg.sender);
        }

        if (arbitration.status != DataTypes.ArbitrationStatus.APPROVED) {
            revert ArbitrationStillPending(arbitrationId);
        }

        uint256 refundAmount = arbitration.depositAmount;
        arbitration.depositAmount = 0; // Prevent double refund

        treasury.withdrawArbitrationFee(arbitrationId, msg.sender, feeToken, refundAmount);

        emit ArbitrationFeeRefunded(arbitrationId, msg.sender, refundAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets arbitration request information
    /// @param arbitrationId ID of the arbitration request
    /// @return arbitration Arbitration request struct
    function getArbitration(
        uint256 arbitrationId
    )
        external
        view
        override
        arbitrationExists(arbitrationId)
        returns (DataTypes.ArbitrationRequest memory arbitration)
    {
        return _arbitrations[arbitrationId];
    }

    /// @notice Gets arbitrations by requester
    /// @param requester Address of the requester
    /// @param offset Starting index
    /// @param limit Maximum number of arbitrations to return
    /// @return arbitrationIds Array of arbitration IDs
    function getArbitrationsByRequester(
        address requester,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory arbitrationIds) {
        return _paginateArray(_requesterArbitrations[requester], offset, limit);
    }

    /// @notice Gets pending arbitrations
    /// @param offset Starting index
    /// @param limit Maximum number of arbitrations to return
    /// @return arbitrationIds Array of pending arbitration IDs
    function getPendingArbitrations(
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory arbitrationIds) {
        return _paginateArray(_pendingArbitrations, offset, limit);
    }

    /// @notice Gets arbitrations by type
    /// @param arbitrationType Type of arbitration
    /// @param offset Starting index
    /// @param limit Maximum number of arbitrations to return
    /// @return arbitrationIds Array of arbitration IDs
    function getArbitrationsByType(
        DataTypes.ArbitrationType arbitrationType,
        uint256 offset,
        uint256 limit
    ) external view override returns (uint256[] memory arbitrationIds) {
        return _paginateArray(_arbitrationsByType[arbitrationType], offset, limit);
    }

    /// @notice Gets current arbitration fee
    /// @return fee Current arbitration fee amount
    function getArbitrationFee() external view override returns (uint256 fee) {
        return _arbitrationFee;
    }

    /// @notice Checks if arbitration can be requested for a target
    /// @param arbitrationType Type of arbitration
    /// @param targetId Target ID (user address as uint256 or submission ID)
    /// @return canRequest Whether arbitration can be requested
    /// @return reason Reason if arbitration cannot be requested
    function canRequestArbitration(
        DataTypes.ArbitrationType arbitrationType,
        uint256 targetId
    ) public view override returns (bool canRequest, string memory reason) {
        // Check requester's reputation
        (uint256 reputation, , , , ) = reputationManager.getUserReputation(msg.sender);
        if (reputation < _MIN_REPUTATION_FOR_ARBITRATION) {
            return (false, Messages.INSUFFICIENT_REPUTATION_ARBITRATION);
        }

        // Check user access
        (bool canAccess, string memory accessReason) = reputationManager.validateUserAccess(msg.sender);
        if (!canAccess) {
            return (false, accessReason);
        }

        if (arbitrationType == DataTypes.ArbitrationType.USER_REPUTATION) {
            address user = address(uint160(targetId));
            (uint256 userReputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(user);

            if (status == DataTypes.UserStatus.UNINITIALIZED) {
                return (false, Messages.USER_NOT_INITIALIZED);
            }

            // Only allow arbitration for users with low reputation
            if (userReputation >= 600) {
                // 60.0 reputation
                return (false, Messages.REPUTATION_TOO_HIGH_ARBITRATION);
            }
        } else if (arbitrationType == DataTypes.ArbitrationType.SUBMISSION_STATUS) {
            // Check if submission exists and is in a state that can be arbitrated
            try submissionManager.getSubmission(targetId) returns (DataTypes.SubmissionInfo memory submission) {
                // Allow arbitration for submissions that could be unfairly treated
                if (submission.status == DataTypes.SubmissionStatus.ADOPTED) {
                    return (false, Messages.SUBMISSION_ALREADY_ADOPTED);
                }
            } catch {
                return (false, Messages.SUBMISSION_NOT_REVIEWABLE);
            }
        }

        return (true, Messages.ARBITRATION_CAN_REQUEST);
    }

    /// @notice Gets total number of arbitrations
    /// @return totalArbitrations Total arbitration count
    function getTotalArbitrations() external view override returns (uint256 totalArbitrations) {
        return _totalArbitrations;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates a new arbitration request
    /// @param arbitrationType Type of arbitration
    /// @param targetId Target ID
    /// @param evidence Evidence string
    /// @param depositAmount Deposit amount
    /// @return arbitrationId Created arbitration ID
    function _createArbitration(
        DataTypes.ArbitrationType arbitrationType,
        uint256 targetId,
        string calldata evidence,
        uint256 depositAmount
    ) internal returns (uint256 arbitrationId) {
        arbitrationId = _nextArbitrationId;
        unchecked {
            ++_nextArbitrationId;
            ++_totalArbitrations;
        }

        // Create arbitration request
        DataTypes.ArbitrationRequest storage arbitration = _arbitrations[arbitrationId];
        arbitration.id = arbitrationId;
        arbitration.requester = msg.sender;
        arbitration.arbitrationType = arbitrationType;
        arbitration.targetId = targetId;
        arbitration.evidence = evidence;
        arbitration.depositAmount = depositAmount;
        arbitration.status = DataTypes.ArbitrationStatus.PENDING;
        arbitration.requestedAt = block.timestamp;
        arbitration.resolvedAt = 0;
        arbitration.resolver = address(0);

        // Deposit arbitration fee
        treasury.depositArbitrationFee(arbitrationId, feeToken, depositAmount);

        // Add to mappings
        _requesterArbitrations[msg.sender].push(arbitrationId);
        _arbitrationsByType[arbitrationType].push(arbitrationId);
        _pendingArbitrations.push(arbitrationId);
    }

    /// @notice Removes arbitration from pending list
    /// @param arbitrationId Arbitration ID to remove
    function _removeFromPendingArbitrations(uint256 arbitrationId) internal {
        uint256 length = _pendingArbitrations.length;
        for (uint256 i = 0; i < length; ) {
            if (_pendingArbitrations[i] == arbitrationId) {
                _pendingArbitrations[i] = _pendingArbitrations[length - 1];
                _pendingArbitrations.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Paginates an array
    /// @param array Source array
    /// @param offset Starting index
    /// @param limit Maximum items to return
    /// @return result Paginated array
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
