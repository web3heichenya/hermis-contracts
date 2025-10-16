// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../../src/core/Treasury.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Reward Token", "MRT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title TreasuryTest
/// @notice Basic unit tests for Treasury contract
/// @dev Tests core treasury functionality with simple setup
/// @author Hermis Team
contract TreasuryTest is Test {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address internal constant ADMIN = address(0x10);
    address internal constant AUTHORIZED_CONTRACT = address(0x20);
    address internal constant USER = address(0x30);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    Treasury internal treasury;
    MockToken internal rewardToken;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        SETUP                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setUp() public {
        // Fund test accounts
        vm.deal(ADMIN, 100 ether);
        vm.deal(AUTHORIZED_CONTRACT, 100 ether);
        vm.deal(USER, 100 ether);

        // Deploy treasury
        treasury = new Treasury(ADMIN);

        // Set up authorized contract
        vm.prank(ADMIN);
        treasury.setAuthorizedContract(AUTHORIZED_CONTRACT, true);

        // Deploy mock ERC20 token and mint balances
        rewardToken = new MockToken();
        rewardToken.mint(AUTHORIZED_CONTRACT, 1_000 ether);
        rewardToken.mint(USER, 1_000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    AUTHORIZATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testSetAuthorizedContract_Success() public {
        address newContract = address(0x40);

        vm.prank(ADMIN);
        treasury.setAuthorizedContract(newContract, true);

        assertTrue(treasury.isAuthorized(newContract), "Contract should be authorized");
    }

    function testSetAuthorizedContract_RevertWhenNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        treasury.setAuthorizedContract(address(0x40), true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      DEPOSIT TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testDepositTaskReward_SuccessWithETH() public {
        uint256 taskId = 1;
        uint256 amount = 1 ether;

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: amount}(taskId, address(0), amount);

        uint256 balance = treasury.getBalance(address(0), "task", taskId);
        assertEq(balance, amount, "Task reward should be deposited");

        uint256 totalLocked = treasury.getTotalLocked(address(0));
        assertEq(totalLocked, amount, "Total locked should be updated");
    }

    function testDepositTaskReward_RevertWhenNotAuthorized() public {
        vm.prank(USER);
        vm.expectRevert();
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);
    }

    function testDepositTaskReward_RevertWhenPaused() public {
        // Pause treasury
        vm.prank(ADMIN);
        treasury.setPaused(true);

        vm.prank(AUTHORIZED_CONTRACT);
        vm.expectRevert();
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);
    }

    function testDepositTaskReward_WithERC20() public {
        uint256 taskId = 2;
        uint256 amount = 250 ether;

        vm.startPrank(AUTHORIZED_CONTRACT);
        rewardToken.approve(address(treasury), amount);
        treasury.depositTaskReward(taskId, address(rewardToken), amount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(rewardToken), "task", taskId), amount);
        assertEq(treasury.getTotalLocked(address(rewardToken)), amount);
        assertEq(rewardToken.balanceOf(address(treasury)), amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     WITHDRAWAL TESTS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testWithdrawTaskReward_Success() public {
        uint256 taskId = 1;
        uint256 amount = 1 ether;

        // First deposit
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: amount}(taskId, address(0), amount);

        uint256 userBalanceBefore = USER.balance;

        // Then withdraw
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(taskId, USER, address(0), amount);

        assertEq(USER.balance, userBalanceBefore + amount, "User should receive withdrawal");

        uint256 balance = treasury.getBalance(address(0), "task", taskId);
        assertEq(balance, 0, "Task balance should be zero after withdrawal");
    }

    function testWithdrawTaskReward_RevertWhenInsufficientBalance() public {
        vm.prank(AUTHORIZED_CONTRACT);
        vm.expectRevert();
        treasury.withdrawTaskReward(1, USER, address(0), 1 ether);
    }

    function testWithdrawTaskReward_WithERC20() public {
        uint256 taskId = 3;
        uint256 amount = 150 ether;

        vm.startPrank(AUTHORIZED_CONTRACT);
        rewardToken.approve(address(treasury), amount);
        treasury.depositTaskReward(taskId, address(rewardToken), amount);
        vm.stopPrank();

        uint256 userBalanceBefore = rewardToken.balanceOf(USER);

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(taskId, USER, address(rewardToken), amount);

        assertEq(rewardToken.balanceOf(USER), userBalanceBefore + amount);
        assertEq(treasury.getBalance(address(rewardToken), "task", taskId), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PLATFORM FEE TESTS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testAllocatePlatformFee_Success() public {
        uint256 amount = 0.1 ether;

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), amount);

        uint256 feeBalance = treasury.getPlatformFeeBalance(address(0));
        assertEq(feeBalance, amount, "Platform fee should be allocated");
    }

    function testAllocatePlatformFee_WithERC20() public {
        uint256 amount = 40 ether;

        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(rewardToken), amount);

        assertEq(treasury.getPlatformFeeBalance(address(rewardToken)), amount);

        // Fund treasury with ERC20 to allow withdrawal
        rewardToken.mint(address(treasury), amount);
        uint256 adminBalanceBefore = rewardToken.balanceOf(ADMIN);

        vm.prank(ADMIN);
        treasury.withdrawPlatformFees(ADMIN, address(rewardToken), amount);

        assertEq(rewardToken.balanceOf(ADMIN), adminBalanceBefore + amount);
        assertEq(treasury.getPlatformFeeBalance(address(rewardToken)), 0);
    }

    function testWithdrawPlatformFees_Success() public {
        uint256 amount = 0.1 ether;

        // First allocate fees
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(0), amount);

        // Fund treasury for withdrawal
        vm.deal(address(treasury), amount);

        uint256 adminBalanceBefore = ADMIN.balance;

        // Withdraw fees
        vm.prank(ADMIN);
        treasury.withdrawPlatformFees(ADMIN, address(0), amount);

        assertGt(ADMIN.balance, adminBalanceBefore, "Admin should receive fees");

        uint256 feeBalance = treasury.getPlatformFeeBalance(address(0));
        assertEq(feeBalance, 0, "Fee balance should be zero after withdrawal");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EMERGENCY TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testEmergencyWithdraw_Success() public {
        uint256 amount = 1 ether;

        // Fund treasury
        vm.deal(address(treasury), amount);

        // Pause treasury for emergency
        vm.prank(ADMIN);
        treasury.setPaused(true);

        uint256 adminBalanceBefore = ADMIN.balance;

        // Emergency withdraw
        vm.prank(ADMIN);
        treasury.emergencyWithdraw(address(0), ADMIN, amount);

        assertGt(ADMIN.balance, adminBalanceBefore, "Admin should receive emergency withdrawal");
    }

    function testEmergencyWithdraw_RevertWhenNotPaused() public {
        vm.deal(address(treasury), 1 ether);

        vm.prank(ADMIN);
        vm.expectRevert();
        treasury.emergencyWithdraw(address(0), ADMIN, 1 ether);
    }

    function testGetBalanceAcrossPurposes() public {
        uint256 taskId = 11;
        uint256 stakeAmount = 60 ether;
        uint256 taskAmount = 90 ether;

        vm.startPrank(AUTHORIZED_CONTRACT);
        rewardToken.approve(address(treasury), stakeAmount + taskAmount);
        treasury.depositTaskReward(taskId, address(rewardToken), taskAmount);
        treasury.depositStake(USER, address(rewardToken), stakeAmount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(rewardToken), "task", taskId), taskAmount);
        assertEq(treasury.getBalance(address(rewardToken), "stake", uint256(uint160(USER))), stakeAmount);
        assertEq(treasury.getTotalLocked(address(rewardToken)), taskAmount + stakeAmount);
    }

    function testEmergencyWithdraw_WithPlatformFeesButNoLiquidity() public {
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.allocatePlatformFee(address(rewardToken), 25 ether);

        vm.prank(ADMIN);
        treasury.setPaused(true);

        vm.prank(ADMIN);
        vm.expectRevert();
        treasury.emergencyWithdraw(address(rewardToken), ADMIN, 10 ether);

        assertEq(treasury.getPlatformFeeBalance(address(rewardToken)), 25 ether);
        assertEq(rewardToken.balanceOf(address(treasury)), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGetTotalBalance() public {
        uint256 amount = 5 ether;
        vm.deal(address(treasury), amount);

        uint256 totalBalance = treasury.getTotalBalance(address(0));
        assertEq(totalBalance, amount, "Should return correct ETH balance");
    }

    function testIsPaused() public {
        assertFalse(treasury.paused(), "Should not be paused initially");

        vm.prank(ADMIN);
        treasury.setPaused(true);

        assertTrue(treasury.paused(), "Should be paused after setting");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         GAS TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testGas_DepositTaskReward() public {
        uint256 gasBefore = gasleft();
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 150_000, "Deposit gas usage too high");
        emit log_named_uint("DepositTaskReward gas used", gasUsed);
    }

    function testGas_WithdrawTaskReward() public {
        // Setup
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.depositTaskReward{value: 1 ether}(1, address(0), 1 ether);

        uint256 gasBefore = gasleft();
        vm.prank(AUTHORIZED_CONTRACT);
        treasury.withdrawTaskReward(1, USER, address(0), 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 100_000, "Withdraw gas usage too high");
        emit log_named_uint("WithdrawTaskReward gas used", gasUsed);
    }
}
