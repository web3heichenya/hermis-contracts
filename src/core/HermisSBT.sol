// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// === IMPORTS ===

// 1. OpenZeppelin imports
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

// 2. Internal interfaces
import {IHermisSBT} from "../interfaces/IHermisSBT.sol";

// 3. Internal libraries
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title HermisSBT
/// @notice Soulbound Token representing user credentials and achievements on the Hermis platform
/// @dev This contract implements a non-transferable NFT system that provides:
///      - Unique identity tokens for platform users with immutable ownership
///      - Dynamic metadata generation reflecting current user reputation and status
///      - Category-specific expertise scoring for specialized skill representation
///      - Real-time stake amount tracking for reputation-based access control
///      - SVG image generation with status-based visual indicators
///      - Complete soulbound functionality preventing transfers and approvals
/// @custom:soulbound Tokens cannot be transferred, approved, or traded once minted
/// @custom:metadata Generates dynamic JSON metadata with real-time user data
/// @author Hermis Team
contract HermisSBT is IHermisSBT, ERC721, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         LIBRARIES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    using Strings for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mapping of user addresses to their unique token IDs (one token per user)
    mapping(address => uint256) private _userTokenId;

    /// @notice Mapping of token IDs to current reputation scores (with 10x precision)
    mapping(uint256 => uint256) private _tokenReputation;

    /// @notice Mapping of token IDs to current user status (NORMAL/AT_RISK/BLACKLISTED)
    mapping(uint256 => DataTypes.UserStatus) private _tokenStatus;

    /// @notice Mapping of token IDs to current stake amounts for reputation requirements
    mapping(uint256 => uint256) private _tokenStakeAmount;

    /// @notice Double mapping of token IDs to category names to category expertise scores
    mapping(uint256 => mapping(string => uint256)) private _tokenCategoryScores;

    /// @notice Mapping of token IDs to arrays of category names for iteration
    /// @dev Used to efficiently retrieve all categories a user has scores in
    mapping(uint256 => string[]) private _tokenCategories;

    /// @notice Counter for generating unique token IDs, starts from 1
    uint256 private _nextTokenId;

    /// @notice Address of the ReputationManager contract authorized to update SBT data
    address public reputationManager;

    /// @notice Base URI for token metadata (optional, falls back to dynamic generation)
    string private _baseTokenURI;

    /// @notice Contract-level metadata URI for collection information
    string private _contractMetadataURI;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyReputationManager() {
        if (msg.sender != reputationManager && msg.sender != owner()) {
            revert UnauthorizedSBTUpdate(msg.sender);
        }
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the HermisSBT contract with collection metadata
    /// @dev Sets up the ERC721 contract with name and symbol, configures metadata URIs,
    ///      and initializes token ID counter. ReputationManager address is set separately after deployment.
    /// @param owner Address that will have administrative control over the contract
    /// @param name ERC721 collection name (e.g., "Hermis Soulbound Token")
    /// @param symbol ERC721 collection symbol (e.g., "HSBT")
    /// @param baseURI Base URI for token metadata (optional, can be empty for dynamic generation)
    /// @param contractMetadataURI URI for contract-level metadata
    /// @custom:soulbound Contract enforces non-transferable behavior after deployment
    constructor(
        address owner,
        string memory name,
        string memory symbol,
        string memory baseURI,
        string memory contractMetadataURI
    ) ERC721(name, symbol) Ownable(owner) {
        _baseTokenURI = baseURI;
        _contractMetadataURI = contractMetadataURI;
        _nextTokenId = 1; // Start from 1
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the ReputationManager contract address for authorized updates
    /// @dev Only the authorized ReputationManager can mint tokens and update user data.
    ///      This should be called once after both contracts are deployed.
    /// @param reputationManagerAddress Address of the deployed ReputationManager contract
    /// @custom:security Only callable by contract owner during initial setup
    function setReputationManager(address reputationManagerAddress) external onlyOwner {
        reputationManager = reputationManagerAddress;
    }

    /// @notice Updates the base URI for token metadata
    /// @dev If set, tokens will use {baseURI}{tokenId} for metadata. If empty,
    ///      tokens will use dynamically generated JSON metadata with SVG images.
    /// @param newBaseURI New base URI for token metadata (can be empty for dynamic generation)
    /// @custom:security Only callable by contract owner for metadata management
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    /// @notice Updates the contract-level metadata URI
    /// @dev Contract metadata provides collection-level information for marketplaces and interfaces.
    /// @param newContractURI New contract metadata URI for collection information
    /// @custom:security Only callable by contract owner for collection metadata management
    function setContractURI(string calldata newContractURI) external onlyOwner {
        _contractMetadataURI = newContractURI;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mints a new Soulbound Token for a user with default reputation data
    /// @dev Only callable by ReputationManager when a user is initialized. Each user can only
    ///      have one SBT. Initializes token with default reputation (100.0) and NORMAL status.
    /// @param user Address to mint the SBT for (becomes the permanent owner)
    /// @return tokenId ID of the minted token
    /// @custom:security Only callable by authorized ReputationManager contract
    /// @custom:soulbound Token becomes permanently bound to the user address
    function mint(address user) external override onlyReputationManager returns (uint256 tokenId) {
        if (_userTokenId[user] != 0) revert TokenAlreadyExists(user);

        tokenId = _nextTokenId;
        unchecked {
            ++_nextTokenId;
        }

        _userTokenId[user] = tokenId;
        _mint(user, tokenId);

        // Initialize with default values
        _tokenReputation[tokenId] = 1000; // 100.0 default reputation
        _tokenStatus[tokenId] = DataTypes.UserStatus.NORMAL;
        _tokenStakeAmount[tokenId] = 0;

        emit SBTMinted(user, tokenId);
    }

    /// @notice Updates user reputation and status data in the SBT metadata
    /// @dev Called by ReputationManager when user reputation changes. Updates both numerical
    ///      reputation score and status enum, then refreshes metadata for real-time display.
    /// @param user Address of the user whose reputation to update
    /// @param newReputation New reputation score (with 10x precision)
    /// @param newStatus New user status (NORMAL/AT_RISK/BLACKLISTED)
    /// @custom:security Only callable by authorized ReputationManager contract
    /// @custom:metadata Automatically refreshes token metadata after update
    function updateReputation(
        address user,
        uint256 newReputation,
        DataTypes.UserStatus newStatus
    ) external override onlyReputationManager {
        uint256 tokenId = _userTokenId[user];
        if (tokenId == 0) return; // No token exists

        _tokenReputation[tokenId] = newReputation;
        _tokenStatus[tokenId] = newStatus;

        emit ReputationUpdated(user, tokenId, newReputation, newStatus);
        emit MetadataRefreshed(tokenId, tokenURI(tokenId));
    }

    /// @notice Updates user category expertise score in the SBT metadata
    /// @dev Called by ReputationManager when user claims category scores. Adds new categories
    ///      to the user's category list when they first earn scores in that category.
    /// @param user Address of the user whose category score to update
    /// @param category Category name (e.g., "development", "design")
    /// @param newScore New category expertise score
    /// @custom:security Only callable by authorized ReputationManager contract
    /// @custom:metadata Automatically refreshes token metadata after update
    function updateCategoryScore(
        address user,
        string calldata category,
        uint256 newScore
    ) external override onlyReputationManager {
        uint256 tokenId = _userTokenId[user];
        if (tokenId == 0) return; // No token exists

        // Add category if it doesn't exist
        if (_tokenCategoryScores[tokenId][category] == 0 && newScore > 0) {
            _tokenCategories[tokenId].push(category);
        }

        _tokenCategoryScores[tokenId][category] = newScore;

        emit CategoryScoreUpdated(user, tokenId, category, newScore);
        emit MetadataRefreshed(tokenId, tokenURI(tokenId));
    }

    /// @notice Updates user stake amount in the SBT metadata
    /// @dev Called by ReputationManager when user stakes or unstakes tokens. Reflects
    ///      current staking status for reputation-based access control visualization.
    /// @param user Address of the user whose stake amount to update
    /// @param newStakeAmount New stake amount (0 if no tokens are staked)
    /// @custom:security Only callable by authorized ReputationManager contract
    /// @custom:metadata Automatically refreshes token metadata after update
    function updateStakeAmount(address user, uint256 newStakeAmount) external override onlyReputationManager {
        uint256 tokenId = _userTokenId[user];
        if (tokenId == 0) return; // No token exists

        _tokenStakeAmount[tokenId] = newStakeAmount;

        emit StakeAmountUpdated(user, tokenId, newStakeAmount);
        emit MetadataRefreshed(tokenId, tokenURI(tokenId));
    }

    /// @notice Manually refreshes metadata for a specific token
    /// @dev Emits MetadataRefreshed event to notify marketplaces and interfaces of metadata updates.
    ///      Can be called to force metadata refresh without changing underlying data.
    /// @param tokenId ID of the token to refresh metadata for
    /// @custom:security Only callable by authorized ReputationManager contract
    /// @custom:metadata Forces metadata refresh event emission
    function refreshMetadata(uint256 tokenId) external override onlyReputationManager tokenExists(tokenId) {
        emit MetadataRefreshed(tokenId, tokenURI(tokenId));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the unique token ID for a specific user
    /// @dev Each user has at most one SBT. Returns 0 if the user doesn't have an SBT yet.
    /// @param user Address of the user to query
    /// @return tokenId User's unique token ID (0 if no SBT exists)
    /// @custom:view This function is read-only and provides user-to-token mapping
    function getUserTokenId(address user) external view override returns (uint256 tokenId) {
        return _userTokenId[user];
    }

    /// @notice Gets comprehensive user data from their SBT in a single call
    /// @dev Efficiently retrieves all user data stored in the SBT for frontend queries.
    ///      Returns default values if the user doesn't have an SBT.
    /// @param user Address of the user to query
    /// @return tokenId User's token ID (0 if no SBT)
    /// @return reputation Current reputation score (with 10x precision)
    /// @return status Current user status (NORMAL/AT_RISK/BLACKLISTED)
    /// @return stakeAmount Current stake amount
    /// @return exists Whether the user has an SBT
    /// @custom:view This function is read-only and provides efficient bulk data access
    function getUserData(
        address user
    )
        external
        view
        override
        returns (uint256 tokenId, uint256 reputation, DataTypes.UserStatus status, uint256 stakeAmount, bool exists)
    {
        tokenId = _userTokenId[user];
        exists = tokenId != 0;

        if (exists) {
            reputation = _tokenReputation[tokenId];
            status = _tokenStatus[tokenId];
            stakeAmount = _tokenStakeAmount[tokenId];
        }
    }

    /// @notice Gets user's expertise score in a specific category
    /// @dev Returns the claimed category score for a user in the specified category.
    ///      Returns 0 if user has no SBT or no score in the category.
    /// @param user Address of the user to query
    /// @param category Category name to get score for (e.g., "development", "design")
    /// @return score User's expertise score in the specified category
    /// @custom:view This function is read-only and provides category-specific data
    function getUserCategoryScore(
        address user,
        string calldata category
    ) external view override returns (uint256 score) {
        uint256 tokenId = _userTokenId[user];
        if (tokenId == 0) return 0;

        return _tokenCategoryScores[tokenId][category];
    }

    /// @notice Gets all category scores for a user in aligned arrays
    /// @dev Returns two arrays with matching indices: category names and their corresponding scores.
    ///      Returns empty arrays if user has no SBT or no category scores.
    /// @param user Address of the user to query
    /// @return categories Array of category names user has scores in
    /// @return scores Array of corresponding expertise scores (aligned with categories)
    /// @custom:view This function is read-only and provides complete category expertise data
    function getUserAllCategoryScores(
        address user
    ) external view override returns (string[] memory categories, uint256[] memory scores) {
        uint256 tokenId = _userTokenId[user];
        if (tokenId == 0) {
            return (new string[](0), new uint256[](0));
        }

        categories = _tokenCategories[tokenId];
        scores = new uint256[](categories.length);

        for (uint256 i = 0; i < categories.length; ) {
            scores[i] = _tokenCategoryScores[tokenId][categories[i]];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Checks if a user has been issued a Soulbound Token
    /// @dev Simple boolean check for SBT existence, useful for access control and validation.
    /// @param user Address of the user to check
    /// @return exists Whether the user has been issued an SBT
    /// @custom:view This function is read-only and provides existence validation
    function hasSBT(address user) external view override returns (bool exists) {
        return _userTokenId[user] != 0;
    }

    /// @notice Gets token metadata URI with real-time user data
    /// @dev Returns either static metadata (if baseURI is set) or dynamically generated JSON
    ///      with SVG image reflecting current user status and reputation.
    /// @param tokenId ID of the token to get metadata for
    /// @return uri Complete metadata URI (static URL or data URI with JSON)
    /// @custom:metadata Generates dynamic JSON with SVG when baseURI is empty
    /// @custom:view This function is read-only and provides ERC721 compliance
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, IHermisSBT) tokenExists(tokenId) returns (string memory uri) {
        if (bytes(_baseTokenURI).length > 0) {
            return string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
        }

        // Generate dynamic JSON metadata
        return _generateDynamicMetadata(tokenId);
    }

    /// @notice Gets contract-level metadata URI for the SBT collection
    /// @dev Provides collection-wide metadata for marketplaces and interfaces.
    /// @return uri Contract metadata URI containing collection information
    /// @custom:view This function is read-only and provides collection metadata
    function contractURI() external view override returns (string memory uri) {
        return _contractMetadataURI;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OVERRIDE FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Override approve functions to make token soulbound
    /// @dev Soulbound tokens cannot be approved for transfer
    // solhint-disable-next-line use-natspec
    function approve(address, /*to*/ uint256 /*tokenId*/) public pure override(ERC721, IHermisSBT) {
        revert SoulboundTokenNotTransferable();
    }

    /// @notice Override setApprovalForAll to make token soulbound
    /// @dev Soulbound tokens cannot be approved for transfer
    // solhint-disable-next-line use-natspec
    function setApprovalForAll(address, /*operator*/ bool /*approved*/) public pure override(ERC721, IHermisSBT) {
        revert SoulboundTokenNotTransferable();
    }

    /// @notice Override transfer functions to make token soulbound
    /// @dev Soulbound tokens cannot be transferred
    // solhint-disable-next-line use-natspec
    function transferFrom(
        address,
        /*from*/
        address,
        /*to*/
        uint256 /*tokenId*/
    ) public pure override(ERC721, IHermisSBT) {
        revert SoulboundTokenNotTransferable();
    }

    /// @notice Override safeTransferFrom functions to make token soulbound
    /// @dev Soulbound tokens cannot be transferred
    // solhint-disable-next-line use-natspec
    function safeTransferFrom(
        address,
        /*from*/
        address,
        /*to*/
        uint256,
        /*tokenId*/
        bytes memory /*data*/
    ) public pure override(ERC721, IHermisSBT) {
        revert SoulboundTokenNotTransferable();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Generates dynamic JSON metadata with embedded SVG for a token
    /// @dev Creates complete ERC721 metadata JSON with name, description, SVG image, and attributes.
    ///      Used when no baseURI is set to provide real-time metadata reflecting user status.
    /// @param tokenId Token ID to generate metadata for
    /// @return metadata Complete data URI with base64-encoded JSON metadata
    /// @custom:metadata Includes SVG image and comprehensive user attributes
    function _generateDynamicMetadata(uint256 tokenId) internal view returns (string memory metadata) {
        uint256 reputation = _tokenReputation[tokenId];
        DataTypes.UserStatus status = _tokenStatus[tokenId];
        uint256 stakeAmount = _tokenStakeAmount[tokenId];

        // Generate attributes JSON
        string memory attributes = _generateAttributes(tokenId, reputation, status, stakeAmount);

        string memory json = string(
            abi.encodePacked(
                '{"name":"Hermis SBT #',
                tokenId.toString(),
                '","description":"Hermis Platform Soulbound Token representing user credentials and achievements",',
                '"image":"data:image/svg+xml;base64,',
                _generateSVG(tokenId),
                '",',
                '"attributes":[',
                attributes,
                "]}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /// @notice Generates JSON attributes array for NFT metadata
    /// @dev Creates formatted JSON attributes including reputation, status, stake amount,
    ///      and all category scores with proper decimal formatting (dividing by 10 for precision).
    /// @param tokenId Token ID to generate attributes for
    /// @param reputation Reputation score (with 10x precision)
    /// @param status User status enum value
    /// @param stakeAmount Current stake amount
    /// @return attributes Formatted JSON attributes string for metadata
    /// @custom:formatting Converts 10x precision scores to decimal representation
    function _generateAttributes(
        uint256 tokenId,
        uint256 reputation,
        DataTypes.UserStatus status,
        uint256 stakeAmount
    ) internal view returns (string memory attributes) {
        string memory statusStr = _getStatusString(status);

        // Base attributes
        attributes = string(
            abi.encodePacked(
                '{"trait_type":"Reputation","value":',
                (reputation / 10).toString(),
                ".",
                (reputation % 10).toString(),
                "},",
                '{"trait_type":"Status","value":"',
                statusStr,
                '"},',
                '{"trait_type":"Stake Amount","value":',
                stakeAmount.toString(),
                "}"
            )
        );

        // Add category scores
        string[] memory categories = _tokenCategories[tokenId];
        for (uint256 i = 0; i < categories.length; ) {
            uint256 score = _tokenCategoryScores[tokenId][categories[i]];
            if (score > 0) {
                attributes = string(
                    abi.encodePacked(
                        attributes,
                        ',{"trait_type":"',
                        categories[i],
                        ' Score","value":',
                        (score / 10).toString(),
                        ".",
                        (score % 10).toString(),
                        "}"
                    )
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Generates status-based SVG image for the token
    /// @dev Creates a simple SVG with background color based on user status and displays
    ///      token ID and reputation. Colors: Green (Normal), Orange (At Risk), Red (Blacklisted).
    /// @param tokenId Token ID to generate SVG for
    /// @return svg Base64-encoded SVG image string
    /// @custom:visual Uses status-based color coding for immediate status recognition
    function _generateSVG(uint256 tokenId) internal view returns (string memory svg) {
        uint256 reputation = _tokenReputation[tokenId];
        DataTypes.UserStatus status = _tokenStatus[tokenId];

        // Simple SVG based on status
        string memory statusColor = _getStatusColor(status);
        string memory reputationStr = string(
            abi.encodePacked((reputation / 10).toString(), ".", (reputation % 10).toString())
        );

        string memory svgString = string(
            abi.encodePacked(
                '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="100%" height="100%" fill="',
                statusColor,
                '"/>',
                '<text x="50%" y="40%" text-anchor="middle" font-family="Arial" font-size="24" fill="white">Hermis SBT</text>',
                '<text x="50%" y="55%" text-anchor="middle" font-family="Arial" font-size="18" fill="white">#',
                tokenId.toString(),
                "</text>",
                '<text x="50%" y="75%" text-anchor="middle" font-family="Arial" font-size="16" fill="white">Reputation: ',
                reputationStr,
                "</text>",
                "</svg>"
            )
        );

        return Base64.encode(bytes(svgString));
    }

    /// @notice Converts user status enum to human-readable string
    /// @dev Maps UserStatus enum values to their string representations for metadata display.
    /// @param status User status enum value
    /// @return statusStr Human-readable status string ("Normal", "At Risk", "Blacklisted", "Uninitialized")
    /// @custom:pure This function is pure and performs simple enum-to-string conversion
    function _getStatusString(DataTypes.UserStatus status) internal pure returns (string memory statusStr) {
        if (status == DataTypes.UserStatus.NORMAL) {
            return "Normal";
        } else if (status == DataTypes.UserStatus.AT_RISK) {
            return "At Risk";
        } else if (status == DataTypes.UserStatus.BLACKLISTED) {
            return "Blacklisted";
        } else {
            return "Uninitialized";
        }
    }

    /// @notice Gets hex color code based on user status for SVG generation
    /// @dev Maps UserStatus enum values to corresponding colors: Green (Normal), Orange (At Risk),
    ///      Red (Blacklisted), Gray (Uninitialized) for intuitive visual status indication.
    /// @param status User status enum value
    /// @return color Hex color string for SVG background
    /// @custom:pure This function is pure and provides consistent status color mapping
    function _getStatusColor(DataTypes.UserStatus status) internal pure returns (string memory color) {
        if (status == DataTypes.UserStatus.NORMAL) {
            return "#4CAF50"; // Green
        } else if (status == DataTypes.UserStatus.AT_RISK) {
            return "#FF9800"; // Orange
        } else if (status == DataTypes.UserStatus.BLACKLISTED) {
            return "#F44336"; // Red
        } else {
            return "#9E9E9E"; // Gray
        }
    }

    /// @notice Internal function to check if a token has been minted
    /// @dev Uses OpenZeppelin's _ownerOf to determine token existence efficiently.
    /// @param tokenId Token ID to check for existence
    /// @return exists Whether the token has been minted and has an owner
    /// @custom:internal Used by tokenExists modifier for validation
    function _exists(uint256 tokenId) internal view returns (bool exists) {
        return _ownerOf(tokenId) != address(0);
    }
}
