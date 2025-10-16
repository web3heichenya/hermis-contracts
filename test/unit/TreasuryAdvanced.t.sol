// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Reward Token", "MRT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title TreasuryAdvancedTest
/// @notice Advanced Treasury tests - covering fund management edge cases
contract TreasuryAdvancedTest is Test {
    Treasury internal treasury;
    MockToken internal rewardToken;

    address internal constant ADMIN = address(0x10);
    address internal constant AUTHORIZED_CONTRACT = address(0x20);
    address internal constant PLATFORM = address(0x30);
    address internal constant USER = address(0x40);

    function setUp() public {
        vm.deal(ADMIN, 100 ether);
        vm.deal(AUTHORIZED_CONTRACT, 100 ether);
        vm.deal(PLATFORM, 100 ether);
        vm.deal(USER, 100 ether);

        treasury = new Treasury(ADMIN);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(AUTHORIZED_CONTRACT, true);

        rewardToken = new MockToken();
        rewardToken.mint(AUTHORIZED_CONTRACT, 1_000 ether);
        rewardToken.mint(USER, 1_000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           AUTHORIZATION CONTROL TESTS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test operations blocked after authorization revoked
    function testAuthorization_RevokeAccess() public {
        // Deposit funds
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        // Revoke authorization
        vm.prank(ADMIN);
        treasury.setAuthorizedContract(AUTHORIZED_CONTRACT, false);

        assertFalse(treasury.isAuthorized(AUTHORIZED_CONTRACT));

        // Try to withdraw - should revert
        vm.prank(AUTHORIZED_CONTRACT);
        vm.expectRevert();
        treasury.withdrawTaskReward(1, USER, address(0), 0.5 ether);
    }

    /// @notice Test access restored after re-authorization
    function testAuthorization_RestoreAccess() public {
        // Deposit funds
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        // Revoke then restore authorization
        vm.prank(ADMIN);
        treasury.setAuthorizedContract(AUTHORIZED_CONTRACT, false);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(AUTHORIZED_CONTRACT, true);

        assertTrue(treasury.isAuthorized(AUTHORIZED_CONTRACT));

        // Should be able to withdraw now
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(1, USER, address(0), 0.5 ether);

        assertEq(USER.balance, 100.5 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           PLATFORM FEE MANAGEMENT TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test platform fee accumulation
    function testPlatformFee_Accumulation() public {
        // Allocate platform fees from multiple sources
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), 0.1 ether);

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), 0.2 ether);

        uint256 totalFees = treasury.getPlatformFeeBalance(address(0));
        assertEq(totalFees, 0.3 ether);
    }

    /// @notice Test platform fee withdrawal
    function testPlatformFee_Withdrawal() public {
        // First send ETH to treasury
        vm.deal(address(treasury), 1 ether);

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), 1 ether);

        uint256 balanceBefore = PLATFORM.balance;

        vm.prank(ADMIN);
        treasury.withdrawPlatformFees(PLATFORM, address(0), 0.5 ether);

        assertEq(PLATFORM.balance - balanceBefore, 0.5 ether);
        assertEq(treasury.getPlatformFeeBalance(address(0)), 0.5 ether);
    }

    /// @notice Test only admin can withdraw platform fees
    function testPlatformFee_OnlyAdminCanWithdraw() public {
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), 1 ether);

        vm.prank(USER);
        vm.expectRevert();
        treasury.withdrawPlatformFees(USER, address(0), 0.5 ether);
    }

    /// @notice Test ERC20 platform fees
    function testPlatformFee_ERC20Token() public {
        // First transfer tokens to treasury
        vm.prank(AUTHORIZED_CONTRACT);
        rewardToken.transfer(address(treasury), 5 ether);

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(rewardToken), 5 ether);

        assertEq(treasury.getPlatformFeeBalance(address(rewardToken)), 5 ether);

        vm.prank(ADMIN);
        treasury.withdrawPlatformFees(PLATFORM, address(rewardToken), 2 ether);

        assertEq(rewardToken.balanceOf(PLATFORM), 2 ether);
        assertEq(treasury.getPlatformFeeBalance(address(rewardToken)), 3 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           MIXED TOKEN SCENARIO TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test simultaneous management of ETH and multiple ERC20 tokens
    function testMixedTokens_SimultaneousManagement() public {
        MockToken token2 = new MockToken();
        token2.mint(AUTHORIZED_CONTRACT, 1000 ether);

        // Deposit ETH for task 1
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        // Deposit rewardToken for task 2
        vm.startPrank(AUTHORIZED_CONTRACT);
        rewardToken.approve(address(treasury), 10 ether);
        treasury.depositTaskReward(2, address(rewardToken), 5 ether);
        vm.stopPrank();

        // Deposit token2 for task 3
        vm.startPrank(AUTHORIZED_CONTRACT);
        token2.approve(address(treasury), 10 ether);
        treasury.depositTaskReward(3, address(token2), 3 ether);
        vm.stopPrank();

        // Verify balances
        assertEq(treasury.getBalance(address(0), "task", 1), 1 ether);
        assertEq(treasury.getBalance(address(rewardToken), "task", 2), 5 ether);
        assertEq(treasury.getBalance(address(token2), "task", 3), 3 ether);

        // Verify total balances
        assertEq(treasury.getTotalBalance(address(0)), 1 ether);
        assertEq(treasury.getTotalBalance(address(rewardToken)), 5 ether);
        assertEq(treasury.getTotalBalance(address(token2)), 3 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           BALANCE TRACKING TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test separation of locked and available balances
    function testBalance_LockedVsAvailable() public {
        // Deposit for task (locked)
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 5 ether}(1, address(0), 5 ether);

        uint256 totalLocked = treasury.getTotalLocked(address(0));
        assertEq(totalLocked, 5 ether);

        // Withdraw some
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(1, USER, address(0), 2 ether);

        uint256 lockedAfter = treasury.getTotalLocked(address(0));
        assertEq(lockedAfter, 3 ether);
    }

    /// @notice Test balance isolation between multiple tasks
    function testBalance_TaskIsolation() public {
        // Task 1
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        // Task 2
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 2 ether}(2, address(0), 2 ether);

        assertEq(treasury.getBalance(address(0), "task", 1), 1 ether);
        assertEq(treasury.getBalance(address(0), "task", 2), 2 ether);

        // Withdrawing from task 1 should not affect task 2
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(1, USER, address(0), 1 ether);

        assertEq(treasury.getBalance(address(0), "task", 1), 0);
        assertEq(treasury.getBalance(address(0), "task", 2), 2 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           EMERGENCY RESCUE TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test emergency ETH withdrawal (admin only)
    function testEmergencyWithdraw_ETH() public {
        // Send ETH directly to treasury (not through deposit)
        vm.deal(address(treasury), 10 ether);

        uint256 adminBalanceBefore = ADMIN.balance;

        // Pause treasury first (required for emergency withdraw)
        vm.prank(ADMIN);
        treasury.setPaused(true);

        vm.prank(ADMIN);
        treasury.emergencyWithdraw(address(0), ADMIN, 5 ether);

        assertEq(ADMIN.balance - adminBalanceBefore, 5 ether);
    }

    /// @notice Test emergency ERC20 withdrawal (admin only)
    function testEmergencyWithdraw_ERC20() public {
        // Transfer tokens directly to treasury
        rewardToken.mint(address(treasury), 100 ether);

        // Pause treasury first (required for emergency withdraw)
        vm.prank(ADMIN);
        treasury.setPaused(true);

        vm.prank(ADMIN);
        treasury.emergencyWithdraw(address(rewardToken), ADMIN, 50 ether);

        assertEq(rewardToken.balanceOf(ADMIN), 50 ether);
    }

    /// @notice Test non-admin cannot emergency withdraw
    function testEmergencyWithdraw_OnlyAdmin() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(USER);
        vm.expectRevert();
        treasury.emergencyWithdraw(address(0), USER, 5 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           ERROR HANDLING TESTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test withdrawal fails when balance insufficient
    function testWithdraw_InsufficientBalance() public {
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        vm.prank(AUTHORIZED_CONTRACT);
        vm.expectRevert();
        treasury.withdrawTaskReward(1, USER, address(0), 2 ether);
    }

    /// @notice Test handling of ETH transfer failures
    function testWithdraw_ETHTransferFailure() public {
        // Create a contract that rejects ETH
        RejectEth rejecter = new RejectEth();

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        vm.prank(AUTHORIZED_CONTRACT);
        vm.expectRevert();
        treasury.withdrawTaskReward(1, address(rejecter), address(0), 1 ether);
    }
}

/// @notice Contract that rejects ETH transfers
contract RejectEth {
    receive() external payable {
        revert("Rejecting ETH");
    }
}
