// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IHermisSBT
/// @notice Interface for Hermis Soulbound Token that represents user credentials and platform achievements
/// @dev This interface defines the standard Soulbound Token functionality including:
///      - Non-transferable token minting for unique user identity
///      - Dynamic metadata updates reflecting user reputation and achievements
///      - Category-based skill tracking and score management
///      - Integration with reputation system for credential verification
/// @custom:interface Defines standard SBT behavior for user credential and achievement tracking
/// @author Hermis Team
interface IHermisSBT {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CUSTOM ERRORS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Error when attempting to transfer a soulbound token
    error SoulboundTokenNotTransferable();

    /// @notice Error when token ID does not exist in the contract
    error TokenNotFound(uint256 tokenId);

    /// @notice Error when attempting to mint a token for user who already has one
    error TokenAlreadyExists(address user);

    /// @notice Error when caller lacks permission to update SBT data
    error UnauthorizedSBTUpdate(address caller);

    /// @notice Error when metadata update parameters are invalid
    error InvalidMetadataUpdate();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new SBT is minted for a user
    /// @param user Address of the user for whom the SBT was minted
    /// @param tokenId Unique ID of the minted Soulbound Token
    event SBTMinted(address indexed user, uint256 indexed tokenId);

    /// @notice Emitted when user reputation data is updated in the SBT
    /// @param user Address of the user whose reputation data was updated
    /// @param tokenId ID of the SBT token that was updated
    /// @param newReputation Updated reputation score stored in the SBT
    /// @param newStatus Updated user status reflected in the SBT
    event ReputationUpdated(
        address indexed user,
        uint256 indexed tokenId,
        uint256 newReputation,
        DataTypes.UserStatus newStatus
    );

    /// @notice Emitted when user category score is updated in the SBT
    /// @param user Address of the user whose category score was updated
    /// @param tokenId ID of the SBT token that was updated
    /// @param category Name of the skill category that was updated
    /// @param newScore Updated score value for the specified category
    event CategoryScoreUpdated(address indexed user, uint256 indexed tokenId, string category, uint256 newScore);

    /// @notice Emitted when user stake amount is updated in the SBT
    /// @param user Address of the user whose stake amount was updated
    /// @param tokenId ID of the SBT token that was updated
    /// @param newStakeAmount Updated stake token amount displayed in the SBT
    event StakeAmountUpdated(address indexed user, uint256 indexed tokenId, uint256 newStakeAmount);

    /// @notice Emitted when SBT metadata is refreshed with updated information
    /// @param tokenId ID of the SBT token whose metadata was refreshed
    /// @param newMetadataURI Updated metadata URI pointing to current credential data
    event MetadataRefreshed(uint256 indexed tokenId, string newMetadataURI);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       SBT FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mints a new Soulbound Token for user credential tracking
    /// @dev Creates a unique, non-transferable token representing user identity and achievements.
    ///      Should validate user doesn't already have an SBT before minting.
    /// @param user Address of the user to mint the SBT credential for
    /// @return tokenId Unique ID of the minted Soulbound Token
    /// @custom:security Only callable by authorized platform contracts, ensures one SBT per user
    function mint(address user) external returns (uint256 tokenId);

    /// @notice Updates user reputation data stored in the SBT metadata
    /// @dev Synchronizes SBT data with reputation manager updates for credential accuracy.
    ///      Should validate new values and emit update events.
    /// @param user Address of the user whose SBT reputation data is being updated
    /// @param newReputation Updated reputation score to store in SBT
    /// @param newStatus Updated user status to reflect in SBT credentials
    /// @custom:security Only callable by authorized reputation management contracts
    function updateReputation(address user, uint256 newReputation, DataTypes.UserStatus newStatus) external;

    /// @notice Updates user category skill score in the SBT credentials
    /// @dev Synchronizes category expertise scores with platform activity for skill verification.
    ///      Should validate category name and score value before updating.
    /// @param user Address of the user whose category score is being updated
    /// @param category String identifier of the skill category being updated
    /// @param newScore Updated score value for the specified category
    /// @custom:security Only callable by authorized platform contracts tracking user skills
    function updateCategoryScore(address user, string calldata category, uint256 newScore) external;

    /// @notice Updates user stake amount displayed in the SBT credentials
    /// @dev Synchronizes staking data with reputation manager for credential completeness.
    ///      Should validate stake amount and update SBT metadata accordingly.
    /// @param user Address of the user whose stake amount is being updated
    /// @param newStakeAmount Updated stake token amount to display in SBT
    /// @custom:security Only callable by authorized staking management contracts
    function updateStakeAmount(address user, uint256 newStakeAmount) external;

