// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract HermisSBTTest is Test {
    HermisSBT internal hermisSBT;
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    MockToken internal stakeToken;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant ADMIN = address(0x10);

    string internal constant BASE_URI = "https://hermis.ai/metadata/";
    string internal constant CONTRACT_URI = "https://hermis.ai/contract-metadata";

    function setUp() public {
        // Fund test accounts
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(ADMIN, 100 ether);

        // Deploy Treasury
        treasury = new Treasury(ADMIN);

        // Deploy mock stake token
        stakeToken = new MockToken();

        // Deploy HermisSBT
        hermisSBT = new HermisSBT(ADMIN, "Hermis SBT", "HSBT", BASE_URI, CONTRACT_URI);

        // Deploy ReputationManager
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        // Note: Not initializing users here to avoid automatic SBT minting
        // Individual tests will initialize users as needed
    }

    // Helper function to initialize a user (which mints SBT automatically)
    function _initializeUser(address user) internal {
        vm.prank(ADMIN);
        reputationManager.initializeUser(user);
    }

    function testMint_Success() public {
        // Initialize user first (which will mint SBT)
        _initializeUser(ALICE);

        // Check that SBT was automatically minted
        assertTrue(hermisSBT.hasSBT(ALICE));
        uint256 tokenId = hermisSBT.getUserTokenId(ALICE);

        // Verify token was minted
        assertEq(hermisSBT.ownerOf(tokenId), ALICE);
        assertEq(hermisSBT.balanceOf(ALICE), 1);
        assertTrue(hermisSBT.hasSBT(ALICE));
        assertEq(hermisSBT.getUserTokenId(ALICE), tokenId);
    }

    function testMint_RevertWhenNotAuthorized() public {
        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.mint(BOB);
    }

    function testMint_RevertWhenAlreadyExists() public {
        // Initialize user first (which will mint SBT)
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Try to mint again directly - should revert
        vm.prank(address(reputationManager));
        vm.expectRevert();
        hermisSBT.mint(ALICE);
    }

    function testUpdateReputation_Success() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);
        assertEq(tokenId, 1, "unexpected token id");

        vm.prank(address(reputationManager));
        hermisSBT.updateReputation(ALICE, 1500, DataTypes.UserStatus.NORMAL);

        // Verify update was recorded (through getUserData)
        (, uint256 reputation, DataTypes.UserStatus status, , bool exists) = hermisSBT.getUserData(ALICE);
        assertEq(reputation, 1500);
        assertEq(uint256(status), uint256(DataTypes.UserStatus.NORMAL));
        assertTrue(exists);
    }

    function testUpdateCategoryScore_Success() public {
        vm.prank(address(reputationManager));
        hermisSBT.mint(ALICE);

        string memory category = "development";
        uint256 newScore = 150;

        vm.prank(address(reputationManager));
        hermisSBT.updateCategoryScore(ALICE, category, newScore);

        // Verify category score was updated
        uint256 score = hermisSBT.getUserCategoryScore(ALICE, category);
        assertEq(score, newScore);
    }

    function testUpdateStakeAmount_Success() public {
        vm.prank(address(reputationManager));
        hermisSBT.mint(ALICE);

        uint256 newStakeAmount = 5 ether;

        vm.prank(address(reputationManager));
        hermisSBT.updateStakeAmount(ALICE, newStakeAmount);

        // Verify stake amount was updated (through getUserData)
        (, , , uint256 stakeAmount, ) = hermisSBT.getUserData(ALICE);
        assertEq(stakeAmount, newStakeAmount);
    }

    function testRefreshMetadata_Success() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        vm.prank(address(reputationManager));
        hermisSBT.refreshMetadata(tokenId);

        // Should not revert and token should still exist
        assertEq(hermisSBT.ownerOf(tokenId), ALICE);
    }

    function testRefreshMetadata_RevertWhenNotOwner() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        vm.prank(BOB);
        vm.expectRevert();
        hermisSBT.refreshMetadata(tokenId);
    }

    function testGetUserAllCategoryScores() public {
        vm.prank(address(reputationManager));
        hermisSBT.mint(ALICE);

        // Add multiple category scores
        vm.prank(address(reputationManager));
        hermisSBT.updateCategoryScore(ALICE, "development", 150);

        vm.prank(address(reputationManager));
        hermisSBT.updateCategoryScore(ALICE, "design", 100);

        (string[] memory categories, uint256[] memory scores) = hermisSBT.getUserAllCategoryScores(ALICE);

        assertEq(categories.length, 2);
        assertEq(scores.length, 2);
        assertEq(categories[0], "development");
        assertEq(scores[0], 150);
        assertEq(categories[1], "design");
        assertEq(scores[1], 100);
    }

    function testTokenURI() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        string memory uri = hermisSBT.tokenURI(tokenId);

        // Should contain base URI
        assertTrue(bytes(uri).length > 0);
    }

    function testTokenURI_RevertWhenTokenNotExists() public {
        vm.expectRevert();
        hermisSBT.tokenURI(999); // Non-existent token
    }

    function testContractURI() public view {
        string memory uri = hermisSBT.contractURI();
        assertEq(uri, CONTRACT_URI);
    }

    function testSetBaseURI() public {
        string memory newBaseURI = "https://newuri.com/";

        vm.prank(ADMIN);
        hermisSBT.setBaseURI(newBaseURI);

        // Verify through minting and checking token URI
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        string memory uri = hermisSBT.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
    }

    function testSetBaseURI_RevertWhenNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.setBaseURI("https://newuri.com/");
    }

    function testSetContractURI() public {
        string memory newContractURI = "https://newcontract.com/metadata";

        vm.prank(ADMIN);
        hermisSBT.setContractURI(newContractURI);

        assertEq(hermisSBT.contractURI(), newContractURI);
    }

    function testTransferFrom_RevertSoulbound() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.transferFrom(ALICE, BOB, tokenId);
    }

    function testSafeTransferFrom_RevertSoulbound() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.safeTransferFrom(ALICE, BOB, tokenId, "");
    }

    function testApprove_RevertSoulbound() public {
        vm.prank(address(reputationManager));
        uint256 tokenId = hermisSBT.mint(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.approve(BOB, tokenId);
    }

    function testSetApprovalForAll_RevertSoulbound() public {
        vm.prank(ALICE);
        vm.expectRevert();
        hermisSBT.setApprovalForAll(BOB, true);
    }

    function testSupportsInterface() public view {
        // Should support ERC721
        assertTrue(hermisSBT.supportsInterface(0x80ac58cd));

        // Should support ERC721Metadata
        assertTrue(hermisSBT.supportsInterface(0x5b5e139f));

        // Should support ERC165
        assertTrue(hermisSBT.supportsInterface(0x01ffc9a7));
    }
}
