// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ReputationManager} from "../../src/core/ReputationManager.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {HermisSBT} from "../../src/core/HermisSBT.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ReputationManagerTest
/// @notice Basic unit tests for ReputationManager contract
contract ReputationManagerTest is Test {
    ReputationManager internal reputationManager;
    Treasury internal treasury;
    HermisSBT internal hermisSBT;
    MockToken internal stakeToken;

    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant ADMIN = address(0x10);

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
        hermisSBT = new HermisSBT(
            ADMIN,
            "Hermis SBT",
            "HSBT",
            "https://hermis.ai/metadata/",
            "https://hermis.ai/contract-metadata"
        );

        // Deploy ReputationManager with stake token
        reputationManager = new ReputationManager(ADMIN, address(treasury), address(stakeToken));

        // Connect contracts
        vm.prank(ADMIN);
        hermisSBT.setReputationManager(address(reputationManager));

        vm.prank(ADMIN);
        reputationManager.setHermisSBT(address(hermisSBT));

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(address(reputationManager), true);

        // Give ALICE some tokens for testing
        stakeToken.mint(ALICE, 10 ether);
        stakeToken.mint(BOB, 10 ether);
    }

    function testInitializeUser_Success() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        (
            uint256 reputation,
            DataTypes.UserStatus status,
            uint256 stakedAmount,
            bool canUnstake,
            uint256 unlockTime
        ) = reputationManager.getUserReputation(ALICE);

        assertEq(reputation, 1000); // Default reputation
        assertEq(uint256(status), uint256(DataTypes.UserStatus.NORMAL));
        assertEq(stakedAmount, 0);
        assertFalse(canUnstake); // No stake, so can't unstake
        assertEq(unlockTime, 0);
    }

    function testStake_Success() public {
        // Initialize user first
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        uint256 stakeAmount = 1 ether;

        // Approve ReputationManager to spend tokens
        vm.prank(ALICE);
        stakeToken.approve(address(reputationManager), stakeAmount);

        // Stake tokens
        vm.prank(ALICE);
        reputationManager.stake(stakeAmount, address(stakeToken));

        (, , uint256 stakedAmount, , ) = reputationManager.getUserReputation(ALICE);
        assertEq(stakedAmount, stakeAmount);
    }

    function testReputationUpdate() public {
        // Initialize user first
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Update reputation downward to test status change
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Test penalty");

        (uint256 reputation, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(ALICE);

        assertEq(reputation, 500); // 1000 - 500
        assertEq(uint256(status), uint256(DataTypes.UserStatus.AT_RISK)); // Should be at-risk now
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           CATEGORY SCORE MANAGEMENT TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test single category score claiming
    function testCategoryScore_SingleCategoryClaim() public {
        // Initialize user
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Admin adds pending category score
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 850);

        // User claims the category score
        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 850);

        // Verify the category score is now active
        uint256 score = reputationManager.getCategoryScore(ALICE, "development");
        assertEq(score, 850);
    }

    /// @notice Test multiple category scores for one user
    function testCategoryScore_MultipleCategories() public {
        // Initialize user
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Add scores in different categories
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 800);
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "design", 750);
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "marketing", 600);

        // Claim all category scores
        vm.startPrank(ALICE);
        reputationManager.claimCategoryScore("development", 800);
        reputationManager.claimCategoryScore("design", 750);
        reputationManager.claimCategoryScore("marketing", 600);
        vm.stopPrank();

        // Verify all category scores
        assertEq(reputationManager.getCategoryScore(ALICE, "development"), 800);
        assertEq(reputationManager.getCategoryScore(ALICE, "design"), 750);
        assertEq(reputationManager.getCategoryScore(ALICE, "marketing"), 600);
    }

    /// @notice Test incremental category score increases
    function testCategoryScore_IncrementalIncreases() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Add and claim initial score
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 700);
        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 700);

        assertEq(reputationManager.getCategoryScore(ALICE, "development"), 700);

        // Add and claim additional score
        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 150);
        vm.prank(ALICE);
        reputationManager.claimCategoryScore("development", 150);

        // Score should be cumulative
        assertEq(reputationManager.getCategoryScore(ALICE, "development"), 850);
    }

    /// @notice Test claiming more than pending score should revert
    function testCategoryScore_ClaimExcessFails() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ADMIN);
        reputationManager.addPendingCategoryScore(ALICE, "development", 500);

        // Attempt to claim more than available
        vm.prank(ALICE);
        vm.expectRevert();
        reputationManager.claimCategoryScore("development", 600);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           REPUTATION STATUS TRANSITION TESTS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test normal -> at-risk status transition
    function testReputationStatus_NormalToAtRisk() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        (, DataTypes.UserStatus initialStatus, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(uint256(initialStatus), uint256(DataTypes.UserStatus.NORMAL));

        // Reduce reputation to at-risk level (below 600)
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -450, "Quality issues");

        (uint256 rep, DataTypes.UserStatus newStatus, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 550); // 1000 - 450
        assertEq(uint256(newStatus), uint256(DataTypes.UserStatus.AT_RISK));
    }

    /// @notice Test at-risk -> blacklisted status transition
    function testReputationStatus_AtRiskToBlacklisted() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Drop to at-risk
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "First penalty");

        (, DataTypes.UserStatus status1, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(uint256(status1), uint256(DataTypes.UserStatus.AT_RISK));

        // Drop to blacklisted (reputation <= 0)
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Severe violation");

        (uint256 rep, DataTypes.UserStatus status2, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 0);
        assertEq(uint256(status2), uint256(DataTypes.UserStatus.BLACKLISTED));
    }

    /// @notice Test blacklisted -> at-risk recovery
    function testReputationStatus_BlacklistedToAtRisk() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Drop to blacklisted
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -1000, "Major violation");

        (, DataTypes.UserStatus status1, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(uint256(status1), uint256(DataTypes.UserStatus.BLACKLISTED));

        // Restore some reputation through arbitration or good behavior
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, 300, "Arbitration approved");

        (uint256 rep, DataTypes.UserStatus status2, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 300);
        assertEq(uint256(status2), uint256(DataTypes.UserStatus.AT_RISK));
    }

    /// @notice Test at-risk -> normal recovery
    function testReputationStatus_AtRiskToNormal() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Drop to at-risk
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "Poor performance");

        // Improve reputation back to normal
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, 200, "Quality improvement");

        (uint256 rep, DataTypes.UserStatus status, , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 700); // 1000 - 500 + 200
        assertEq(uint256(status), uint256(DataTypes.UserStatus.NORMAL));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              STAKING MECHANISM TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test staking requirement calculation for at-risk users
    function testStaking_RequiredStakeCalculation() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Reduce reputation to at-risk level
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -500, "At-risk user");

        // Check required stake amount (should be proportional to reputation deficit)
        uint256 requiredStake = reputationManager.getRequiredStakeAmount(ALICE);
        assertTrue(requiredStake > 0, "At-risk user should require stake");
    }

    /// @notice Test full unstake workflow with lock period
    function testStaking_UnstakeWorkflow() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Stake tokens
        uint256 stakeAmount = 5 ether;
        vm.startPrank(ALICE);
        stakeToken.approve(address(reputationManager), stakeAmount);
        reputationManager.stake(stakeAmount, address(stakeToken));
        vm.stopPrank();

        (, , uint256 stakedAmount1, , ) = reputationManager.getUserReputation(ALICE);
        assertEq(stakedAmount1, stakeAmount);

        // Request unstake
        vm.prank(ALICE);
        reputationManager.requestUnstake();

        // Try to unstake immediately (should fail)
        vm.prank(ALICE);
        vm.expectRevert();
        reputationManager.unstake();

        // Fast forward past lock period
        vm.warp(block.timestamp + 7 days + 1);

        // Now unstake should succeed
        vm.prank(ALICE);
        reputationManager.unstake();

        (, , uint256 stakedAmount2, , ) = reputationManager.getUserReputation(ALICE);
        assertEq(stakedAmount2, 0);
    }

    /// @notice Test multiple stake increases
    function testStaking_MultipleStakeIncreases() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // First stake
        vm.startPrank(ALICE);
        stakeToken.approve(address(reputationManager), 10 ether);
        reputationManager.stake(2 ether, address(stakeToken));
        vm.stopPrank();

        (, , uint256 staked1, , ) = reputationManager.getUserReputation(ALICE);
        assertEq(staked1, 2 ether);

        // Second stake
        vm.prank(ALICE);
        reputationManager.stake(3 ether, address(stakeToken));

        (, , uint256 staked2, , ) = reputationManager.getUserReputation(ALICE);
        assertEq(staked2, 5 ether); // Cumulative
    }

    /// @notice Test staking with insufficient balance reverts
    function testStaking_InsufficientBalanceReverts() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(BOB);

        // BOB has 10 ether, try to stake more
        vm.startPrank(BOB);
        stakeToken.approve(address(reputationManager), 20 ether);
        vm.expectRevert();
        reputationManager.stake(20 ether, address(stakeToken));
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              EDGE CASES AND BOUNDARY TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test reputation cannot exceed MAX_REPUTATION
    function testReputation_CannotExceedMaximum() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Try to increase beyond max (10000)
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, 15000, "Excessive reward");

        (uint256 rep, , , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 10000); // Capped at MAX_REPUTATION
    }

    /// @notice Test reputation cannot go below 0
    function testReputation_CannotGoBelowZero() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Try to decrease below 0
        vm.prank(ADMIN);
        reputationManager.updateReputation(ALICE, -2000, "Severe penalty");

        (uint256 rep, , , , ) = reputationManager.getUserReputation(ALICE);
        assertEq(rep, 0); // Floored at 0
    }

    /// @notice Test double initialization is safe (idempotent)
    function testInitialization_Idempotent() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        (uint256 rep1, , , , ) = reputationManager.getUserReputation(ALICE);

        // Initialize again
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        (uint256 rep2, , , , ) = reputationManager.getUserReputation(ALICE);

        // Reputation should not reset
        assertEq(rep1, rep2);
    }

    /// @notice Test unauthorized reputation update should fail
    function testReputation_UnauthorizedUpdateFails() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // BOB (not authorized) tries to update ALICE's reputation
        vm.prank(BOB);
        vm.expectRevert();
        reputationManager.updateReputation(ALICE, 100, "Unauthorized");
    }

    /// @notice Test concurrent operations from multiple users
    function testConcurrency_MultipleUsersSimultaneous() public {
        address user1 = address(0x101);
        address user2 = address(0x102);
        address user3 = address(0x103);

        // Initialize all users
        vm.startPrank(ADMIN);
        reputationManager.initializeUser(user1);
        reputationManager.initializeUser(user2);
        reputationManager.initializeUser(user3);

        // Update reputations simultaneously
        reputationManager.updateReputation(user1, -200, "User 1 penalty");
        reputationManager.updateReputation(user2, 300, "User 2 bonus");
        reputationManager.updateReputation(user3, -500, "User 3 penalty");
        vm.stopPrank();

        // Verify all updates were applied correctly
        (uint256 rep1, , , , ) = reputationManager.getUserReputation(user1);
        (uint256 rep2, , , , ) = reputationManager.getUserReputation(user2);
        (uint256 rep3, , , , ) = reputationManager.getUserReputation(user3);

        assertEq(rep1, 800); // 1000 - 200
        assertEq(rep2, 1300); // 1000 + 300
        assertEq(rep3, 500); // 1000 - 500
    }

    /// @notice Test requesting unstake without stake should fail
    function testUnstake_WithoutStakeFails() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        reputationManager.requestUnstake();
    }

    /// @notice Test double unstake request should fail
    function testUnstake_DoubleRequestFails() public {
        vm.prank(ADMIN);
        reputationManager.initializeUser(ALICE);

        // Stake first
        vm.startPrank(ALICE);
        stakeToken.approve(address(reputationManager), 5 ether);
        reputationManager.stake(5 ether, address(stakeToken));

        // Request unstake
        reputationManager.requestUnstake();

        // Request again should fail
        vm.expectRevert();
        reputationManager.requestUnstake();
        vm.stopPrank();
    }
}