    /// @notice Refreshes SBT metadata with latest user data and achievements
    /// @dev Regenerates token metadata URI with current user statistics and credentials.
    ///      Should compile latest reputation, scores, and achievement data.
    /// @param tokenId ID of the SBT token to refresh metadata for
    /// @custom:security Can be called by token owner or authorized contracts
    function refreshMetadata(uint256 tokenId) external;

    /// @notice Gets the SBT token ID associated with a user address
    /// @dev Returns the unique token identifier for user credential lookup.
    /// @param user Address of the user to get SBT token ID for
    /// @return tokenId User's SBT token ID (0 if no SBT has been minted for this user)
    /// @custom:view This function is read-only and returns user token mapping
    function getUserTokenId(address user) external view returns (uint256 tokenId);

    /// @notice Gets comprehensive user credential data from the SBT
    /// @dev Returns complete user profile data stored in SBT for credential verification.
    /// @param user Address of the user to retrieve comprehensive data for
    /// @return tokenId User's SBT token identifier
    /// @return reputation Current reputation score stored in SBT
    /// @return status Current user status reflected in credentials
    /// @return stakeAmount Current stake amount displayed in SBT
    /// @return exists Whether the user has a minted SBT token
    /// @custom:view This function is read-only and returns complete user credential data
    function getUserData(
        address user
    )
        external
        view
        returns (uint256 tokenId, uint256 reputation, DataTypes.UserStatus status, uint256 stakeAmount, bool exists);

    /// @notice Gets user's skill score in a specific category from SBT
    /// @dev Returns category expertise score stored in SBT credentials.
    /// @param user Address of the user to get category score for
    /// @param category String identifier of the skill category to retrieve
    /// @return score Current score value for the specified category
    /// @custom:view This function is read-only and returns category skill data
    function getUserCategoryScore(address user, string calldata category) external view returns (uint256 score);

    /// @notice Gets all category skill scores for a user from SBT credentials
    /// @dev Returns complete skill profile with all categories and corresponding scores.
    /// @param user Address of the user to retrieve all category scores for
    /// @return categories Array of skill category names the user has scores in
    /// @return scores Array of corresponding score values for each category
    /// @custom:view This function is read-only and returns complete skill profile
    function getUserAllCategoryScores(
        address user
    ) external view returns (string[] memory categories, uint256[] memory scores);

    /// @notice Checks whether a user has a minted SBT credential
    /// @dev Validates if user has platform credentials represented by SBT.
    /// @param user Address of the user to check SBT existence for
    /// @return exists Whether the user has a minted Soulbound Token
    /// @custom:view This function is read-only and validates SBT existence
    function hasSBT(address user) external view returns (bool exists);

    /// @notice Gets SBT token URI with dynamic metadata reflecting current user status
    /// @dev Returns metadata URI that dynamically updates with user achievements and credentials.
    ///      Should include reputation, skills, achievements, and visual representation.
    /// @param tokenId ID of the SBT token to get metadata URI for
    /// @return uri Token metadata URI pointing to current credential data
    /// @custom:view This function is read-only and returns dynamic metadata URI
    function tokenURI(uint256 tokenId) external view returns (string memory uri);

    /// @notice Gets contract URI for SBT collection metadata and platform information
    /// @dev Returns collection-level metadata describing the Hermis SBT credential system.
    /// @return uri Contract metadata URI with platform and collection information
    /// @custom:view This function is read-only and returns static collection metadata
    function contractURI() external view returns (string memory uri);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OVERRIDE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Override transfer functions to enforce soulbound behavior
    /// @dev These functions are overridden to revert and prevent token transfers.
    ///      Ensures tokens remain bound to original recipient for credential integrity.
    /// @param from Address to transfer from (always reverts for soulbound tokens)
    /// @param to Address to transfer to (always reverts for soulbound tokens)
    /// @param tokenId Token ID to transfer (always reverts for soulbound tokens)
    /// @custom:security All transfer functions revert to maintain soulbound property
    function transferFrom(address from, address to, uint256 tokenId) external pure;

    /// @notice Override safe transfer to prevent soulbound token movement
    /// @param from Address to transfer from (always reverts for soulbound tokens)
    /// @param to Address to transfer to (always reverts for soulbound tokens)
    /// @param tokenId Token ID to transfer (always reverts for soulbound tokens)
    /// @param data Additional data (always reverts for soulbound tokens)
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external pure;

    /// @notice Override approve to prevent soulbound token delegation
    /// @param to Address to approve (always reverts for soulbound tokens)
    /// @param tokenId Token ID to approve (always reverts for soulbound tokens)
    function approve(address to, uint256 tokenId) external pure;

    /// @notice Override approval for all to prevent soulbound token delegation
    /// @param operator Address to set approval for (always reverts for soulbound tokens)
    /// @param approved Approval status (always reverts for soulbound tokens)
    function setApprovalForAll(address operator, bool approved) external pure;
}
